/// Ports packages/perf-monitor/src/perf-monitor/components/MetricSparkline.tsx
/// — the iOS-RCTFPSGraph-style column chart, drawn with a cheap `CustomPaint`
/// instead of RN's row of `<View>`s (identical output, one layer).
///
/// The algorithm is RN's, verbatim:
///  - **Wall-clock bucketing.** Columns are anchored to `stepMs` buckets
///    (1000 ms = one column per second, 30 columns). Each column shows the LAST
///    sample that landed in its second, so a column freezes once its second
///    elapses and the chart scrolls left. Buckets with no sample are
///    transparent — that's why a young history paints only a few columns on
///    the right instead of stretching to fill the frame.
///  - **Fixed scale** (0..max) for FPS/CPU — auto-fit would hide headroom, and
///    the question there is "how close am I to the spec". **Auto scale** for
///    memory, where there's no universal ceiling and the signal is the trend:
///    rescale to the observed window with a floor of 5% of the window's centre
///    (so a flat trace reads as a flat mid-chart band, not noise) and 10%
///    padding above/below otherwise.
///  - **Identity coloring**: every column is the metric's stable hue. Severity
///    is read from the NUMBER and the bar's distance from the target line, not
///    from the chart's color — calmer under long-running monitoring.
///  - A dashed target line (RN `TARGET_LINE`, rgba(255,255,255,0.25), 30
///    alternating segments) and an optional fainter solid baseline
///    (rgba(255,255,255,0.18)) projected through the same scale.
library;

import 'package:flutter/widgets.dart';

import '../perf_types.dart';

/// RN `MetricSparkline` defaults.
const int kSparklineBucketCount = 30;
const int kSparklineStepMs = 1000;

const Color _targetLineColor = Color(0x40FFFFFF); // rgba(255,255,255,0.25)
const Color _baselineColor = Color(0x2EFFFFFF); // rgba(255,255,255,0.18)

/// How sample values map to column heights (RN `scaleMode`).
enum SparklineScale {
  /// 0..max — FPS/CPU, where there's a hard ceiling.
  fixed,

  /// Rescaled to the observed window — memory, where the trend is the signal.
  auto,
}

/// The chart's computed geometry: per-bucket fill ratios (null = no sample
/// that bucket) plus the scale the ratios were computed against, so a baseline
/// in raw units can be projected through the same mapping.
class SparklineColumns {
  const SparklineColumns({
    required this.ratios,
    required this.effectiveMin,
    required this.effectiveMax,
  });

  final List<double?> ratios;
  final double effectiveMin;
  final double effectiveMax;

  /// Project a raw value onto the chart. Null when it falls outside the chart
  /// (a line pinned to the very top or bottom is visual noise, so RN skips it).
  double? ratioFor(double value) {
    if (!value.isFinite) return null;
    final denom = effectiveMax - effectiveMin;
    if (denom <= 0) return null;
    final r = (value - effectiveMin) / denom;
    return (r > 0 && r < 1) ? r : null;
  }
}

/// Pure port of RN `MetricSparkline`'s `useMemo` body — bucketing + scaling,
/// extracted so it can be parity-tested without a widget tree. [nowMs] is
/// injected for determinism.
SparklineColumns buildSparklineColumns({
  required List<PerfSample> history,
  required double Function(PerfSample) pick,
  required double max,
  required int nowMs,
  SparklineScale scaleMode = SparklineScale.fixed,
  int bucketCount = kSparklineBucketCount,
  int stepMs = kSparklineStepMs,
}) {
  final scale = max > 0 ? max : 1.0;

  // Anchor buckets to wall-clock steps. The in-progress bucket is excluded so
  // the rightmost column freezes once its second completes (iOS RCTFPSGraph).
  final startBucket = (nowMs ~/ stepMs) - bucketCount;
  final buckets = List<double?>.filled(bucketCount, null);
  for (final sample in history) {
    final idx = (sample.timestamp ~/ stepMs) - startBucket;
    if (idx < 0 || idx >= bucketCount) continue;
    // Forward iteration → the last sample within a bucket wins.
    buckets[idx] = pick(sample);
  }

  var effectiveMin = 0.0;
  var effectiveMax = scale;
  if (scaleMode == SparklineScale.auto) {
    var observedMin = double.infinity;
    var observedMax = double.negativeInfinity;
    var count = 0;
    for (final v in buckets) {
      if (v == null) continue;
      if (v < observedMin) observedMin = v;
      if (v > observedMax) observedMax = v;
      count++;
    }
    if (count > 0 && observedMin.isFinite && observedMax.isFinite) {
      final range = observedMax - observedMin;
      final center = (observedMin + observedMax) / 2;
      // Floor: keep the visual range from collapsing when the signal is flat —
      // a stable trace should read as a flat mid-chart band, not noise.
      final minRange = center * 0.05 > 1 ? center * 0.05 : 1.0;
      if (range < minRange) {
        effectiveMin = center - minRange / 2 < 0 ? 0 : center - minRange / 2;
        effectiveMax = center + minRange / 2;
      } else {
        // 10% headroom so peaks/dips don't kiss the edges.
        final padding = range * 0.1;
        effectiveMin = observedMin - padding < 0 ? 0 : observedMin - padding;
        effectiveMax = observedMax + padding;
      }
    }
  }

  final denom = effectiveMax - effectiveMin;
  return SparklineColumns(
    ratios: [
      for (final v in buckets)
        if (v == null)
          null
        else if (denom > 0)
          ((v - effectiveMin) / denom).clamp(0.0, 1.0)
        else
          0.5,
    ],
    effectiveMin: effectiveMin,
    effectiveMax: effectiveMax,
  );
}

class PerfSparkline extends StatelessWidget {
  const PerfSparkline({
    super.key,
    required this.history,
    required this.pick,
    required this.max,
    required this.color,
    this.scaleMode = SparklineScale.fixed,
    this.targetRatio,
    this.baselineValue,
    this.bucketCount = kSparklineBucketCount,
    this.stepMs = kSparklineStepMs,
    this.height,
  });

  /// Newest-last sample history (the controller keeps ~34s — enough to cover
  /// the 30 completed-second buckets at any wall-clock phase, so the leftmost
  /// column never drains mid-second).
  final List<PerfSample> history;

  /// Which channel to chart.
  final double Function(PerfSample sample) pick;

  /// Hard upper bound for `fixed` normalization (refresh rate / 100 / 1024).
  final double max;

  /// The metric's stable identity hue.
  final Color color;
  final SparklineScale scaleMode;

  /// 0..1 height of the dashed reference line (e.g. the FPS "good" cutoff).
  final double? targetRatio;

  /// Headroom line in raw metric units (e.g. the device refresh rate). Drawn
  /// only when it lands strictly inside the chart.
  final double? baselineValue;

  final int bucketCount;
  final int stepMs;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final columns = buildSparklineColumns(
      history: history,
      pick: pick,
      max: max,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      scaleMode: scaleMode,
      bucketCount: bucketCount,
      stepMs: stepMs,
    );
    final baseline = baselineValue;
    final painter = CustomPaint(
      painter: _SparklinePainter(
        columns: columns.ratios,
        color: color,
        targetRatio: targetRatio,
        baselineRatio: baseline == null ? null : columns.ratioFor(baseline),
      ),
      child: const SizedBox.expand(),
    );
    return height != null ? SizedBox(height: height, child: painter) : painter;
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.columns,
    required this.color,
    this.targetRatio,
    this.baselineRatio,
  });

  /// Per-bucket fill ratio (0..1); null = no sample that bucket.
  final List<double?> columns;
  final Color color;
  final double? targetRatio;
  final double? baselineRatio;

  /// RN draws the dashed line as 30 alternating segments across the width.
  static const int _dashSegments = 30;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (columns.isNotEmpty) {
      final barPaint = Paint()..color = color;
      final barW = size.width / columns.length;
      for (var i = 0; i < columns.length; i++) {
        final ratio = columns[i];
        if (ratio == null || ratio <= 0) continue;
        final h = size.height * ratio;
        canvas.drawRect(
          Rect.fromLTWH(i * barW, size.height - h, barW, h),
          barPaint,
        );
      }
    }

    _line(canvas, size, targetRatio, _targetLineColor, dashed: true);
    _line(canvas, size, baselineRatio, _baselineColor, dashed: false);
  }

  void _line(
    Canvas canvas,
    Size size,
    double? ratio,
    Color lineColor, {
    required bool dashed,
  }) {
    if (ratio == null || ratio <= 0 || ratio >= 1) return;
    final y = size.height * (1 - ratio);
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    final segW = size.width / _dashSegments;
    for (var i = 0; i < _dashSegments; i += 2) {
      canvas.drawLine(
        Offset(i * segW, y),
        Offset((i + 1) * segW, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color ||
      old.targetRatio != targetRatio ||
      old.baselineRatio != baselineRatio ||
      !_sameColumns(old.columns, columns);

  static bool _sameColumns(List<double?> a, List<double?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
