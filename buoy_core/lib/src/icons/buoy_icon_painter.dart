import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'generated/icon_glow_styles.g.dart';
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
/// arcs instead of line-segment approximations, one `cubicTo` instead of
/// hundreds of dots) it uses it. Per the spec's fidelity policy that is
/// intended: position, size, angle, order, color and opacity must match
/// exactly; smoothness may exceed the original.
///
/// GLOW is not in that category. RN renders a glow as a CALayer shadow with a
/// specific opacity and radius per element kind, and those numbers live in ONE
/// table (`packages/floating-tools-core/src/icons/iconGlow.ts` → the generated
/// [IconGlowStyles]) so no port re-types them. A filled element casts one
/// shadow of its own silhouette; a border-only ring, a line and a border-only
/// rect get a separate twin drawn UNDERNEATH with a FIXED shadow radius. A
/// "looks better" blur is a parity bug — the iOS port had exactly that one,
/// and the network icon's halo came out several points too wide.
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
  double _stroke(double authored, double scale) =>
      (strokeWidthOverride ?? authored) * scale;

  Paint _paint({
    required Color color,
    required double opacity,
    required bool stroke,
    double strokeWidth = 0,
    StrokeCap cap = StrokeCap.butt,
  }) {
    final Paint paint = Paint()
      ..color = opacity == 1.0
          ? color
          : color.withValues(alpha: color.a * opacity)
      ..isAntiAlias = true;

    if (stroke) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = cap;
    } else {
      paint.style = PaintingStyle.fill;
    }

    return paint;
  }

  /// A shadow RADIUS (the number RN puts in `shadowRadius`) -> the Gaussian
  /// sigma `ImageFilter.blur` wants.
  ///
  /// Both sides are Gaussians, so this is the ONE calibration constant in the
  /// renderer. Quartz's shadow blur is ~2 sigma wide, which is where 0.5 comes
  /// from; change it ONLY from a parity-sheet measurement — `pnpm parity boxes
  /// icons/network-32` prints the halo spread and edge softness on both sides.
  static const double sigmaPerShadowRadius = 1.0;

  double _sigma(double shadowRadiusPx) =>
      math.max(0.0, shadowRadiusPx * sigmaPerShadowRadius);

  /// The layer a glow is composited into. The blur bleeds well past the icon
  /// box, so the layer is the icon square grown by half its size on every side
  /// (the same bleed the iOS renderer uses); the LAYOUT box is untouched.
  Rect _glowBounds(double center) =>
      Rect.fromLTRB(-center, -center, center * 3, center * 3);

  /// RN's filled glow: ONE shadow of the element's whole silhouette, in the
  /// ICON colour. `draw` runs twice — once into the blurred, recoloured layer
  /// and once crisp on top — so a fill and its border cast a single shadow
  /// rather than two that stack ~1.35x brighter at the edge.
  void _filledGlow(
    Canvas canvas,
    double center,
    Color color,
    double glowRadiusPx,
    VoidCallback draw,
  ) {
    final double sigma = _sigma(
      glowRadiusPx * IconGlowStyles.ICON_GLOW_filledRadiusScale,
    );
    if (sigma <= 0) {
      draw();
      return;
    }
    canvas.saveLayer(
      _glowBounds(center),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
        ..colorFilter = ColorFilter.mode(
          color.withValues(alpha: IconGlowStyles.ICON_GLOW_filledShadowOpacity),
          BlendMode.srcIn,
        ),
    );
    draw();
    canvas.restore();
    draw();
  }

  /// RN's separate glow LAYER: a twin View drawn under the element at
  /// `layerOpacity`, casting a shadow of `shadowOpacity` at a FIXED radius in
  /// points (unscaled, exactly like RN). `drawTwin` paints the twin's body.
  void _twinGlow(
    Canvas canvas,
    double center,
    Color color, {
    required double layerOpacity,
    required double shadowRadius,
    required double shadowOpacity,
    required VoidCallback drawTwin,
  }) {
    final double sigma = _sigma(shadowRadius);
    canvas.saveLayer(
      _glowBounds(center),
      Paint()..color = Color.fromRGBO(0, 0, 0, layerOpacity),
    );
    if (sigma > 0) {
      canvas.saveLayer(
        _glowBounds(center),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
          ..colorFilter = ColorFilter.mode(
            color.withValues(alpha: shadowOpacity),
            BlendMode.srcIn,
          ),
      );
      drawTwin();
      canvas.restore();
    }
    drawTwin();
    canvas.restore();
  }

  /// Moves `p` towards `q` by `d` pixels, never past the midpoint.
  static Offset _moved(Offset p, Offset q, double d) {
    final double dx = q.dx - p.dx;
    final double dy = q.dy - p.dy;
    final double len = math.max(0.0001, math.sqrt(dx * dx + dy * dy));
    final double k = math.min(d, len / 2) / len;
    return Offset(p.dx + dx * k, p.dy + dy * k);
  }

  double _rad(double degrees) => degrees * math.pi / 180.0;

  /// Runs [draw] with the canvas rotated [degrees] about [pivot].
  void _rotated(
    Canvas canvas,
    double? degrees,
    Offset pivot,
    VoidCallback draw,
  ) {
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

  void _circle(
    Canvas canvas,
    BifCircle e,
    double scale,
    double center,
    Color theme,
    Color bg,
  ) {
    final Offset origin = Offset(
      _px(e.cx, scale, center),
      _px(e.cy, scale, center),
    );
    final double r = e.r * scale;
    final double strokeWidth = _stroke(e.borderWidth, scale);
    // `r` is the OUTER radius but Canvas centres strokes on the path.
    final double innerR = r - strokeWidth / 2;
    final Color? fill = e.fill?.resolve(theme, bg);
    final Color borderColor = e.borderColor?.resolve(theme, bg) ?? theme;
    // RN: the glow colour is the ICON colour, never the fill.
    final Color glowColor = theme;
    final double glowRadius = e.glowRadius * scale;

    // RN draws the UNSCALED circle (border `borderWidth` all round) and then
    // applies `transform: [{scaleX}, {scaleY}]` to the whole View — so a
    // squashed ring's border is thin on the squashed sides. `canvas.scale`
    // about the element's own centre reproduces that; stroking a pre-squashed
    // ellipse with a uniform width does not.
    final bool scaled = e.scaleX != 1.0 || e.scaleY != 1.0;
    if (scaled) {
      canvas
        ..save()
        ..translate(origin.dx, origin.dy)
        ..scale(e.scaleX, e.scaleY)
        ..translate(-origin.dx, -origin.dy);
    }

    void body() {
      if (fill != null) {
        canvas.drawCircle(
          origin,
          r,
          _paint(color: fill, opacity: e.opacity, stroke: false),
        );
      }
      if (e.border && innerR > 0) {
        canvas.drawCircle(
          origin,
          innerR,
          _paint(
            color: borderColor,
            opacity: e.opacity,
            stroke: true,
            strokeWidth: strokeWidth,
          ),
        );
      }
    }

    if (e.glow && glowRadius > 0 && fill != null) {
      _filledGlow(canvas, center, glowColor, glowRadius, body);
    } else if (e.glow && glowRadius > 0) {
      // RN ring glow: a same-size ring with a BLACK fill and a glow-colour
      // border, at 0.5 opacity with a fixed 8 pt shadow, under the real ring.
      _twinGlow(
        canvas,
        center,
        glowColor,
        layerOpacity: IconGlowStyles.ICON_GLOW_ringLayerOpacity,
        shadowRadius: IconGlowStyles.ICON_GLOW_ringShadowRadius,
        shadowOpacity: IconGlowStyles.ICON_GLOW_ringShadowOpacity,
        drawTwin: () {
          canvas.drawCircle(
            origin,
            r,
            _paint(color: const Color(0xFF000000), opacity: 1, stroke: false),
          );
          if (innerR > 0) {
            canvas.drawCircle(
              origin,
              innerR,
              _paint(
                color: glowColor,
                opacity: 1,
                stroke: true,
                strokeWidth: math.max(strokeWidth, scale),
              ),
            );
          }
        },
      );
      body();
    } else {
      body();
    }

    if (scaled) canvas.restore();
  }

  // ------------------------------------------------------------------ rect

  void _rect(
    Canvas canvas,
    BifRect e,
    double scale,
    double center,
    Color theme,
    Color bg,
  ) {
    final Rect rect = Rect.fromLTWH(
      _px(e.x, scale, center),
      _px(e.y, scale, center),
      e.width * scale,
      e.height * scale,
    );
    final double radius = e.borderRadius * scale;
    final double strokeWidth = _stroke(e.borderWidth, scale);
    final Rect inner = rect.deflate(strokeWidth / 2);
    final Color? fill = e.fill?.resolve(theme, bg);
    final Color borderColor = e.borderColor?.resolve(theme, bg) ?? theme;
    final double glowRadius = e.glowRadius * scale;

    // Rotation origin: left-edge midpoint by default, center when asked.
    final Offset pivot = e.rotateFromCenter
        ? rect.center
        : Offset(rect.left, rect.center.dy);

    _rotated(canvas, e.rotation, pivot, () {
      void body() {
        if (fill != null) {
          _drawRect(
            canvas,
            rect,
            radius,
            _paint(color: fill, opacity: e.opacity, stroke: false),
          );
        }
        if (e.border && inner.width > 0 && inner.height > 0) {
          // The inner edge keeps the same visual corner: shrink the radius with it.
          _drawRect(
            canvas,
            inner,
            math.max(0.0, radius - strokeWidth / 2),
            _paint(
              color: borderColor,
              opacity: e.opacity,
              stroke: true,
              strokeWidth: strokeWidth,
            ),
          );
        }
      }

      if (e.glow && glowRadius > 0 && fill != null) {
        _filledGlow(canvas, center, theme, glowRadius, body);
      } else if (e.glow && glowRadius > 0) {
        // RN rect glow: the rect expanded by the stroke width, bordered at
        // 2x the stroke, 0.4 opacity, shadow radius 4x the stroke at 0.8.
        final double sw = math.max(strokeWidth, scale);
        _twinGlow(
          canvas,
          center,
          theme,
          layerOpacity: IconGlowStyles.ICON_GLOW_rectLayerOpacity,
          shadowRadius: sw * IconGlowStyles.ICON_GLOW_rectShadowRadiusScale,
          shadowOpacity: IconGlowStyles.ICON_GLOW_rectShadowOpacity,
          drawTwin: () => _drawRect(
            canvas,
            rect,
            math.max(0.0, radius),
            _paint(
              color: theme,
              opacity: 1,
              stroke: true,
              strokeWidth: sw * IconGlowStyles.ICON_GLOW_rectBorderScale,
            ),
          ),
        );
        body();
      } else {
        body();
      }
    });
  }

  void _drawRect(Canvas canvas, Rect rect, double radius, Paint paint) {
    if (radius > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  // ------------------------------------------------------------------ line

  void _line(
    Canvas canvas,
    BifLine e,
    double scale,
    double center,
    Color theme,
    Color bg,
  ) {
    final double strokeWidth = _stroke(e.strokeWidth, scale);
    final Color color = e.stroke.resolve(theme, bg);
    final double glowRadius = e.glowRadius * scale;
    final Path path = _linePath(e, scale, center, inset: strokeWidth / 2);

    Paint linePaint() => _paint(
      color: color,
      opacity: e.opacity,
      stroke: true,
      strokeWidth: strokeWidth,
      cap: StrokeCap.round,
    );

    if (e.glow && glowRadius > 0) {
      // RN line glow: the SAME line in the glow colour at 0.5 opacity with a
      // fixed 8 pt shadow, drawn under the crisp one.
      _twinGlow(
        canvas,
        center,
        color,
        layerOpacity: IconGlowStyles.ICON_GLOW_lineLayerOpacity,
        shadowRadius: IconGlowStyles.ICON_GLOW_lineShadowRadius,
        shadowOpacity: IconGlowStyles.ICON_GLOW_lineShadowOpacity,
        drawTwin: () => canvas.drawPath(
          path,
          _paint(
            color: color,
            opacity: 1,
            stroke: true,
            strokeWidth: strokeWidth,
            cap: StrokeCap.round,
          ),
        ),
      );
    }
    canvas.drawPath(path, linePaint());
  }

  /// The line's path, with both ends pulled in by [inset].
  ///
  /// An RN line is a capsule exactly `length` long — its round ends sit INSIDE
  /// the length — while a stroked path with round caps sticks out by half the
  /// stroke at each end. Pulling both endpoints in by half the stroke makes the
  /// extents equal (the fix for the bolder routes S, the wider wifi arcs and
  /// the blobs at the highlighter's joins on iOS).
  Path _linePath(BifLine e, double scale, double center, {double inset = 0}) {
    Offset start = Offset(_px(e.x1, scale, center), _px(e.y1, scale, center));
    Offset end = Offset(_px(e.x2, scale, center), _px(e.y2, scale, center));
    final Offset mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final Path path = Path();

    if (e.isCurved) {
      // Control points are offsets from the segment MIDPOINT, not the start.
      // Flutter draws one true Bezier where RN stamps hundreds of dots.
      final Offset c1 =
          mid + Offset((e.curveX ?? 0) * scale, (e.curveY ?? 0) * scale);
      final Offset c2 =
          mid + Offset((e.curve2X ?? 0) * scale, (e.curve2Y ?? 0) * scale);
      final bool has1 = (e.curveX ?? 0) != 0 || (e.curveY ?? 0) != 0;
      if (inset > 0) {
        // Trim along the end tangents (towards the first / last control point).
        final Offset cs = has1 ? c1 : c2;
        final Offset ce = e.isCubic ? c2 : cs;
        start = _moved(start, cs, inset);
        end = _moved(end, ce, inset);
      }
      path.moveTo(start.dx, start.dy);
      if (e.isCubic) {
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
      } else {
        final Offset c = e.usesFirstControlForQuadratic ? c1 : c2;
        path.quadraticBezierTo(c.dx, c.dy, end.dx, end.dy);
      }
      return path;
    }

    // Straight: `rotation` adds to the segment's own angle, about its midpoint.
    if (e.rotation != null && e.rotation != 0) {
      final double a = _rad(e.rotation!);
      Offset spin(Offset p) {
        final double dx = p.dx - mid.dx;
        final double dy = p.dy - mid.dy;
        return Offset(
          mid.dx + dx * math.cos(a) - dy * math.sin(a),
          mid.dy + dx * math.sin(a) + dy * math.cos(a),
        );
      }

      start = spin(start);
      end = spin(end);
    }
    if (inset > 0) {
      final Offset s0 = start;
      final Offset e0 = end;
      start = _moved(s0, e0, inset);
      end = _moved(e0, s0, inset);
    }
    path
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    return path;
  }

  // -------------------------------------------------------------- triangle

  void _triangle(
    Canvas canvas,
    BifTriangle e,
    double scale,
    double center,
    Color theme,
    Color bg,
  ) {
    final double x = _px(e.x, scale, center);
    final double y = _px(e.y, scale, center);
    final double size = e.size * scale;
    final double half = size * BifTriangle.baseHalfWidthRatio;

    // (x, y) is the midpoint of the BASE; the apex is `size` away in `direction`.
    final (Offset apex, Offset baseA, Offset baseB) = switch (e.direction) {
      BifDirection.down => (
        Offset(x, y + size),
        Offset(x - half, y),
        Offset(x + half, y),
      ),
      BifDirection.up => (
        Offset(x, y - size),
        Offset(x - half, y),
        Offset(x + half, y),
      ),
      BifDirection.right => (
        Offset(x + size, y),
        Offset(x, y - half),
        Offset(x, y + half),
      ),
      BifDirection.left => (
        Offset(x - size, y),
        Offset(x, y - half),
        Offset(x, y + half),
      ),
    };

    final Path path = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(baseA.dx, baseA.dy)
      ..lineTo(baseB.dx, baseB.dy)
      ..close();

    final Offset pivot = path.getBounds().center;
    _rotated(canvas, e.rotation, pivot, () {
      canvas.drawPath(
        path,
        _paint(
          color: e.fill.resolve(theme, bg),
          opacity: e.opacity,
          stroke: false,
        ),
      );
    });
  }

  // ------------------------------------------------------------------- arc

  void _arc(
    Canvas canvas,
    BifArc e,
    double scale,
    double center,
    Color theme,
    Color bg,
  ) {
    final double strokeWidth = _stroke(e.strokeWidth, scale);
    // Inset: `r` is the OUTER radius.
    final double r = e.r * scale - strokeWidth / 2;
    // Round caps stick out by half a stroke ALONG THE ARC, so the angular
    // equivalent of the line inset is `sw / 2r` radians at each end — the same
    // capsule rule as [_linePath].
    final double capRad = strokeWidth / 2 / math.max(r, 0.001);
    final double from = _rad(e.startAngle) + capRad;
    final double to = _rad(e.endAngle) - capRad;
    // A true arc — the `segments` hint in the format is for renderers that have
    // to approximate. Flutter ignores it, per the spec's fidelity policy.
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(_px(e.cx, scale, center), _px(e.cy, scale, center)),
        radius: r,
      ),
      from,
      math.max(0.0, to - from),
      false,
      _paint(
        color: e.stroke.resolve(theme, bg),
        opacity: e.opacity,
        stroke: true,
        strokeWidth: strokeWidth,
        cap: StrokeCap.round,
      ),
    );
  }

  // ------------------------------------------------------------ semicircle

  void _semicircle(
    Canvas canvas,
    BifSemicircle e,
    double scale,
    double center,
    Color theme,
    Color bg,
  ) {
    final Offset origin = Offset(
      _px(e.cx, scale, center),
      _px(e.cy, scale, center),
    );
    final double r = e.r * scale;

    // Half a disc, cut through the center. 0 deg = right, sweeping clockwise.
    final double startDeg = switch (e.half) {
      BifHalf.bottom => 0.0,
      BifHalf.left => 90.0,
      BifHalf.top => 180.0,
      BifHalf.right => 270.0,
    };

    final Color? fill = e.fill?.resolve(theme, bg);
    final double strokeWidth = _stroke(e.borderWidth, scale);
    final double glowRadius = e.glowRadius * scale;

    void body() {
      if (fill != null) {
        canvas.drawArc(
          Rect.fromCircle(center: origin, radius: r),
          _rad(startDeg),
          math.pi,
          true,
          _paint(color: fill, opacity: e.opacity, stroke: false),
        );
      }
      if (e.border) {
        canvas.drawArc(
          Rect.fromCircle(center: origin, radius: r - strokeWidth / 2),
          _rad(startDeg),
          math.pi,
          true,
          _paint(
            color: e.borderColor?.resolve(theme, bg) ?? theme,
            opacity: e.opacity,
            stroke: true,
            strokeWidth: strokeWidth,
          ),
        );
      }
    }

    if (e.glow && glowRadius > 0 && fill != null) {
      _filledGlow(canvas, center, theme, glowRadius, body);
    } else {
      body();
    }
  }

  // ------------------------------------------------------------ smooth arc

  void _smoothArc(
    Canvas canvas,
    BifSmoothArc e,
    double scale,
    double center,
    Color theme,
    Color bg,
  ) {
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
  /// stroke lands inside it exactly like an RN border does. Used by
  /// `smoothArc`, whose ends are cut SQUARE by the quadrant boundary (RN draws
  /// it as a circle View with only some borders coloured) — butt caps, exact
  /// angles, no cap inset.
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
    // `Align` with both factors 1 — NOT `Center`: Center expands to its
    // constraints, so an icon dropped into a loose parent (a row, the parity
    // sheet's hug box) measured the whole available width instead of `size`.
    // The factors keep the loosening this needs (see the note above) while the
    // box still shrink-wraps to `size`.
    return Align(
      widthFactor: 1,
      heightFactor: 1,
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
