/// Ports packages/perf-monitor/src/perf-monitor/utils/windowedStats.ts.
///
/// Pure helpers (no Flutter import) for summarizing the last few seconds of
/// [PerfSample] history — the HUD reads instantaneous samples but shows the
/// worst few frames over `windowMs`. `computeWindowStats` drives the min /
/// volatility / slope hints; `computeJankCounts` drives the "JS n / UI n" row.
///
/// Flutter deviation: idle samples (`active == false`) are skipped by both
/// helpers so a still, non-rendering app never fabricates jank or a
/// misleading "min 0" — the honest analog of RN's always-ticking native FPS.
library;

import 'dart:math' as math;

import 'perf_types.dart';

/// Metric selectors.
enum MetricKey { jsFps, uiFps, cpuUsage, memoryUsage }

double _pick(PerfSample s, MetricKey m) {
  switch (m) {
    case MetricKey.jsFps:
      return s.jsFps;
    case MetricKey.uiFps:
      return s.uiFps;
    case MetricKey.cpuUsage:
      return s.cpuUsage;
    case MetricKey.memoryUsage:
      return s.memoryUsage;
  }
}

/// Coarse volatility bucket from coefficient-of-variation (RN `Volatility`).
enum Volatility { stable, varying, spiky }

class WindowStats {
  const WindowStats({
    required this.samplesUsed,
    required this.current,
    required this.min,
    required this.max,
    required this.mean,
    required this.stddev,
    required this.p95,
    required this.slope,
    required this.volatility,
  });

  final int samplesUsed;
  final double current;
  final double min;
  final double max;
  final double mean;
  final double stddev;
  final double p95;

  /// Linear-regression slope in units-per-sample (memory direction arrow).
  final double slope;
  final Volatility volatility;

  static const WindowStats empty = WindowStats(
    samplesUsed: 0,
    current: 0,
    min: 0,
    max: 0,
    mean: 0,
    stddev: 0,
    p95: 0,
    slope: 0,
    volatility: Volatility.stable,
  );
}

Volatility _classifyVolatility(double mean, double stddev) {
  if (mean <= 0.0001) return Volatility.stable;
  final ratio = stddev / mean;
  if (ratio < 0.05) return Volatility.stable;
  if (ratio < 0.2) return Volatility.varying;
  return Volatility.spiky;
}

/// Selects the trailing `[start, end)` window measured back from the newest
/// sample. `activeOnly` drops idle (non-rendering) samples for FPS metrics.
({int start, int end}) _sliceWindow(
  List<PerfSample> samples,
  int windowMs,
  int? maxSamples,
) {
  final end = samples.length;
  if (end == 0) return (start: 0, end: 0);
  final newestTs = samples[end - 1].timestamp;
  final cutoff = newestTs - windowMs;
  var start = end;
  while (start > 0 && samples[start - 1].timestamp >= cutoff) {
    start--;
  }
  if (maxSamples != null && end - start > maxSamples) {
    start = end - maxSamples;
  }
  return (start: start, end: end);
}

/// Summary stats for one metric over the trailing window (RN
/// `computeWindowStats`). `activeOnly` (default true) skips idle samples so FPS
/// min/volatility reflect real rendering activity only.
WindowStats computeWindowStats(
  List<PerfSample> samples,
  MetricKey metric, {
  int windowMs = 5000,
  int? maxSamples,
  bool activeOnly = true,
}) {
  final w = math.max(0, windowMs);
  final range = _sliceWindow(samples, w, maxSamples);

  final values = <double>[];
  for (var i = range.start; i < range.end; i++) {
    final s = samples[i];
    if (activeOnly && !s.active) continue;
    values.add(_pick(s, metric));
  }
  final n = values.length;
  if (n == 0) return WindowStats.empty;

  var sum = 0.0;
  var min = double.infinity;
  var max = double.negativeInfinity;
  for (final v in values) {
    sum += v;
    if (v < min) min = v;
    if (v > max) max = v;
  }
  final mean = sum / n;

  var sqSum = 0.0;
  for (final v in values) {
    final d = v - mean;
    sqSum += d * d;
  }
  final stddev = math.sqrt(sqSum / n);

  final sorted = [...values]..sort();
  final p95Idx = math.min(n - 1, math.max(0, (n * 0.95).ceil() - 1));
  final p95 = sorted[p95Idx];

  var slope = 0.0;
  if (n >= 2) {
    final xMean = (n - 1) / 2;
    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = i - xMean;
      num += dx * (values[i] - mean);
      den += dx * dx;
    }
    slope = den > 0 ? num / den : 0;
  }

  return WindowStats(
    samplesUsed: n,
    current: values[n - 1],
    min: min,
    max: max,
    mean: mean,
    stddev: stddev,
    p95: p95,
    slope: slope,
    volatility: _classifyVolatility(mean, stddev),
  );
}

class JankCounts {
  const JankCounts({
    required this.jsJank,
    required this.uiJank,
    required this.samplesUsed,
  });

  final int jsJank;
  final int uiJank;
  final int samplesUsed;

  static const JankCounts empty =
      JankCounts(jsJank: 0, uiJank: 0, samplesUsed: 0);
}

/// Per-thread jank over the trailing window (RN `computeJankCounts`). Idle
/// samples are skipped (`activeOnly`) so a still app reads 0 jank.
JankCounts computeJankCounts(
  List<PerfSample> samples, {
  int windowMs = 5000,
  double jsThreshold = 50,
  double uiRefreshRatio = 0.85,
  int? maxSamples,
  bool activeOnly = true,
}) {
  final w = math.max(0, windowMs);
  final range = _sliceWindow(samples, w, maxSamples);
  var jsJank = 0;
  var uiJank = 0;
  var used = 0;
  for (var i = range.start; i < range.end; i++) {
    final s = samples[i];
    if (activeOnly && !s.active) continue;
    used++;
    if (s.jsFps < jsThreshold) jsJank++;
    final uiFloor =
        ((s.deviceMaxRefreshRate == 0 ? 60 : s.deviceMaxRefreshRate) *
                uiRefreshRatio)
            .round();
    if (s.uiFps < uiFloor) uiJank++;
  }
  return JankCounts(jsJank: jsJank, uiJank: uiJank, samplesUsed: used);
}
