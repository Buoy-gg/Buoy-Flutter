/// The recording-aware wrapper shared by the floating chip
/// ([PerfHudOverlay]) and the modal's inline strip
/// (packages/perf-monitor/.../PerfHudInline.tsx). Both RN surfaces attach to
/// the SAME singletons ([PerfMonitorController] / [benchmarkRecorder]), so
/// live data and recording stay in lock-step regardless of which one drove
/// the action — this widget is that shared wiring.
///
/// Owns: the controller/recorder subscriptions, the 1 Hz elapsed ticker
/// (RN `useElapsed`), the current-route label, and the stop→name→save prompt
/// (rendered by the owner via [pendingSavePrompt] so it can place it in its
/// own Stack — there's no Navigator above the dev-tools layer).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../benchmark_recorder.dart';
import '../hud_preferences.dart';
import '../perf_monitor_controller.dart';
import '../perf_route_bridge.dart';
import '../perf_settings.dart';
import '../perf_types.dart';
import 'perf_dialogs.dart';
import 'perf_hud_body.dart';

/// The chip/inline box each mode needs, padding included — the single sizing
/// contract shared by the floating overlay and the modal's inline HUD (RN
/// `dimsFor`). [padV] is the surface's own vertical padding.
double hudHeightFor(HudMode mode, {double padV = 8}) {
  switch (mode) {
    // STRIP_ROUTE_ROW_HEIGHT (12) + STRIP_CELLS_HEIGHT (64), padding included.
    case HudMode.strip:
      return 76;
    // Header line only — no route row, no sparklines.
    case HudMode.compact:
      return 36;
    case HudMode.card:
      return kCardBodyHeight + padV * 2;
  }
}

/// No frames within this many ms → the HUD dashes FPS (idle).
const int perfIdleThresholdMs = 700;

/// MM:SS elapsed since [startedAt] (RN `useElapsed`). Empty when idle.
String formatElapsed(int startedAt) {
  if (startedAt <= 0) return '';
  final seconds = ((DateTime.now().millisecondsSinceEpoch - startedAt) / 1000)
      .floor();
  if (seconds < 0) return '00:00';
  final mm = (seconds ~/ 60).toString().padLeft(2, '0');
  final ss = (seconds % 60).toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// Auto-name a manual run "route · HH:MM" (RN `autoNameForRun`).
BenchmarkMetadata autoNameForRun() {
  final route = getCurrentRoute();
  final now = DateTime.now();
  final time =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  return BenchmarkMetadata(
    name: route.isNotEmpty ? '$route · $time' : 'Run · $time',
    route: route.isNotEmpty ? route : null,
    source: 'manual',
  );
}

/// Start a manual recording (RN `startManualRecording`). No-op when one is
/// already in flight.
void startManualRecording() {
  if (benchmarkRecorder.isRecording()) return;
  benchmarkRecorder.start(autoNameForRun());
}

/// Non-floating copy of the HUD, mounted at the top of the modal's runs list
/// (RN `PerfHudInline`). The floating chip suppresses itself while the modal is
/// open, so this is the only HUD surface then — which is why it reads and
/// writes the SAME persisted `hud-prefs.mode` and cycles on tap: the layout you
/// picked on the bubble is the layout you get in the modal, and vice versa.
class PerfHudInline extends StatefulWidget {
  const PerfHudInline({super.key, this.onPendingPromptChanged});

  /// Fires with the save prompt widget (or null); the modal renders it in its
  /// own Stack (no Navigator exists above the dev-tools layer).
  final void Function(Widget? prompt)? onPendingPromptChanged;

  @override
  State<PerfHudInline> createState() => _PerfHudInlineState();
}

class _PerfHudInlineState extends State<PerfHudInline> {
  static const double _padH = 10;
  static const double _padV = 8;

  HudMode _mode = HudPreferences.defaults.mode;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    loadHudPreferences().then((p) {
      if (mounted) setState(() => _mode = p.mode);
    });
  }

  void _cycleMode() {
    final next = nextHudMode(_mode);
    setState(() => _mode = next);
    // ignore: discarded_futures
    loadHudPreferences().then((p) {
      // ignore: discarded_futures
      saveHudPreferences(p.copyWith(mode: next));
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _cycleMode,
      child: PerfHudSurface(
        mode: _mode,
        onPendingPromptChanged: widget.onPendingPromptChanged,
        builder: (context, body) => Container(
          height: hudHeightFor(_mode, padV: _padV),
          padding: const EdgeInsets.symmetric(
            horizontal: _padH,
            vertical: _padV,
          ),
          decoration: BoxDecoration(
            color: BuoyColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: BuoyColors.textMuted.withValues(alpha: 0x66 / 255),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: body,
        ),
      ),
    );
  }
}

/// Renders [PerfHudBody] with live recording state wired in. The owner passes
/// a [builder] so it can wrap the body in its own chrome (floating chip card
/// vs the modal's inline surface).
class PerfHudSurface extends StatefulWidget {
  const PerfHudSurface({
    super.key,
    required this.mode,
    required this.builder,
    this.onPendingPromptChanged,
  });

  final HudMode mode;

  /// Wraps the built HUD body in the surface's own chrome.
  final Widget Function(BuildContext context, Widget body) builder;

  /// Fires with the save prompt widget (or null) whenever a recording is
  /// stopped with samples — the owner renders it in its own Stack.
  final void Function(Widget? prompt)? onPendingPromptChanged;

  @override
  State<PerfHudSurface> createState() => _PerfHudSurfaceState();
}

class _PerfHudSurfaceState extends State<PerfHudSurface> {
  final _controller = PerfMonitorController.instance;

  PerfSnapshot _snapshot = PerfMonitorController.instance.getSnapshot();
  PerfSettings _settings = PerfSettingsStore.instance.current;
  bool _recording = benchmarkRecorder.isRecording();
  int _startedAt = benchmarkRecorder.getStartedAt();
  String? _routeLabel;

  void Function()? _unsubSnapshot;
  void Function()? _unsubSettings;
  void Function()? _unsubRecording;
  void Function()? _unsubRoute;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _unsubSnapshot = _controller.subscribe((s) {
      if (mounted) setState(() => _snapshot = s);
    });
    _unsubSettings = PerfSettingsStore.instance.subscribe((s) {
      if (mounted) setState(() => _settings = s);
    });
    _unsubRecording = benchmarkRecorder.subscribe((isRecording) {
      if (!mounted) return;
      setState(() {
        _recording = isRecording;
        _startedAt = benchmarkRecorder.getStartedAt();
      });
      _syncElapsedTimer();
    });
    final route = getCurrentRoute();
    _routeLabel = route.isEmpty ? null : route;
    _unsubRoute = subscribeRouteChanges((pathname) {
      if (mounted) setState(() => _routeLabel = pathname);
    });
    // ignore: discarded_futures
    PerfSettingsStore.instance.load();
    _syncElapsedTimer();
  }

  @override
  void dispose() {
    _unsubSnapshot?.call();
    _unsubSettings?.call();
    _unsubRecording?.call();
    _unsubRoute?.call();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  /// The elapsed label only needs 1 Hz, and only while recording — no timer
  /// runs otherwise.
  void _syncElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    if (!_recording) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _handleRecord() {
    if (benchmarkRecorder.isRecording()) return;
    startManualRecording();
  }

  void _handleStop() {
    if (!benchmarkRecorder.isRecording()) return;
    final report = benchmarkRecorder.stop();
    // Too short to be useful — drop it silently (RN parity).
    if (report == null || report.samples.isEmpty) return;
    widget.onPendingPromptChanged?.call(
      SaveBenchmarkPrompt(
        defaultName: report.metadata.name,
        sampleCount: report.samples.length,
        onSave: (name) {
          widget.onPendingPromptChanged?.call(null);
          final trimmed = name.trim();
          final finalName = trimmed.isNotEmpty ? trimmed : report.metadata.name;
          // ignore: discarded_futures
          benchmarkRecorder.saveReport(
            report.copyWith(
              metadata: report.metadata.copyWith(name: finalName),
            ),
          );
        },
        onCancel: () => widget.onPendingPromptChanged?.call(null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _controller.lastFrameAtMs;
    final idle = last == 0 || (now - last) > perfIdleThresholdMs;

    return widget.builder(
      context,
      PerfHudBody(
        mode: widget.mode,
        snapshot: _snapshot,
        settings: _settings,
        idle: idle,
        recording: _recording,
        recordingElapsed: formatElapsed(_startedAt),
        onRecordTap: _handleRecord,
        onStopTap: _handleStop,
        routeLabel: _routeLabel,
      ),
    );
  }
}
