/// Chart primitives for the HUD's `card` mode — the sleek per-metric cards.
///
/// These read the SAME bucketed geometry as the column sparkline
/// ([buildSparklineColumns]), so a card and a strip cell drawn at the same
/// instant describe the same 30 seconds of history. Only the ink differs:
///
///  - [PerfLineChart] — a smooth glowing line with a lit end dot. Used for the
///    continuous channels (JS / UI / CPU), where the shape of the trend is the
///    thing you read.
///  - [PerfBarChart] — thin rounded bars. Used for memory, whose trace is
///    step-like (allocations land as jumps, GC as cliffs); a smoothed line
///    would invent slopes that never happened.
///  - [PerfRecDots] — the Rec card's beat row. Not data: a recording indicator
///    that reads as "time is passing", brightening left→right and marching one
///    dot per second while a capture is in flight.
///
/// Null buckets (seconds with no sample) are gaps, not zeros — the line breaks
/// across them rather than diving to the floor and back.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Buckets per card chart. Well under the sparkline's 30, for two reasons: the
/// RN port draws its line as several rotated `<View>`s per segment (so the
/// count is a real cost there), and at 24 points across a ~65pt column the
/// segments were shorter than the stroke was thick — the line rendered as a
/// string of beads instead of a curve. 14 points still reads as a smooth wave.
/// Both builds use this so a card shows the same window on either platform.
const int kCardBucketCount = 14;

/// Vertical inset so the stroke, its end dot, and the bloom around them have
/// room when a value pins to 0 or max.
const double _chartInsetY = 6;

/// Smooth glowing line + end dot.
class PerfLineChart extends StatelessWidget {
  const PerfLineChart({super.key, required this.ratios, required this.color});

  /// Per-bucket 0..1 fill ratios; null = no sample that second.
  final List<double?> ratios;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _LinePainter(ratios: ratios, color: color),
    child: const SizedBox.expand(),
  );
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.ratios, required this.color});

  final List<double?> ratios;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || ratios.length < 2) return;

    final usableH = math.max(1.0, size.height - _chartInsetY * 2);
    final stepX = size.width / (ratios.length - 1);
    Offset pointAt(int i, double ratio) =>
        Offset(i * stepX, _chartInsetY + (1 - ratio.clamp(0.0, 1.0)) * usableH);

    // Contiguous runs of sampled buckets. A gap ends the current run so the
    // line breaks instead of teleporting across missing seconds.
    final runs = <List<Offset>>[];
    var run = <Offset>[];
    for (var i = 0; i < ratios.length; i++) {
      final r = ratios[i];
      if (r == null) {
        if (run.length > 1) runs.add(run);
        run = <Offset>[];
        continue;
      }
      run.add(pointAt(i, r));
    }
    if (run.length > 1) runs.add(run);
    if (runs.isEmpty) {
      // A single sample has no line to draw — mark it with the end dot alone
      // so a freshly-opened HUD isn't an empty box.
      for (var i = ratios.length - 1; i >= 0; i--) {
        final r = ratios[i];
        if (r != null) {
          _drawEndDot(canvas, pointAt(i, r));
          return;
        }
      }
      return;
    }

    for (final points in runs) {
      final path = _smoothPath(points);

      // The region under the curve, used ONLY as a clip — nothing fills it.
      // An earlier pass painted a gradient wash down to the floor; because
      // these charts are ~32pt tall and traces usually sit near the top, that
      // covered most of the frame and the chart read as a solid block with the
      // wire lost inside it.
      final under = Path.from(path)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();

      // Bloom: two blurred strokes, wide-and-faint under tight-and-bright.
      // One pass reads as a fuzzy line; stacking them gives the halo a falloff
      // instead of an edge. Kept tight — at 32pt tall, a 12pt halo IS the
      // chart.
      //
      // Clipped to [under]. A blur is symmetric, and a halo straddling the
      // wire reads as a fuzzy band; letting it spill only downward reads as
      // light coming off the wire. The crisp stroke is drawn after the restore
      // so it covers the seam the clip leaves at the line.
      canvas.save();
      canvas.clipPath(under);
      _stroke(canvas, path, 8, 0.22, blur: 4);
      _stroke(canvas, path, 4, 0.4, blur: 2);
      canvas.restore();
      _stroke(canvas, path, 1.8, 1.0);
    }

    _drawEndDot(canvas, runs.last.last);
  }

  void _stroke(
    Canvas canvas,
    Path path,
    double width,
    double alpha, {
    double? blur,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: alpha);
    if (blur != null) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    }
    canvas.drawPath(path, paint);
  }

  /// Cubic through the points with horizontal control tangents at each
  /// midpoint — the same easing a spline would give for a monotone series,
  /// without the overshoot a Catmull-Rom introduces on spiky data.
  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final midX = (a.dx + b.dx) / 2;
      path.cubicTo(midX, a.dy, midX, b.dy, b.dx, b.dy);
    }
    return path;
  }

  /// The "you are here" ball. Same two-pass bloom as the line so it reads as
  /// the brightest point of one continuous light source.
  void _drawEndDot(Canvas canvas, Offset at) {
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      at,
      4.5,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(at, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || !_sameRatios(old.ratios, ratios);
}

/// Thin rounded bars — memory's step-like trace.
class PerfBarChart extends StatelessWidget {
  const PerfBarChart({super.key, required this.ratios, required this.color});

  final List<double?> ratios;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BarPainter(ratios: ratios, color: color),
    child: const SizedBox.expand(),
  );
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.ratios, required this.color});

  final List<double?> ratios;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || ratios.isEmpty) return;

    final slot = size.width / ratios.length;
    // Bars keep ~55% of their slot so the gaps stay legible at 30 buckets in a
    // ~90pt card; below 1.5pt they'd alias into a solid block.
    final barW = math.max(1.5, slot * 0.55);
    final usableH = math.max(1.0, size.height - _chartInsetY);
    final paint = Paint()..color = color;
    // Same bloom idea as the line, per bar — otherwise the memory column looks
    // flat next to three glowing neighbours.
    final glow = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (var i = 0; i < ratios.length; i++) {
      final r = ratios[i];
      if (r == null) continue;
      // Floor at 2pt: a bucket that sampled at the very bottom of the window
      // still happened, and an invisible bar reads as a gap.
      final h = math.max(2.0, r.clamp(0.0, 1.0) * usableH);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * slot + (slot - barW) / 2, size.height - h, barW, h),
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(rect, glow);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.color != color || !_sameRatios(old.ratios, ratios);
}

/// The Rec card's beat row: dots brightening left→right, marching one step per
/// second while recording. Purely an indicator — no metric is encoded here.
class PerfRecDots extends StatelessWidget {
  const PerfRecDots({
    super.key,
    required this.color,
    required this.recording,
    required this.elapsedSeconds,
    this.count = 10,
  });

  final Color color;
  final bool recording;

  /// Drives the marching highlight. Ignored when [recording] is false.
  final int elapsedSeconds;
  final int count;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RecDotsPainter(
      color: color,
      recording: recording,
      step: recording ? elapsedSeconds % count : -1,
      count: count,
    ),
    child: const SizedBox.expand(),
  );
}

class _RecDotsPainter extends CustomPainter {
  _RecDotsPainter({
    required this.color,
    required this.recording,
    required this.step,
    required this.count,
  });

  final Color color;
  final bool recording;

  /// Index of the currently-lit dot, or -1 when idle.
  final int step;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || count <= 0) return;
    final slot = size.width / count;
    final cy = size.height / 2;
    for (var i = 0; i < count; i++) {
      final ramp = count == 1 ? 1.0 : i / (count - 1);
      // Idle: a dim ramp, so the card still has a silhouette. Recording: the
      // ramp brightens and the marching dot blooms.
      final lit = recording && i == step;
      final alpha = recording ? 0.35 + ramp * 0.5 : 0.12 + ramp * 0.18;
      final radius = 1.5 + ramp * 1.0 + (lit ? 1.5 : 0.0);
      final center = Offset(i * slot + slot / 2, cy);
      if (lit) {
        canvas.drawCircle(
          center,
          radius + 3,
          Paint()
            ..color = color.withValues(alpha: 0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: lit ? 1.0 : alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_RecDotsPainter old) =>
      old.color != color ||
      old.recording != recording ||
      old.step != step ||
      old.count != count;
}

bool _sameRatios(List<double?> a, List<double?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
