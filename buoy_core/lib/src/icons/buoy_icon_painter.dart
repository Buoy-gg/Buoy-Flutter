import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'buoy_icon_data.dart';

/// Renders a [BuoyIconData] — the Flutter renderer for the Buoy Icon Format.
///
/// The contract this implements is `shared/icons/SPEC.md`; that document wins
/// over anything here. Four rules are the ones that actually bite:
///
/// * **Inset strokes** — RN/CSS draw borders *inside* the box, Canvas centers
///   them on the path. Every stroked shape insets by `strokeWidth / 2`, or
///   rings come out a stroke-width too fat.
/// * **Rect rotation origin** — defaults to the midpoint of the LEFT EDGE, not
///   the center, so a rect can act as a stroke growing from a point.
/// * **Triangles** — `(x, y)` is the midpoint of the base, not the centroid.
/// * **Smootharcs** — a 90-degree quadrant, not a half circle.
///
/// Where Flutter has a better primitive than the React Native original (real
/// arcs instead of line-segment approximations, a real blur instead of stacked
/// shadows, one `cubicTo` instead of hundreds of dots) it uses it. Per the
/// spec's fidelity policy that is intended: position, size, angle, order,
/// color and opacity must match exactly; smoothness may exceed the original.
///
/// Uses no packages — `dart:ui` only. Adding `flutter_svg` here would defeat
/// the point of the format.
class BuoyIconPainter extends CustomPainter {
  const BuoyIconPainter(
    this.data, {
    this.colorOverride,
    this.bgColorOverride,
    this.strokeWidthOverride,
  });

  /// The icon to draw.
  final BuoyIconData data;

  /// Replaces the icon's own theme color — this is how one icon renders in a
  /// different brand color.
  final Color? colorOverride;

  /// Replaces the icon's own background color.
  final Color? bgColorOverride;

  /// REPLACES every authored stroke and border width (it does not scale them).
  ///
  /// For the uniform-stroke glyph tier, whose weight is caller-controlled —
  /// the Flutter equivalent of lucide's `strokeWidth` prop. Applying it to a
  /// brand icon whose elements deliberately vary in weight will flatten it.
  final double? strokeWidthOverride;

  /// Icons are authored on a 24x24 grid.
  static const double baseSize = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / baseSize;
    final double center = size.shortestSide / 2;
    final Color themeColor = colorOverride ?? data.color;
    final Color bgColor = bgColorOverride ?? data.bgColor;

    for (final BifElement element in data.elements) {
      switch (element) {
        case BifCircle():
          _circle(canvas, element, scale, center, themeColor, bgColor);
        case BifRect():
          _rect(canvas, element, scale, center, themeColor, bgColor);
        case BifLine():
          _line(canvas, element, scale, center, themeColor, bgColor);
        case BifTriangle():
          _triangle(canvas, element, scale, center, themeColor, bgColor);
        case BifArc():
          _arc(canvas, element, scale, center, themeColor, bgColor);
        case BifSemicircle():
          _semicircle(canvas, element, scale, center, themeColor, bgColor);
        case BifSmoothArc():
          _smoothArc(canvas, element, scale, center, themeColor, bgColor);
      }
    }
  }

  // --------------------------------------------------------------- helpers

  /// Icon units -> canvas pixels. The origin of BIF is the icon's center.
  double _px(double unit, double scale, double center) => center + unit * scale;

  /// An authored stroke width in icon units -> pixels, honoring the override.
  double _stroke(double authored, double scale) => (strokeWidthOverride ?? authored) * scale;

  Paint _paint({
    required Color color,
    required double opacity,
    required bool stroke,
    double strokeWidth = 0,
    StrokeCap cap = StrokeCap.butt,
    bool glow = false,
    double glowSigma = 0,
  }) {
    final Paint paint = Paint()
      ..color = opacity == 1.0 ? color : color.withValues(alpha: color.a * opacity)
      ..isAntiAlias = true;

    if (stroke) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = cap;
    } else {
      paint.style = PaintingStyle.fill;
    }

    if (glow && glowSigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma);
    }
    return paint;
  }

  /// A blur radius in icon units -> a Gaussian sigma in pixels.
  ///
  /// The RN original fakes glow with a shadow whose radius is a hard cutoff,
  /// while a Gaussian's visible extent is roughly 3 sigma. Dividing by 3 keeps
  /// the bloom the same visual size instead of three times too wide.
  double _glowSigma(double radiusUnits, double scale) => math.max(0.0, radiusUnits * scale / 3.0);

  double _rad(double degrees) => degrees * math.pi / 180.0;

  /// Runs [draw] with the canvas rotated [degrees] about [pivot].
  void _rotated(Canvas canvas, double? degrees, Offset pivot, VoidCallback draw) {
    if (degrees == null || degrees == 0) {
      draw();
      return;
    }
    canvas
      ..save()
      ..translate(pivot.dx, pivot.dy)
      ..rotate(_rad(degrees))
      ..translate(-pivot.dx, -pivot.dy);
    draw();
    canvas.restore();
  }

  // ---------------------------------------------------------------- circle

  void _circle(Canvas canvas, BifCircle e, double scale, double center, Color theme, Color bg) {
    final Offset origin = Offset(_px(e.cx, scale, center), _px(e.cy, scale, center));
    final double r = e.r * scale;

    // scaleX/scaleY scale about the element's own center, turning it into an
    // ellipse. Note `rotation` is intentionally unsupported here (see SPEC.md).
    final bool scaled = e.scaleX != 1.0 || e.scaleY != 1.0;
    if (scaled) {
      canvas
        ..save()
        ..translate(origin.dx, origin.dy)
        ..scale(e.scaleX, e.scaleY)
        ..translate(-origin.dx, -origin.dy);
    }

    final double glowSigma = _glowSigma(e.glowRadius, scale);

    // Glow first so it sits behind the shape, matching the RN layer order.
    if (e.glow && glowSigma > 0) {
      final Color glowColor = theme;
      if (e.border) {
        canvas.drawCircle(
          origin,
          r - _stroke(e.borderWidth, scale) / 2,
          _paint(
            color: glowColor,
            opacity: e.opacity * 0.5,
            stroke: true,
            strokeWidth: _stroke(e.borderWidth, scale),
            glow: true,
            glowSigma: glowSigma,
          ),
        );
      } else {
        canvas.drawCircle(
          origin,
          r,
          _paint(color: glowColor, opacity: e.opacity * 0.9, stroke: false, glow: true, glowSigma: glowSigma),
        );
      }
    }

    if (e.fill != null) {
      canvas.drawCircle(origin, r, _paint(color: e.fill!.resolve(theme, bg), opacity: e.opacity, stroke: false));
    }

    if (e.border) {
      final double strokeWidth = _stroke(e.borderWidth, scale);
      // Inset: `r` is the OUTER radius but Canvas centers strokes on the path.
      canvas.drawCircle(
        origin,
        r - strokeWidth / 2,
        _paint(color: theme, opacity: e.opacity, stroke: true, strokeWidth: strokeWidth),
      );
    }

    if (scaled) canvas.restore();
  }

  // ------------------------------------------------------------------ rect

  void _rect(Canvas canvas, BifRect e, double scale, double center, Color theme, Color bg) {
    final Rect rect = Rect.fromLTWH(
      _px(e.x, scale, center),
      _px(e.y, scale, center),
      e.width * scale,
      e.height * scale,
    );
    final double radius = e.borderRadius * scale;

    // Rotation origin: left-edge midpoint by default, center when asked.
    final Offset pivot = e.rotateFromCenter ? rect.center : Offset(rect.left, rect.center.dy);

    _rotated(canvas, e.rotation, pivot, () {
      final double glowSigma = _glowSigma(e.glowRadius, scale);

      if (e.glow && glowSigma > 0) {
        _drawRect(
          canvas,
          rect,
          radius,
          _paint(color: theme, opacity: e.opacity * 0.6, stroke: false, glow: true, glowSigma: glowSigma),
        );
      }

      if (e.fill != null) {
        _drawRect(
          canvas,
          rect,
          radius,
          _paint(color: e.fill!.resolve(theme, bg), opacity: e.opacity, stroke: false),
        );
      }

      if (e.border) {
        final double strokeWidth = _stroke(e.borderWidth, scale);
        // Inset for the same reason as circles: the box is the OUTER bound.
        final Rect inner = rect.deflate(strokeWidth / 2);
        _drawRect(
          canvas,
          inner,
          math.max(0.0, radius - strokeWidth / 2),
          _paint(color: theme, opacity: e.opacity, stroke: true, strokeWidth: strokeWidth),
        );
      }
    });
  }

  void _drawRect(Canvas canvas, Rect rect, double radius, Paint paint) {
    if (radius > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  // ------------------------------------------------------------------ line

  void _line(Canvas canvas, BifLine e, double scale, double center, Color theme, Color bg) {
    final Offset p1 = Offset(_px(e.x1, scale, center), _px(e.y1, scale, center));
    final Offset p2 = Offset(_px(e.x2, scale, center), _px(e.y2, scale, center));
    final double strokeWidth = _stroke(e.strokeWidth, scale);
    final Color color = e.stroke.resolve(theme, bg);
    final double glowSigma = _glowSigma(e.glowRadius, scale);

    // Round caps: the RN original is a View with borderRadius = strokeWidth / 2.
    Paint linePaint({required double opacity, bool glow = false}) => _paint(
          color: glow ? theme : color,
          opacity: opacity,
          stroke: true,
          strokeWidth: strokeWidth,
          cap: StrokeCap.round,
          glow: glow,
          glowSigma: glowSigma,
        );

    if (e.isCurved) {
      // Control points are offsets from the segment MIDPOINT, not the start.
      // Flutter draws one true Bezier where RN stamps hundreds of dots.
      final Offset mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      final Offset c1 = mid + Offset((e.curveX ?? 0) * scale, (e.curveY ?? 0) * scale);
      final Offset c2 = mid + Offset((e.curve2X ?? 0) * scale, (e.curve2Y ?? 0) * scale);

      final Path path = Path()..moveTo(p1.dx, p1.dy);
      if (e.isCubic) {
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      } else {
        final Offset c = e.usesFirstControlForQuadratic ? c1 : c2;
        path.quadraticBezierTo(c.dx, c.dy, p2.dx, p2.dy);
      }

      if (e.glow && glowSigma > 0) canvas.drawPath(path, linePaint(opacity: e.opacity * 0.5, glow: true));
      canvas.drawPath(path, linePaint(opacity: e.opacity));
      return;
    }

    // Straight: `rotation` adds to the segment's own angle, about its midpoint.
    final Offset mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    _rotated(canvas, e.rotation, mid, () {
      if (e.glow && glowSigma > 0) canvas.drawLine(p1, p2, linePaint(opacity: e.opacity * 0.5, glow: true));
      canvas.drawLine(p1, p2, linePaint(opacity: e.opacity));
    });
  }

  // -------------------------------------------------------------- triangle

  void _triangle(Canvas canvas, BifTriangle e, double scale, double center, Color theme, Color bg) {
    final double x = _px(e.x, scale, center);
    final double y = _px(e.y, scale, center);
    final double size = e.size * scale;
    final double half = size * BifTriangle.baseHalfWidthRatio;

    // (x, y) is the midpoint of the BASE; the apex is `size` away in `direction`.
    final (Offset apex, Offset baseA, Offset baseB) = switch (e.direction) {
      BifDirection.down => (Offset(x, y + size), Offset(x - half, y), Offset(x + half, y)),
      BifDirection.up => (Offset(x, y - size), Offset(x - half, y), Offset(x + half, y)),
      BifDirection.right => (Offset(x + size, y), Offset(x, y - half), Offset(x, y + half)),
      BifDirection.left => (Offset(x - size, y), Offset(x, y - half), Offset(x, y + half)),
    };

    final Path path = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(baseA.dx, baseA.dy)
      ..lineTo(baseB.dx, baseB.dy)
      ..close();

    final Offset pivot = path.getBounds().center;
    _rotated(canvas, e.rotation, pivot, () {
      canvas.drawPath(path, _paint(color: e.fill.resolve(theme, bg), opacity: e.opacity, stroke: false));
    });
  }

  // ------------------------------------------------------------------- arc

  void _arc(Canvas canvas, BifArc e, double scale, double center, Color theme, Color bg) {
    final double strokeWidth = _stroke(e.strokeWidth, scale);
    // A true arc — the `segments` hint in the format is for renderers that have
    // to approximate. Flutter ignores it, per the spec's fidelity policy.
    _strokeArc(
      canvas,
      Offset(_px(e.cx, scale, center), _px(e.cy, scale, center)),
      e.r * scale,
      _rad(e.startAngle),
      _rad(e.endAngle - e.startAngle),
      _paint(
        color: e.stroke.resolve(theme, bg),
        opacity: e.opacity,
        stroke: true,
        strokeWidth: strokeWidth,
        cap: StrokeCap.round,
      ),
      strokeWidth,
    );
  }

  // ------------------------------------------------------------ semicircle

  void _semicircle(Canvas canvas, BifSemicircle e, double scale, double center, Color theme, Color bg) {
    final Offset origin = Offset(_px(e.cx, scale, center), _px(e.cy, scale, center));
    final double r = e.r * scale;

    // Half a disc, cut through the center. 0 deg = right, sweeping clockwise.
    final double startDeg = switch (e.half) {
      BifHalf.bottom => 0.0,
      BifHalf.left => 90.0,
      BifHalf.top => 180.0,
      BifHalf.right => 270.0,
    };

    final double glowSigma = _glowSigma(e.glowRadius, scale);
    if (e.glow && glowSigma > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: r),
        _rad(startDeg),
        math.pi,
        true,
        _paint(color: theme, opacity: e.opacity * 0.6, stroke: false, glow: true, glowSigma: glowSigma),
      );
    }

    if (e.fill != null) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: r),
        _rad(startDeg),
        math.pi,
        true,
        _paint(color: e.fill!.resolve(theme, bg), opacity: e.opacity, stroke: false),
      );
    }

    if (e.border) {
      final double strokeWidth = _stroke(e.borderWidth, scale);
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: r - strokeWidth / 2),
        _rad(startDeg),
        math.pi,
        true,
        _paint(color: theme, opacity: e.opacity, stroke: true, strokeWidth: strokeWidth),
      );
    }
  }

  // ------------------------------------------------------------ smooth arc

  void _smoothArc(Canvas canvas, BifSmoothArc e, double scale, double center, Color theme, Color bg) {
    final double strokeWidth = _stroke(e.strokeWidth, scale);

    // A QUADRANT, not a half: the RN original colors one border of a rounded
    // box, and CSS splits a border box along its diagonals.
    final double startDeg = switch (e.portion) {
      BifPortion.right => -45.0,
      BifPortion.bottom => 45.0,
      BifPortion.left => 135.0,
      BifPortion.top => 225.0,
    };

    _strokeArc(
      canvas,
      Offset(_px(e.cx, scale, center), _px(e.cy, scale, center)),
      e.r * scale,
      _rad(startDeg),
      _rad(90),
      _paint(
        color: e.stroke.resolve(theme, bg),
        opacity: e.opacity,
        stroke: true,
        strokeWidth: strokeWidth,
      ),
      strokeWidth,
    );
  }

  /// Strokes an arc whose [outerRadius] is the OUTER bound, insetting so the
  /// stroke lands inside it exactly like an RN border does.
  void _strokeArc(
    Canvas canvas,
    Offset origin,
    double outerRadius,
    double startRad,
    double sweepRad,
    Paint paint,
    double strokeWidth,
  ) {
    canvas.drawArc(
      Rect.fromCircle(center: origin, radius: outerRadius - strokeWidth / 2),
      startRad,
      sweepRad,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant BuoyIconPainter old) =>
      !identical(old.data, data) ||
      old.colorOverride != colorOverride ||
      old.bgColorOverride != bgColorOverride ||
      old.strokeWidthOverride != strokeWidthOverride;
}

/// Draws a Buoy icon at [size] logical pixels.
///
/// The Flutter counterpart of RN's `createIcon(iconData)` components, rendering
/// the same `shared/icons/*.json` artwork:
///
/// ```dart
/// BuoyIcon(networkIconData, size: 32)
/// BuoyIcon(networkIconData, size: 32, color: theme.accent) // recolored
/// ```
class BuoyIcon extends StatelessWidget {
  const BuoyIcon(
    this.data, {
    super.key,
    this.size = 24,
    this.color,
    this.bgColor,
    this.strokeWidth,
  });

  final BuoyIconData data;

  /// Rendered width and height, in logical pixels.
  final double size;

  /// Overrides the icon's brand color. Null keeps the icon's own.
  final Color? color;

  /// Overrides the icon's background color. Null keeps the icon's own.
  final Color? bgColor;

  /// Replaces every authored stroke width — see
  /// [BuoyIconPainter.strokeWidthOverride]. Intended for the glyph tier.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    // `CustomPaint.size` is only a PREFERENCE — RenderCustomPaint resolves it
    // as `constraints.constrain(size)`, so a tight parent (e.g.
    // HeaderActionButton's 32×32 Container, or any `Container(width:, height:)`
    // with no alignment) would stretch the canvas and the painter would scale
    // the glyph to fill it. Center loosens the incoming constraints and the
    // SizedBox then pins the paint area to exactly `size` — the same shape
    // Material's own [Icon] uses, and why Material glyphs never inflated here.
    return Center(
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(size),
            isComplex: true,
            willChange: false,
            painter: BuoyIconPainter(
              data,
              colorOverride: color,
              bgColorOverride: bgColor,
              strokeWidthOverride: strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a Buoy UI glyph — the lucide tier — as a drop-in for Flutter's [Icon].
///
/// Glyphs are monochrome and take their color from the caller, so this mirrors
/// `Icon(glyph, size: …, color: …)` and can replace it one call site at a time.
/// It defaults to the ambient [IconTheme] exactly as [Icon] does, which is why
/// swapping `Icon(` for `BuoyGlyph(` needs no other changes.
///
/// ```dart
/// BuoyGlyph(BuoyIcons.filter, size: 14, color: macOSColors.text.secondary)
/// ```
class BuoyGlyph extends StatelessWidget {
  const BuoyGlyph(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
  });

  /// Nullable exactly like [Icon.icon]: a null glyph renders blank space of the
  /// right size, so optional-icon call sites need no null check.
  final BuoyIconData? glyph;

  /// Falls back to the ambient [IconTheme], like [Icon].
  final double? size;

  /// Falls back to the ambient [IconTheme], like [Icon].
  final Color? color;

  /// Stroke weight, replacing the authored 2. Lucide's `strokeWidth` prop.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final IconThemeData theme = IconTheme.of(context);
    final double resolved = size ?? theme.size ?? 24;

    final BuoyIconData? data = glyph;
    if (data == null) return SizedBox.square(dimension: resolved);

    return BuoyIcon(
      data,
      size: resolved,
      color: color ?? theme.color,
      strokeWidth: strokeWidth,
    );
  }
}
