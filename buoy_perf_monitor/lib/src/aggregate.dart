/// Ports packages/perf-monitor/src/perf-monitor/utils/aggregate.ts — 1:1.
///
/// Pure Dart (no Flutter import) so it is unit-tested against hard-coded RN
/// outputs. This is the load-bearing schema math the B2 report/index writers
/// and every desktop/MCP ranking consumer depend on: p95 index = ceil(n*0.95)-1
/// clamped; jsJankThreshold = min(50, round(rate*0.66)); uiJankThreshold =
/// round(rate*0.66); deviceMaxRefreshRate = dominant (histogram mode).
library;

import 'dart:math' as math;

import 'perf_types.dart';

/// RN `PERF_THRESHOLDS.fpsWarnPct`.
const double _fpsWarnPct = PerfThresholds.fpsWarnPct;

AggregateChannel _aggregateChannel(List<double> values) {
  if (values.isEmpty) return AggregateChannel.empty;
  final sorted = [...values]..sort();
  final sum = sorted.fold<double>(0, (acc, v) => acc + v);
  // ceil so p95 of small sample sizes still picks the worst-case bucket.
  final p95Index = math.min(
    sorted.length - 1,
    (sorted.length * 0.95).ceil() - 1,
  );
  return AggregateChannel(
    min: sorted.first,
    max: sorted.last,
    avg: sum / sorted.length,
    p95: sorted[math.max(0, p95Index)],
  );
}

/// Most common refresh-rate value across the run (RN `dominantRefreshRate`).
double _dominantRefreshRate(List<PerfSample> samples) {
  if (samples.isEmpty) return 60;
  final counts = <int, int>{};
  for (final s in samples) {
    final r =
        (s.deviceMaxRefreshRate == 0 ? 60 : s.deviceMaxRefreshRate).round();
    counts[r] = (counts[r] ?? 0) + 1;
  }
  var best = 60;
  var bestCount = 0;
  counts.forEach((rate, count) {
    if (count > bestCount) {
      best = rate;
      bestCount = count;
    }
  });
  return best.toDouble();
}

/// Ports `aggregateSamples`.
PerfStatsAggregate aggregateSamples(List<PerfSample> samples) {
  if (samples.isEmpty) {
    return const PerfStatsAggregate(
      sampleCount: 0,
      durationMs: 0,
      jsFps: AggregateChannel.empty,
      uiFps: AggregateChannel.empty,
      cpuUsage: AggregateChannel.empty,
      memoryUsage: AggregateChannel.empty,
      jsJankFrames: 0,
      uiJankFrames: 0,
      deviceMaxRefreshRate: 60,
    );
  }

  final jsFpsValues = [for (final s in samples) s.jsFps];
  final uiFpsValues = [for (final s in samples) s.uiFps];
  final cpuValues = [for (final s in samples) s.cpuUsage];
  final memValues = [for (final s in samples) s.memoryUsage];

  final refreshRate = _dominantRefreshRate(samples);
  // JS-thread jank historically sat at 50fps regardless of refresh rate;
  // preserve that floor so 60Hz devices don't flip amber too aggressively.
  final jsJankThreshold =
      math.min(50, (refreshRate * _fpsWarnPct).round());
  final uiJankThreshold = (refreshRate * _fpsWarnPct).round();

  return PerfStatsAggregate(
    sampleCount: samples.length,
    durationMs: samples.last.timestamp - samples.first.timestamp,
    jsFps: _aggregateChannel(jsFpsValues),
    uiFps: _aggregateChannel(uiFpsValues),
    cpuUsage: _aggregateChannel(cpuValues),
    memoryUsage: _aggregateChannel(memValues),
    jsJankFrames: jsFpsValues.where((fps) => fps < jsJankThreshold).length,
    uiJankFrames: uiFpsValues.where((fps) => fps < uiJankThreshold).length,
    deviceMaxRefreshRate: refreshRate,
  );
}
