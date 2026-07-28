/// Ports packages/perf-monitor/src/perf-monitor/utils/PerfMonitorController.ts
/// (the B1 hybrid sampler; remote-mirror / reaFps / stall-backfill are dropped).
///
/// **Pure Flutter/Dart — no native code, no FFI, no plugins.** The one thing
/// that reshapes the whole port (spike finding): `addTimingsCallback` only
/// fires while frames are produced, so an idle app renders nothing. Hence a
/// HYBRID sampler — FrameTiming feeds FPS/jank; a 250 ms `Timer.periodic` reads
/// RSS (+ Android CPU) so memory keeps flowing at rest. FPS derivation
/// (spike parity table):
///   uiFps = delivered frame rate = frames-this-tick ÷ elapsed, capped at
///           refresh; idle = last-held (so idle never fabricates UI jank).
///   jsFps = avg over this-tick frames of min(refresh, 1000/buildMs); idle =
///           refresh (Dart thread free = healthy).
/// The HUD *displays* "—" for FPS when no frames arrived within the window —
/// computed from [lastFrameAtMs], independent of the held sample value.
///
/// Backpressure parity: sampling runs iff enabled (HUD) OR remoteSampling
/// (desktop) OR liveViewers>0 (open modal). When all are zero the timings
/// callback + Timer are torn down — literally zero overhead.
library;

import 'dart:async';
import 'dart:io' show File, Platform, ProcessInfo;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'perf_types.dart';
import 'fps_derive.dart';
import 'hud_preferences.dart';
import 'proc_cpu.dart';

const int _historySize = 120;
const int _sampleIntervalMs = 250;

/// Android `_SC_CLK_TCK` — universally 100 on Android/Linux.
const int _clockTicksPerSec = 100;

class _FrameRec {
  const _FrameRec(this.buildMicros, this.rasterMicros);
  final int buildMicros;
  final int rasterMicros;
}

typedef PerfSubscriber = void Function(PerfSnapshot snapshot);
typedef EnabledSubscriber = void Function(bool enabled);
typedef SampleTap = void Function(PerfSample sample);

class PerfMonitorController {
  PerfMonitorController._() {
    _capabilities = PerfCapabilities(
      cpu: Platform.isAndroid,
      accurateMemory: true,
      trueUiFps: true,
      reaFrameCallback: false,
    );
    _snapshot = _emptySnapshot();
    // Restore the persisted HUD-enabled flag (load-then-save: don't persist the
    // in-memory default over a saved value during boot).
    // ignore: discarded_futures
    loadHudEnabled().then((persisted) {
      _enabledLoaded = true;
      if (persisted && !_enabled) enable();
    });
  }

  static final PerfMonitorController instance = PerfMonitorController._();

  late PerfCapabilities _capabilities;
  final PerfMode _mode = PerfMode.native;
  late PerfSnapshot _snapshot;

  bool _enabled = false;
  bool _enabledLoaded = false;
  bool _remoteSampling = false;
  int _liveViewers = 0;

  Timer? _timer;
  bool _timingsInstalled = false;

  final List<PerfSample> _history = [];
  List<_FrameRec> _pending = [];
  int _lastFrameAtMs = 0;
  int _lastTickMs = 0;
  double _lastUiFps = 60;

  double _deviceMaxRefreshRate = 60;
  bool _refreshLearned = false;

  // Android /proc CPU deltas.
  int _lastJiffies = -1;
  int _lastCpuAtMs = 0;
  double _lastCpu = 0;
  int get _cores => math.max(1, Platform.numberOfProcessors);

  final Set<PerfSubscriber> _subscribers = {};
  final Set<EnabledSubscriber> _enabledSubscribers = {};
  final Set<SampleTap> _sampleTaps = {};

  /// True while the on-device HUD overlay should suppress itself because the
  /// modal is open (RN `modalOpenState`). Public so the overlay can listen.
  /// Write it through [setModalOpen], never directly.
  final ValueNotifier<bool> modalOpen = ValueNotifier<bool>(false);

  /// Flip the modal-open flag (RN `setModalOpen`).
  ///
  /// RN calls this from a `useEffect`, i.e. AFTER render. The Dart callers are
  /// `initState`/`dispose`, which run DURING the build/unmount phase — writing
  /// the notifier there fires listeners mid-build, and the HUD overlay's
  /// `setState` then throws "setState() called during build". The overlay is
  /// left un-rebuilt, so closing the modal leaves the floating chip invisible
  /// until the app restarts. Deferring to the post-frame callback reproduces
  /// RN's after-render timing and keeps the notification safe.
  void setModalOpen(bool open) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      modalOpen.value = open;
    });
  }

  PerfSnapshot _emptySnapshot() => PerfSnapshot(
        jsFps: 0,
        uiFps: 0,
        cpuUsage: 0,
        memoryUsage: 0,
        deviceMaxRefreshRate: _deviceMaxRefreshRate,
        history: const [],
        mode: _mode,
        capabilities: _capabilities,
      );

  // ── Public getters ─────────────────────────────────────────────────────
  bool isEnabled() => _enabled;
  bool isRemoteSampling() => _remoteSampling;
  PerfMode getMode() => _mode;
  PerfCapabilities getCapabilities() => _capabilities;
  PerfSnapshot getSnapshot() => _snapshot;

  /// Wall-clock of the most recent frame batch (0 = never). The HUD dashes FPS
  /// when this is older than the window.
  int get lastFrameAtMs => _lastFrameAtMs;

  // ── Subscriptions ──────────────────────────────────────────────────────
  void Function() subscribe(PerfSubscriber fn) {
    _subscribers.add(fn);
    fn(_snapshot);
    return () => _subscribers.remove(fn);
  }

  void Function() subscribeEnabled(EnabledSubscriber fn) {
    _enabledSubscribers.add(fn);
    fn(_enabled);
    return () => _enabledSubscribers.remove(fn);
  }

  /// Register a live viewer (the open modal). Starts sampling while present so
  /// live metrics stream even when the HUD is off. The Dart generalization of
  /// RN `tapSamples`. Returns an unregister closure.
  void Function() addLiveViewer() {
    _liveViewers++;
    _ensureSampling();
    return () {
      _liveViewers = math.max(0, _liveViewers - 1);
      _maybeStop();
    };
  }

  /// Tap the raw per-tick sample stream (RN `PerfMonitorController.tapSamples`).
  /// Used by [BenchmarkRecorder] to accumulate a run. Starts sampling while at
  /// least one tap is attached, exactly like a live viewer. Returns a detach
  /// closure.
  void Function() tapSamples(SampleTap fn) {
    _sampleTaps.add(fn);
    _liveViewers++;
    _ensureSampling();
    return () {
      _sampleTaps.remove(fn);
      _liveViewers = math.max(0, _liveViewers - 1);
      _maybeStop();
    };
  }

  // ── Enable / disable (HUD) ─────────────────────────────────────────────
  void enable() {
    if (_enabled) return;
    _enabled = true;
    _ensureSampling();
    _notifyEnabled();
    _persistEnabled();
  }

  void disable() {
    if (!_enabled) return;
    _enabled = false;
    _maybeStop();
    _notifyEnabled();
    _persistEnabled();
  }

  void toggle() => _enabled ? disable() : enable();

  /// Start/stop SILENT sampling for a remote viewer (desktop) WITHOUT showing
  /// the device's own HUD — mirrors RN `setRemoteSampling`. Pushes a snapshot
  /// on the OFF path too so the sync adapter re-emits the new `live.enabled`.
  void setRemoteSampling(bool on) {
    if (_remoteSampling == on) return;
    _remoteSampling = on;
    if (on) {
      _ensureSampling();
    } else {
      _maybeStop();
    }
    for (final fn in [..._subscribers]) {
      try {
        fn(_snapshot);
      } catch (_) {}
    }
  }

  void _persistEnabled() {
    if (!_enabledLoaded) return;
    // ignore: discarded_futures
    saveHudEnabled(_enabled);
  }

  void _notifyEnabled() {
    for (final fn in [..._enabledSubscribers]) {
      try {
        fn(_enabled);
      } catch (_) {}
    }
  }

  // ── Sampling lifecycle ─────────────────────────────────────────────────
  bool get _shouldSample => _enabled || _remoteSampling || _liveViewers > 0;

  void _ensureSampling() {
    if (!_shouldSample) return;
    if (_timer != null) return;
    _learnRefreshRate();
    if (!_timingsInstalled) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _timingsInstalled = true;
    }
    _pending = [];
    _lastTickMs = DateTime.now().millisecondsSinceEpoch;
    _lastFrameAtMs = 0;
    _lastJiffies = -1;
    _lastCpuAtMs = 0;
    _timer = Timer.periodic(
      const Duration(milliseconds: _sampleIntervalMs),
      (_) => _tick(),
    );
    _tick();
  }

  void _maybeStop() {
    if (_shouldSample) return;
    _stopSampling();
  }

  void _stopSampling() {
    _timer?.cancel();
    _timer = null;
    if (_timingsInstalled) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _timingsInstalled = false;
    }
    _pending = [];
    _lastTickMs = 0;
  }

  void _learnRefreshRate() {
    if (_refreshLearned) return;
    try {
      final displays = SchedulerBinding.instance.platformDispatcher.displays;
      if (displays.isNotEmpty) {
        final rate = displays.first.refreshRate;
        if (rate.isFinite && rate > 0) {
          _deviceMaxRefreshRate = clampRefreshRate(rate);
          _refreshLearned = true;
        }
      }
    } catch (_) {
      _deviceMaxRefreshRate = 60;
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    for (final t in timings) {
      _pending.add(_FrameRec(
        t.buildDuration.inMicroseconds,
        t.rasterDuration.inMicroseconds,
      ));
    }
    _lastFrameAtMs = DateTime.now().millisecondsSinceEpoch;
    // Guard against unbounded growth if the timer is starved.
    if (_pending.length > 1000) {
      _pending = _pending.sublist(_pending.length - 1000);
    }
  }

  void _tick() {
    // Late refresh-rate learning (displays may be empty at first _ensureSampling).
    _learnRefreshRate();

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = _lastTickMs == 0 ? _sampleIntervalMs : (now - _lastTickMs);
    final frames = _pending;
    _pending = [];

    final refresh = _deviceMaxRefreshRate;
    final derived = deriveFps(
      frameBuildMicros: [for (final f in frames) f.buildMicros],
      elapsedMs: elapsedMs,
      refresh: refresh,
      lastUiFps: _lastUiFps,
    );
    if (derived.active) _lastUiFps = derived.uiFps;

    final mem = _readMemoryMb();
    final cpu = _readCpu(now);

    final sample = PerfSample(
      timestamp: now,
      jsFps: derived.jsFps,
      uiFps: derived.uiFps,
      cpuUsage: cpu,
      memoryUsage: mem,
      deviceMaxRefreshRate: refresh,
      active: derived.active,
    );

    _history.add(sample);
    if (_history.length > _historySize) _history.removeAt(0);

    _snapshot = PerfSnapshot(
      jsFps: sample.jsFps,
      uiFps: sample.uiFps,
      cpuUsage: sample.cpuUsage,
      memoryUsage: sample.memoryUsage,
      deviceMaxRefreshRate: refresh,
      history: List.of(_history),
      mode: _mode,
      capabilities: _capabilities,
    );
    _lastTickMs = now;

    for (final tap in [..._sampleTaps]) {
      try {
        tap(sample);
      } catch (e, s) {
        if (kDebugMode) {
          debugPrint('[perf-monitor] sample tap threw: $e\n$s');
        }
      }
    }

    for (final fn in [..._subscribers]) {
      try {
        fn(_snapshot);
      } catch (e, s) {
        if (kDebugMode) {
          debugPrint('[perf-monitor] subscriber threw: $e\n$s');
        }
      }
    }
  }

  double _readMemoryMb() {
    try {
      return ProcessInfo.currentRss / (1024 * 1024);
    } catch (_) {
      return _snapshot.memoryUsage;
    }
  }

  double _readCpu(int nowMs) {
    if (!Platform.isAndroid) return 0;
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      final jiffies = parseProcSelfStatJiffies(stat);
      if (jiffies == null) return _lastCpu;
      if (_lastJiffies < 0 || _lastCpuAtMs == 0) {
        _lastJiffies = jiffies;
        _lastCpuAtMs = nowMs;
        return 0;
      }
      final delta = jiffies - _lastJiffies;
      final interval = nowMs - _lastCpuAtMs;
      _lastJiffies = jiffies;
      _lastCpuAtMs = nowMs;
      _lastCpu = procCpuPercent(
        deltaJiffies: delta,
        intervalMs: interval,
        clockTicksPerSec: _clockTicksPerSec,
        cores: _cores,
      );
      return _lastCpu;
    } catch (_) {
      return _lastCpu;
    }
  }
}
