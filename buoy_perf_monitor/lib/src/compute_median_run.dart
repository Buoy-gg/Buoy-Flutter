/// Ports packages/perf-monitor/src/perf-monitor/utils/computeMedianRun.ts.
///
/// Median-run selection + spread math for multi-run batch cases. Pure — no
/// Flutter imports, no clock — so it is parity-testable against hard-coded RN
/// outputs. Median-run pick mirrors Chrome Lighthouse's representative-run
/// selection.
library;

import 'dart:math' as math;

import 'perf_types.dart';

/// Filter out runs that can't take part in median computation: failed
/// (batchFailureReason set), zero-sample, or any non-finite headline metric.
/// Order is preserved.
List<BenchmarkReport> filterToValidRuns(List<BenchmarkReport> runs) {
  return [
    for (final r in runs)
      if (r.metadata.batchFailureReason == null &&
          r.samples.isNotEmpty &&
          r.stats.jsFps.avg.isFinite &&
          r.stats.uiFps.avg.isFinite &&
          r.stats.cpuUsage.avg.isFinite &&
          r.stats.memoryUsage.avg.isFinite)
        r,
  ];
}

/// Pick the run closest to the median (avg JS FPS, avg UI FPS) point across
/// N runs. Ties break toward the run with fewest JS jank frames. Returns the
/// actual run, never a synthesized one, so its sample series stays inspectable.
///
/// Throws when [runs] is empty — call [filterToValidRuns] first.
BenchmarkReport computeMedianRun(List<BenchmarkReport> runs) {
  if (runs.isEmpty) {
    throw ArgumentError('computeMedianRun: runs must be non-empty');
  }
  if (runs.length == 1) return runs.first;

  final medJs = _median([for (final r in runs) r.stats.jsFps.avg]);
  final medUi = _median([for (final r in runs) r.stats.uiFps.avg]);

  var bestIdx = 0;
  var bestDist = double.infinity;
  var bestJank = double.infinity;
  for (var i = 0; i < runs.length; i++) {
    final dj = runs[i].stats.jsFps.avg - medJs;
    final du = runs[i].stats.uiFps.avg - medUi;
    final dist = math.sqrt(dj * dj + du * du);
    final jank = runs[i].stats.jsJankFrames.toDouble();
    if (dist < bestDist || (dist == bestDist && jank < bestJank)) {
      bestDist = dist;
      bestJank = jank;
      bestIdx = i;
    }
  }
  return runs[bestIdx];
}

/// Mean + SAMPLE stddev (÷ N-1) across runs for each headline metric
/// (RN `computeRunSpread`).
RunSpread computeRunSpread(List<BenchmarkReport> runs) => RunSpread(
      jsFps: _meanStddev([for (final r in runs) r.stats.jsFps.avg]),
      uiFps: _meanStddev([for (final r in runs) r.stats.uiFps.avg]),
      cpuUsage: _meanStddev([for (final r in runs) r.stats.cpuUsage.avg]),
      memoryUsage: _meanStddev([for (final r in runs) r.stats.memoryUsage.max]),
      jsJankFrames:
          _meanStddev([for (final r in runs) r.stats.jsJankFrames.toDouble()]),
      uiJankFrames:
          _meanStddev([for (final r in runs) r.stats.uiJankFrames.toDouble()]),
    );

MeanStddev _meanStddev(List<double> values) {
  final finite = [
    for (final v in values)
      if (v.isFinite) v,
  ];
  if (finite.isEmpty) return MeanStddev.zero;
  final mean = finite.reduce((a, b) => a + b) / finite.length;
  if (finite.length < 2) return MeanStddev(mean: mean, stddev: 0);
  var sumSq = 0.0;
  for (final v in finite) {
    sumSq += (v - mean) * (v - mean);
  }
  return MeanStddev(mean: mean, stddev: math.sqrt(sumSq / (finite.length - 1)));
}

/// Standard median (linear interpolation between centers on even N).
double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isEven) return (sorted[mid - 1] + sorted[mid]) / 2;
  return sorted[mid];
}
