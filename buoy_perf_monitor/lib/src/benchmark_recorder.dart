/// Ports packages/perf-monitor/src/perf-monitor/utils/BenchmarkRecorder.ts.
///
/// Drives a single recording session: taps [PerfMonitorController] for samples,
/// accumulates them, and on stop emits a [BenchmarkReport] with aggregate
/// stats. Owns its own auto-save path so callers can fire-and-forget
/// (`startQuick`), and fires `subscribeSaved` after each persisted run — the
/// signal the automation runner awaits.
///
/// Dropped vs RN (spike parity table): render-commit capture, live render
/// highlights, environment signals, and remote-mirror mode (the desktop drives
/// the device through the sync adapter, not through a mirrored recorder).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'aggregate.dart';
import 'benchmark_storage.dart';
import 'perf_monitor_controller.dart';
import 'perf_types.dart';

typedef RecordingSubscriber = void Function(bool recording);
typedef BenchmarkSavedSubscriber = void Function(BenchmarkReport report);

final math.Random _rng = math.Random();

String _makeId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final suffix = String.fromCharCodes([
    for (var i = 0; i < 6; i++) chars.codeUnitAt(_rng.nextInt(chars.length)),
  ]);
  return 'bench-${DateTime.now().millisecondsSinceEpoch}-$suffix';
}

class BenchmarkRecorderImpl {
  List<PerfSample> _samples = [];
  List<BenchmarkMarker> _markers = [];
  BenchmarkMetadata? _metadata;
  List<PerfDiagnostic>? _diagnostics;
  int _startedAt = 0;
  void Function()? _detach;
  Timer? _autoStop;

  final Set<RecordingSubscriber> _subscribers = {};
  final Set<BenchmarkSavedSubscriber> _savedSubscribers = {};

  bool isRecording() => _detach != null;

  /// Wall-clock ms when the current run started, or 0 when idle.
  int getStartedAt() => _startedAt;

  int getSampleCount() => _samples.length;

  int getMarkerCount() => _markers.length;

  /// Start a manual recording. The caller owns `stop()` + persistence, or uses
  /// [startQuick] for a fire-and-forget timed run that auto-saves.
  void start(BenchmarkMetadata metadata) {
    if (isRecording()) return;
    _samples = [];
    _markers = [];
    _metadata = metadata;
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    _diagnostics = buildPerfDiagnostics();
    _detach = PerfMonitorController.instance.tapSamples((sample) {
      // Drop anything that predates this recording (RN parity — its stall
      // backfill could otherwise inject pre-start zeros).
      if (sample.timestamp >= _startedAt) _samples.add(sample);
    });
    _notifyRecording();
  }

  /// Drop a marker at the current moment. No-op when not recording.
  void mark([String? label]) {
    if (!isRecording()) return;
    _markers.add(BenchmarkMarker(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      label: label,
    ));
  }

  /// Start a recording that auto-stops + saves after [durationMs]. Returns a
  /// cancel closure.
  void Function() startQuick(
    BenchmarkMetadata metadata, [
    int durationMs = 10000,
  ]) {
    if (isRecording()) return () {};
    start(metadata);
    _autoStop = Timer(Duration(milliseconds: durationMs), () {
      _autoStop = null;
      unawaited(stopAndSave());
    });
    return () {
      _autoStop?.cancel();
      _autoStop = null;
      cancel();
    };
  }

  /// Stop, build a report, persist it. Returns the saved report, or null when
  /// there was nothing to save.
  Future<BenchmarkReport?> stopAndSave() async {
    final report = stop();
    if (report == null || report.samples.isEmpty) return null;
    await BenchmarkStorage.save(report);
    _notifySaved(report);
    return report;
  }

  /// Persist a report the caller built or renamed (RN `saveReport`) and notify
  /// `subscribeSaved`.
  Future<void> saveReport(BenchmarkReport report) async {
    await BenchmarkStorage.save(report);
    _notifySaved(report);
  }

  /// Stop WITHOUT saving; returns the in-memory report so the caller can name
  /// it first (the inline stop→name→save flow).
  BenchmarkReport? stop() {
    _autoStop?.cancel();
    _autoStop = null;
    final metadata = _metadata;
    if (!isRecording() || metadata == null) return null;
    _detach?.call();
    _detach = null;

    final samples = _samples;
    final markers = _markers;
    final diagnostics = _diagnostics;
    final startedAt = _startedAt;
    _samples = [];
    _markers = [];
    _metadata = null;
    _diagnostics = null;
    _startedAt = 0;
    _notifyRecording();

    return BenchmarkReport(
      id: _makeId(),
      createdAt: startedAt,
      metadata: metadata,
      samples: samples,
      markers: markers,
      stats: aggregateSamples(samples),
      diagnostics: diagnostics,
    );
  }

  void cancel() {
    _autoStop?.cancel();
    _autoStop = null;
    if (!isRecording()) return;
    _detach?.call();
    _detach = null;
    _samples = [];
    _markers = [];
    _metadata = null;
    _diagnostics = null;
    _startedAt = 0;
    _notifyRecording();
  }

  void Function() subscribe(RecordingSubscriber fn) {
    _subscribers.add(fn);
    fn(isRecording());
    return () => _subscribers.remove(fn);
  }

  /// Fires every time a run is saved (manual stop+save or quick auto-save).
  void Function() subscribeSaved(BenchmarkSavedSubscriber fn) {
    _savedSubscribers.add(fn);
    return () => _savedSubscribers.remove(fn);
  }

  void _notifyRecording() {
    final recording = isRecording();
    for (final fn in [..._subscribers]) {
      try {
        fn(recording);
      } catch (e) {
        if (kDebugMode) debugPrint('[perf-monitor] recording subscriber: $e');
      }
    }
  }

  void _notifySaved(BenchmarkReport report) {
    for (final fn in [..._savedSubscribers]) {
      try {
        fn(report);
      } catch (e) {
        if (kDebugMode) debugPrint('[perf-monitor] saved subscriber: $e');
      }
    }
  }
}

/// Capability snapshot embedded in every report (RN `buildDiagnostics`,
/// slimmed to the rows that mean something in Flutter — see the spike's
/// parity table).
List<PerfDiagnostic> buildPerfDiagnostics() {
  final controller = PerfMonitorController.instance;
  final caps = controller.getCapabilities();
  final snapshot = controller.getSnapshot();
  return [
    PerfDiagnostic(
      id: 'sampler',
      severity: 'ok',
      label: 'Sampler',
      detail:
          'FrameTiming + ProcessInfo (mode ${snapshot.mode.wire}, ${snapshot.deviceMaxRefreshRate.round()} Hz)',
    ),
    PerfDiagnostic(
      id: 'cpu',
      severity: caps.cpu ? 'ok' : 'skip',
      label: 'Process CPU',
      detail: caps.cpu
          ? '/proc/self/stat delta sampling'
          : 'unavailable on this platform — CPU reports 0',
      hint: caps.cpu
          ? null
          : 'iOS has no pure-Dart CPU counter; compare FPS/memory instead.',
    ),
    const PerfDiagnostic(
      id: 'memory',
      severity: 'ok',
      label: 'Memory',
      detail: 'ProcessInfo.currentRss (real RSS)',
      hint: 'Debug builds inflate RSS — profile mode is the honest number.',
    ),
  ];
}

/// Singleton (RN `BenchmarkRecorder`).
final BenchmarkRecorderImpl benchmarkRecorder = BenchmarkRecorderImpl();

/// Top-level convenience for dropping a marker on the active recording
/// (RN `mark()` in utils/mark.ts).
void mark([String? label]) => benchmarkRecorder.mark(label);
