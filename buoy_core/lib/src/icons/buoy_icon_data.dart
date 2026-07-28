/// The Dart model of the **Buoy Icon Format** (BIF).
///
/// Icons are authored once as framework-neutral JSON in `shared/icons/*.json`
/// and generated into every framework, so the Flutter build renders the exact
/// same artwork as React Native and the desktop dashboard. The normative
/// rendering contract is `shared/icons/SPEC.md` — read it before touching
/// [BuoyIconPainter]; several of these fields have geometry that is easy to get
/// subtly wrong (inset strokes, quadrant arcs, base-midpoint triangles).
///
/// Everything here is `const` so whole icons fold into the constant pool: an
/// icon costs no allocation and no parsing at runtime.
///
/// Coordinates are in 24x24 units **relative to the icon's center**, +x right
/// and +y down. A renderer drawing at pixel size `S` scales everything by
/// `S / 24`.
library;

import 'dart:ui' show Color;

/// Where a [BifPaint] takes its color from.
enum BifPaintSource {
  /// The icon's own [BuoyIconData.color] (or the caller's override) — BIF `'color'`.
  theme,

  /// The icon's own [BuoyIconData.bgColor] (or the caller's override) — BIF `'bg'`.
  background,

  /// A literal color baked into the icon — BIF `'#RRGGBB'`.
  literal,
}

/// A BIF color reference: a source plus an optional opacity multiplier (the
/// `':NN'` suffix in the JSON, e.g. `'color:50'`).
class BifPaint {
  const BifPaint(this.source, {this.literal, this.opacity = 1.0});

  /// The icon's theme color at full opacity.
  static const BifPaint theme = BifPaint(BifPaintSource.theme);

  /// The icon's background color at full opacity.
  static const BifPaint background = BifPaint(BifPaintSource.background);

  final BifPaintSource source;

  /// Set only when [source] is [BifPaintSource.literal].
  final Color? literal;

  /// 0..1 multiplier applied on top of the element's own `opacity`.
  final double opacity;

  /// Resolves against the icon's (possibly overridden) theme and background.
  Color resolve(Color themeColor, Color bgColor) {
    final Color base = switch (source) {
      BifPaintSource.theme => themeColor,
      BifPaintSource.background => bgColor,
      BifPaintSource.literal => literal ?? const Color(0x00000000),
    };
    return opacity == 1.0 ? base : base.withValues(alpha: base.a * opacity);
  }
}

/// Apex direction of a [BifTriangle].
enum BifDirection { up, down, left, right }

/// Which half of a [BifSemicircle] is painted.
enum BifHalf { top, bottom, left, right }

/// Which 90-degree quadrant a [BifSmoothArc] paints. NOT a half — see
/// `shared/icons/SPEC.md`, "Smootharc geometry".
enum BifPortion { top, bottom, left, right }

/// One shape in an icon. Elements paint in list order; index 0 is furthest back.
sealed class BifElement {
  const BifElement();
}

/// A circle or, via [scaleX]/[scaleY], an ellipse.
///
/// [r] is the **outer** radius: a border is stroked *inside* it, so thickening
/// the border never grows the shape.
final class BifCircle extends BifElement {
  const BifCircle({
    required this.cx,
    required this.cy,
    required this.r,
    this.fill,
    this.border = false,
    this.borderWidth = 2.0,
    this.opacity = 1.0,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.glow = false,
    this.glowRadius = 4.0,
  });

  final double cx;
  final double cy;
  final double r;
  final BifPaint? fill;
  final bool border;
  final double borderWidth;
  final double opacity;

  /// Scale about the element's own center.
  final double scaleX;
  final double scaleY;
  final bool glow;
  final double glowRadius;
}

/// An axis-aligned rectangle, optionally rounded and/or rotated.
///
/// [x]/[y] are the **outer** top-left corner (pre-rotation); a border is
/// stroked inside the box.
final class BifRect extends BifElement {
  const BifRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.fill,
    this.border = false,
    this.borderWidth = 1.0,
    this.borderRadius = 0.0,
    this.opacity = 1.0,
    this.rotation,
    this.rotateFromCenter = false,
    this.glow = false,
    this.glowRadius = 4.0,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final BifPaint? fill;
  final bool border;
  final double borderWidth;
  final double borderRadius;
  final double opacity;

  /// Degrees, clockwise. Null means no rotation.
  final double? rotation;

  /// Rotation origin: false (default) = midpoint of the LEFT EDGE, so the rect
  /// behaves like a stroke growing from a point; true = the rect's center.
  final bool rotateFromCenter;
  final bool glow;
  final double glowRadius;
}

/// A round-capped straight segment, or a Bezier when a control point is set.
///
/// Control points are offsets from the segment's **midpoint**, not its start.
/// Both pairs set => cubic; exactly one set => quadratic.
final class BifLine extends BifElement {
  const BifLine({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.stroke = BifPaint.theme,
    this.strokeWidth = 1.0,
    this.opacity = 1.0,
    this.rotation,
    this.curveX,
    this.curveY,
    this.curve2X,
    this.curve2Y,
    this.glow = false,
    this.glowRadius = 4.0,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final BifPaint stroke;
  final double strokeWidth;
  final double opacity;

  /// Extra degrees about the segment's midpoint, added to its own angle.
  /// Ignored when the line is curved.
  final double? rotation;

  final double? curveX;
  final double? curveY;
  final double? curve2X;
  final double? curve2Y;
  final bool glow;
  final double glowRadius;

  bool get _hasControl1 => (curveX ?? 0) != 0 || (curveY ?? 0) != 0;
  bool get _hasControl2 => (curve2X ?? 0) != 0 || (curve2Y ?? 0) != 0;

  /// True when either control pair is non-zero.
  bool get isCurved => _hasControl1 || _hasControl2;

  /// True when both control pairs are set (otherwise a curved line is quadratic).
  bool get isCubic => _hasControl1 && _hasControl2;

  /// The single control point of a quadratic curve.
  bool get usesFirstControlForQuadratic => _hasControl1;
}

/// An isoceles triangle. [x]/[y] is the **midpoint of the base**; the apex sits
/// [size] units away in [direction]. Base half-width is `size * 0.577`.
final class BifTriangle extends BifElement {
  const BifTriangle({
    required this.x,
    required this.y,
    required this.size,
    required this.direction,
    this.fill = BifPaint.theme,
    this.opacity = 1.0,
    this.rotation,
  });

  /// Base half-width as a fraction of [size] — an equilateral-ish triangle.
  static const double baseHalfWidthRatio = 0.577;

  final double x;
  final double y;
  final double size;
  final BifDirection direction;
  final BifPaint fill;
  final double opacity;

  /// Degrees about the triangle's own center.
  final double? rotation;
}

/// A stroked circular arc sweeping clockwise from [startAngle] to [endAngle].
/// Degrees, 0 = right (+x), 90 = down (+y).
final class BifArc extends BifElement {
  const BifArc({
    required this.cx,
    required this.cy,
    required this.r,
    required this.startAngle,
    required this.endAngle,
    this.stroke = BifPaint.theme,
    this.strokeWidth = 1.5,
    this.opacity = 1.0,
  });

  final double cx;
  final double cy;
  final double r;
  final double startAngle;
  final double endAngle;
  final BifPaint stroke;
  final double strokeWidth;
  final double opacity;
}

/// Half of a filled circle, cut through the center.
final class BifSemicircle extends BifElement {
  const BifSemicircle({
    required this.cx,
    required this.cy,
    required this.r,
    required this.half,
    this.fill,
    this.border = false,
    this.borderWidth = 2.0,
    this.opacity = 1.0,
    this.glow = false,
    this.glowRadius = 4.0,
  });

  final double cx;
  final double cy;
  final double r;
  final BifHalf half;
  final BifPaint? fill;
  final bool border;
  final double borderWidth;
  final double opacity;
  final bool glow;
  final double glowRadius;
}

/// A stroked **90-degree quadrant** centered on [portion] — bounded by the
/// diagonals, because it originates in a CSS border trick. [r] is the outer
/// radius; the stroke lies inside it.
final class BifSmoothArc extends BifElement {
  const BifSmoothArc({
    required this.cx,
    required this.cy,
    required this.r,
    this.portion = BifPortion.bottom,
    this.stroke = BifPaint.theme,
    this.strokeWidth = 2.0,
    this.opacity = 1.0,
  });

  final double cx;
  final double cy;
  final double r;
  final BifPortion portion;
  final BifPaint stroke;
  final double strokeWidth;
  final double opacity;
}

/// A complete icon: its palette plus the shapes that make it up.
class BuoyIconData {
  const BuoyIconData({
    required this.color,
    required this.bgColor,
    required this.elements,
  });

  /// What a [BifPaintSource.theme] reference resolves to, unless overridden.
  final Color color;

  /// What a [BifPaintSource.background] reference resolves to, unless overridden.
  final Color bgColor;

  /// Painted in order: index 0 is furthest back.
  final List<BifElement> elements;
}
