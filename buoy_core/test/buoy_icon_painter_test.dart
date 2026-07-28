import 'dart:math' as math;
import 'dart:ui';

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Geometry parity tests for the Flutter renderer of the Buoy Icon Format.
///
/// These pin the rules in `shared/icons/SPEC.md` that are easy to get subtly
/// wrong — the ones where a mistake still *looks* like an icon, so it ships:
/// inset strokes, base-midpoint triangles, quadrant smootharcs, and control
/// points measured from the segment midpoint.
///
/// They assert what the painter actually asks the canvas to draw, so a
/// regression fails here rather than in someone's eyeballs.
void main() {

  group('sizing under tight constraints', () {
    // Regression: RenderCustomPaint resolves its `size` as
    // `constraints.constrain(size)`, so before BuoyIcon centred + pinned its
    // paint area, every glyph inside a tight box — HeaderActionButton's 32x32
    // Container, dial slots, any `Container(width:, height:)` — stretched to
    // fill it and the painter scaled the artwork up with it.
    Size paintedSize(WidgetTester tester) => tester.getSize(
          find
              .descendant(
                of: find.byType(BuoyIcon),
                matching: find.byType(CustomPaint),
              )
              .first,
        );

    testWidgets('a 14pt glyph stays 14pt inside a tight 32x32 box',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: BuoyGlyph(BuoyIcons.search, size: 14),
            ),
          ),
        ),
      );
      expect(paintedSize(tester), const Size(14, 14));
    });

    testWidgets('unbounded constraints still honour the requested size',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: BuoyGlyph(BuoyIcons.power, size: 18)),
        ),
      );
      expect(paintedSize(tester), const Size(18, 18));
    });
  });
  const Color theme = Color(0xFF00D4FF);
  const Color bg = Color(0xFF000000);

  /// Paints [elements] at [size] and returns the recorded canvas calls.
  _Recorder paint(List<BifElement> elements, {double size = 24}) {
    final _Recorder canvas = _Recorder();
    BuoyIconPainter(
      BuoyIconData(color: theme, bgColor: bg, elements: elements),
    ).paint(canvas, Size.square(size));
    return canvas;
  }

  /// The point halfway ALONG a path.
  ///
  /// [Path.getBounds] is conservative for Beziers — it bounds the control
  /// points, not the curve — so it cannot tell a quadratic from a cubic with
  /// the same handles. Sampling the real curve can.
  Offset midpointOf(Path path) {
    final PathMetric metric = path.computeMetrics().first;
    return metric.getTangentForOffset(metric.length / 2)!.position;
  }

  group('coordinate system', () {
    test('origin is the icon center, and +y is down', () {
      final _Recorder c = paint(const <BifElement>[
        BifCircle(cx: 0, cy: 0, r: 1, fill: BifPaint.theme),
        BifCircle(cx: 0, cy: 6, r: 1, fill: BifPaint.theme),
      ]);

      expect(c.circles[0].center, const Offset(12, 12), reason: '(0,0) is the center of a 24px icon');
      expect(c.circles[1].center, const Offset(12, 18), reason: '+y must move DOWN');
    });

    test('everything scales linearly with the rendered size', () {
      final _Recorder small = paint(const <BifElement>[
        BifCircle(cx: 4, cy: 0, r: 3, border: true, borderWidth: 2),
      ]);
      final _Recorder big = paint(const <BifElement>[
        BifCircle(cx: 4, cy: 0, r: 3, border: true, borderWidth: 2),
      ], size: 48);

      // 48px is exactly 2x the 24-unit authoring grid.
      expect(big.circles.single.radius, closeTo(small.circles.single.radius * 2, 1e-9));
      expect(big.circles.single.paint.strokeWidth, closeTo(small.circles.single.paint.strokeWidth * 2, 1e-9));
      expect(big.circles.single.center.dx - 24, closeTo((small.circles.single.center.dx - 12) * 2, 1e-9));
    });
  });

  group('inset strokes (the #1 source of cross-framework drift)', () {
    test('a circle border is stroked INSIDE the outer radius', () {
      final _Recorder c = paint(const <BifElement>[
        BifCircle(cx: 0, cy: 0, r: 9, border: true, borderWidth: 2),
      ]);

      // r is the OUTER radius; Canvas centers strokes, so it must inset by
      // half the stroke. Drawing at r=9 would be a stroke-width too fat.
      expect(c.circles.single.radius, 8.0);
      expect(c.circles.single.paint.strokeWidth, 2.0);
      expect(c.circles.single.paint.style, PaintingStyle.stroke);
    });

    test('a circle fill uses the full outer radius', () {
      final _Recorder c = paint(const <BifElement>[
        BifCircle(cx: 0, cy: 0, r: 9, fill: BifPaint.theme),
      ]);
      expect(c.circles.single.radius, 9.0);
      expect(c.circles.single.paint.style, PaintingStyle.fill);
    });

    test('a rect border is stroked inside the outer box', () {
      final _Recorder c = paint(const <BifElement>[
        BifRect(x: -10, y: -10, width: 20, height: 20, border: true, borderWidth: 2),
      ]);
      // Outer box is (2,2)-(22,22); the stroked path insets by 1 on each side.
      expect(c.rects.single.rect, const Rect.fromLTRB(3, 3, 21, 21));
    });

    test('a smootharc strokes inside its outer radius', () {
      final _Recorder c = paint(const <BifElement>[
        BifSmoothArc(cx: 0, cy: 0, r: 10, strokeWidth: 2),
      ]);
      expect(c.arcs.single.rect, Rect.fromCircle(center: const Offset(12, 12), radius: 9));
    });
  });

  group('triangle geometry', () {
    test('(x, y) is the midpoint of the BASE, not the centroid', () {
      final _Recorder c = paint(const <BifElement>[
        BifTriangle(x: 0, y: 0, size: 6, direction: BifDirection.down),
      ]);

      final Rect bounds = c.paths.single.path.getBounds();
      const double half = 6 * BifTriangle.baseHalfWidthRatio;

      // Base sits ON y (the icon center); the apex is `size` BELOW it.
      expect(bounds.top, closeTo(12, 1e-6), reason: 'base is at y, not straddling it');
      expect(bounds.bottom, closeTo(18, 1e-6), reason: 'apex is size units past the base');
      expect(bounds.left, closeTo(12 - half, 1e-6));
      expect(bounds.right, closeTo(12 + half, 1e-6));
    });

    test('each direction points its apex the right way', () {
      Rect boundsFor(BifDirection d) => paint(<BifElement>[
            BifTriangle(x: 0, y: 0, size: 6, direction: d),
          ]).paths.single.path.getBounds();

      expect(boundsFor(BifDirection.up).top, closeTo(6, 1e-6));
      expect(boundsFor(BifDirection.up).bottom, closeTo(12, 1e-6));
      expect(boundsFor(BifDirection.right).right, closeTo(18, 1e-6));
      expect(boundsFor(BifDirection.left).left, closeTo(6, 1e-6));
    });
  });

  group('smootharc is a QUADRANT, not a half circle', () {
    test('sweeps exactly 90 degrees', () {
      final _Recorder c = paint(const <BifElement>[
        BifSmoothArc(cx: 0, cy: 0, r: 8),
      ]);
      expect(c.arcs.single.sweepAngle, closeTo(math.pi / 2, 1e-9));
    });

    test('each portion starts on the diagonal bounding its quadrant', () {
      double startFor(BifPortion p) => paint(<BifElement>[
            BifSmoothArc(cx: 0, cy: 0, r: 8, portion: p),
          ]).arcs.single.startAngle;

      // 0 deg = right, +90 = down. Quadrants are bounded by the diagonals.
      expect(startFor(BifPortion.right), closeTo(-math.pi / 4, 1e-9));
      expect(startFor(BifPortion.bottom), closeTo(math.pi / 4, 1e-9));
      expect(startFor(BifPortion.left), closeTo(3 * math.pi / 4, 1e-9));
      expect(startFor(BifPortion.top), closeTo(5 * math.pi / 4, 1e-9));
    });
  });

  group('line curves', () {
    test('control points are offsets from the MIDPOINT, not the start', () {
      // A line whose start is deliberately NOT its midpoint: (0,0)..(12,0)
      // is pixels (12,12)..(24,12), so the midpoint is (18,12).
      final _Recorder c = paint(const <BifElement>[
        BifLine(x1: 0, y1: 0, x2: 12, y2: 0, curveX: 0, curveY: -6),
      ]);

      expect(c.paths, hasLength(1), reason: 'one true Bezier, not hundreds of stamped dots');

      // Control at midpoint + (0,-6) = (18, 6) puts the curve's own midpoint at
      // x = 18. Measuring the offset from the START would place the control at
      // (12, 6) and drag the curve's midpoint to x = 15 — a different shape.
      final Offset mid = midpointOf(c.paths.single.path);
      expect(mid.dx, closeTo(18, 0.2), reason: 'control point is midpoint-relative');
      expect(mid.dy, closeTo(9, 0.2), reason: 'a quadratic reaches halfway to its control point');
    });

    test('one control point yields a quadratic, both yield a cubic', () {
      const BifLine quad = BifLine(x1: -6, y1: 0, x2: 6, y2: 0, curveX: 0, curveY: -6);
      const BifLine cubic = BifLine(x1: -6, y1: 0, x2: 6, y2: 0, curveX: 0, curveY: -6, curve2X: 0, curve2Y: -6);

      expect(quad.isCurved, isTrue);
      expect(quad.isCubic, isFalse);
      expect(cubic.isCubic, isTrue);

      // Same handle offset, but a cubic has two of them tugging, so it climbs
      // higher: quadratic reaches y=9, cubic y=7.5 (smaller y is higher).
      final double quadTop = midpointOf(paint(const <BifElement>[quad]).paths.single.path).dy;
      final double cubicTop = midpointOf(paint(const <BifElement>[cubic]).paths.single.path).dy;
      expect(quadTop, closeTo(9, 0.2));
      expect(cubicTop, closeTo(7.5, 0.2));
      expect(cubicTop, lessThan(quadTop));
    });

    test('an all-zero control pair is not a curve', () {
      const BifLine line = BifLine(x1: -6, y1: 0, x2: 6, y2: 0, curveX: 0, curveY: 0);
      expect(line.isCurved, isFalse);
      expect(paint(const <BifElement>[line]).lines, hasLength(1));
    });

    test('strokes use round caps, like the RN original', () {
      final _Recorder c = paint(const <BifElement>[BifLine(x1: -6, y1: 0, x2: 6, y2: 0)]);
      expect(c.lines.single.paint.strokeCap, StrokeCap.round);
    });
  });

  group('color resolution', () {
    test("'color' and 'bg' resolve to the icon palette", () {
      final _Recorder c = paint(const <BifElement>[
        BifCircle(cx: 0, cy: 0, r: 4, fill: BifPaint.theme),
        BifCircle(cx: 0, cy: 0, r: 2, fill: BifPaint.background),
      ]);
      // Compare packed ARGB: Color equality is float-component based, and a
      // color round-tripped through Paint differs in the low bits.
      expect(c.circles[0].paint.color.toARGB32(), theme.toARGB32());
      expect(c.circles[1].paint.color.toARGB32(), bg.toARGB32());
    });

    test('an override replaces the theme color without touching literals', () {
      const Color override = Color(0xFFFF0000);
      final _Recorder canvas = _Recorder();
      BuoyIconPainter(
        const BuoyIconData(
          color: theme,
          bgColor: bg,
          elements: <BifElement>[
            BifCircle(cx: 0, cy: 0, r: 4, fill: BifPaint.theme),
            BifCircle(cx: 0, cy: 0, r: 2, fill: BifPaint(BifPaintSource.literal, literal: Color(0xFF123456))),
          ],
        ),
        colorOverride: override,
      ).paint(canvas, const Size.square(24));

      expect(canvas.circles[0].paint.color.toARGB32(), override.toARGB32());
      expect(canvas.circles[1].paint.color.toARGB32(), const Color(0xFF123456).toARGB32(),
          reason: 'literals are baked in');
    });

    test("the ':NN' opacity suffix and the element opacity multiply", () {
      final _Recorder c = paint(const <BifElement>[
        // 'color:50' at element opacity 0.5 => 25% alpha overall.
        BifCircle(cx: 0, cy: 0, r: 4, fill: BifPaint(BifPaintSource.theme, opacity: 0.5), opacity: 0.5),
      ]);
      expect(c.circles.single.paint.color.a, closeTo(0.25, 1e-6));
    });
  });

  group('painting order and repaint', () {
    test('elements paint back-to-front in list order', () {
      final _Recorder c = paint(const <BifElement>[
        BifCircle(cx: 0, cy: 0, r: 9, fill: BifPaint.background),
        BifCircle(cx: 0, cy: 0, r: 3, fill: BifPaint.theme),
      ]);
      expect(c.circles.map((_C c) => c.radius), <double>[9, 3]);
    });

    test('repaints only when the icon or its color overrides change', () {
      const BuoyIconData a = BuoyIconData(color: theme, bgColor: bg, elements: <BifElement>[
        BifCircle(cx: 0, cy: 0, r: 4, fill: BifPaint.theme),
      ]);
      const BuoyIconPainter base = BuoyIconPainter(a);

      expect(base.shouldRepaint(const BuoyIconPainter(a)), isFalse);
      expect(base.shouldRepaint(const BuoyIconPainter(a, colorOverride: Color(0xFFFF0000))), isTrue);
    });
  });

  group('generated icons', () {
    test('ship the same artwork as React Native', () {
      // Sanity that codegen ran and the brand colors survived the port.
      expect(buoyIconsByName, isNotEmpty);
      expect(networkIconData.color, const Color(0xFF00D4FF));
      expect(kBenchmarkIconColor, const Color(0xFFF59E0B));
      expect(buoyIconsByName['network'], same(networkIconData));
    });

    test('every generated icon paints without throwing, at every size', () {
      final Map<String, BuoyIconData> all = <String, BuoyIconData>{
        for (final MapEntry<String, BuoyIconData> e in buoyIconsByName.entries) 'icon:${e.key}': e.value,
        for (final MapEntry<String, BuoyIconData> e in buoyGlyphsByName.entries) 'glyph:${e.key}': e.value,
      };

      for (final MapEntry<String, BuoyIconData> entry in all.entries) {
        for (final double size in <double>[16, 24, 32, 96]) {
          final _Recorder canvas = _Recorder();
          expect(
            () => BuoyIconPainter(entry.value).paint(canvas, Size.square(size)),
            returnsNormally,
            reason: '${entry.key} @ ${size}px',
          );
          expect(canvas.drawCalls, greaterThan(0), reason: '${entry.key} drew nothing');
        }
      }
    });

    test('the scratch curve-test icons are excluded from the Dart build', () {
      // They carry "targets": ["ts"] — RN authoring scratch, not real icons.
      expect(buoyIconsByName.keys.where((String k) => k.startsWith('curve-test')), isEmpty);
    });

    test('the glyph tier is complete and separate from the brand tier', () {
      // Every BuoyIcons entry must resolve, or a widget renders a blank box.
      expect(buoyGlyphsByName.length, greaterThanOrEqualTo(44));
      expect(BuoyIcons.filter, same(buoyGlyphsByName['filter']));
      expect(BuoyIcons.chevronDown, same(buoyGlyphsByName['chevron-down']));

      // `wifi` exists in BOTH tiers as two different drawings — the tiers are
      // separate maps precisely so one cannot shadow the other.
      expect(buoyIconsByName.containsKey('wifi'), isTrue);
      expect(buoyGlyphsByName.containsKey('wifi'), isTrue);
      expect(identical(buoyIconsByName['wifi'], buoyGlyphsByName['wifi']), isFalse);
    });

    test('glyphs are uniform-stroke and honor the stroke-width override', () {
      // Authored at 2; lucide callers pass 2.5 or 3 and expect a REPLACEMENT.
      final _Recorder plain = _Recorder();
      BuoyIconPainter(BuoyIcons.check).paint(plain, const Size.square(24));
      expect(plain.lines.every((_L l) => l.paint.strokeWidth == 2.0), isTrue);

      final _Recorder heavy = _Recorder();
      BuoyIconPainter(BuoyIcons.check, strokeWidthOverride: 3)
          .paint(heavy, const Size.square(24));
      expect(heavy.lines.every((_L l) => l.paint.strokeWidth == 3.0), isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// A Canvas that records what it was asked to draw.
// ---------------------------------------------------------------------------

class _C {
  _C(this.center, this.radius, this.paint);
  final Offset center;
  final double radius;
  final Paint paint;
}

class _R {
  _R(this.rect, this.paint);
  final Rect rect;
  final Paint paint;
}

class _A {
  _A(this.rect, this.startAngle, this.sweepAngle, this.paint);
  final Rect rect;
  final double startAngle;
  final double sweepAngle;
  final Paint paint;
}

class _P {
  _P(this.path, this.paint);
  final Path path;
  final Paint paint;
}

class _L {
  _L(this.p1, this.p2, this.paint);
  final Offset p1;
  final Offset p2;
  final Paint paint;
}

class _Recorder implements Canvas {
  final List<_C> circles = <_C>[];
  final List<_R> rects = <_R>[];
  final List<_A> arcs = <_A>[];
  final List<_P> paths = <_P>[];
  final List<_L> lines = <_L>[];

  int get drawCalls => circles.length + rects.length + arcs.length + paths.length + lines.length;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(_C(c, radius, paint));

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(_R(rect, paint));

  @override
  void drawRRect(RRect rrect, Paint paint) => rects.add(_R(rrect.outerRect, paint));

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) =>
      arcs.add(_A(rect, startAngle, sweepAngle, paint));

  @override
  void drawPath(Path path, Paint paint) => paths.add(_P(path, paint));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add(_L(p1, p2, paint));

  // Transform/state calls are no-ops here; the assertions above are written
  // against elements that don't depend on canvas transform state.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

}
