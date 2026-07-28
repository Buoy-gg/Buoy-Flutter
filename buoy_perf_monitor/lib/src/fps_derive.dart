/// Pure per-tick FPS derivation (extracted from [PerfMonitorController] so it
/// can be unit-tested against synthetic FrameTiming lists without a device).
///
/// Spike parity table:
///   uiFps = delivered frame rate = frames ÷ elapsedSec, capped at refresh;
///           idle (no frames) = last-held (never fabricates UI jank).
///   jsFps = avg over this-tick frames of min(refresh, 1000/buildMs);
///           idle = refresh (Dart thread free = healthy).
library;

import 'dart:math' as math;

/// Learn-time refresh-rate normalization: round and clamp to a 60 Hz floor
/// (RN `Math.max(60, Math.round(getDeviceMaxRefreshRate()))`). A 60 Hz sim
/// reports 60; a 120 Hz device reports 120 → budget 8.33 ms.
double clampRefreshRate(double rate) {
  if (!rate.isFinite || rate <= 0) return 60;
  return math.max(60, rate.round()).toDouble();
}

class FpsDerivation {
  const FpsDerivation({
    required this.jsFps,
    required this.uiFps,
    required this.active,
  });

  final double jsFps;
  final double uiFps;

  /// Whether frames were produced this tick (idle ticks are `active == false`).
  final bool active;
}

/// Derives (jsFps, uiFps, active) from the frames collected since the last
/// tick. [frameBuildMicros] = per-frame `buildDuration` in microseconds;
/// [elapsedMs] = wall time since the previous tick; [refresh] = device max
/// refresh; [lastUiFps] = the previous delivered rate (held during idle).
FpsDerivation deriveFps({
  required List<int> frameBuildMicros,
  required int elapsedMs,
  required double refresh,
  required double lastUiFps,
}) {
  if (frameBuildMicros.isEmpty) {
    return FpsDerivation(jsFps: refresh, uiFps: lastUiFps, active: false);
  }
  final elapsedSec = elapsedMs / 1000.0;
  var uiFps = elapsedSec > 0 ? frameBuildMicros.length / elapsedSec : refresh;
  if (uiFps > refresh) uiFps = refresh;
  if (uiFps < 0) uiFps = 0;

  var sum = 0.0;
  for (final micros in frameBuildMicros) {
    final buildMs = micros / 1000.0;
    sum += buildMs <= 0 ? refresh : math.min(refresh, 1000.0 / buildMs);
  }
  final jsFps = sum / frameBuildMicros.length;

  return FpsDerivation(jsFps: jsFps, uiFps: uiFps, active: true);
}
