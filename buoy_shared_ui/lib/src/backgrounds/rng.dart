/// Ports packages/shared/src/ui/backgrounds/rng.ts — deterministic scatter
/// tables for the tool backgrounds. Every preset needs a pile of "random"
/// positions, sizes and phases; they are generated ONCE from a fixed seed so
/// the same seed always paints the same field (screenshots are stable, and
/// two tools showing the same background look identical).
///
/// `mulberry32` is BIT-EXACT with the JS: the JS runs on int32 (`| 0`,
/// `Math.imul`, `>>> 0`); Dart ints are 64-bit, so every step masks back to
/// the low 32 bits. Any drift here is a different sky — `rng_test.dart` pins
/// the first outputs for three seeds against values captured from node.
library;

import 'dart:ui' show Color;

const int _mask32 = 0xFFFFFFFF;

/// JS `Math.imul`: the low 32 bits of the product. Dart wraps the 64-bit
/// product on overflow, which preserves exactly those bits.
int _imul(int a, int b) => ((a & _mask32) * (b & _mask32)) & _mask32;

/// Returns a generator of doubles in [0, 1) from `seed` (JS `mulberry32`).
double Function() mulberry32(int seed) {
  var s = seed & _mask32;
  return () {
    s = (s + 0x6d2b79f5) & _mask32;
    var t = _imul(s ^ (s >> 15), 1 | s);
    t = ((t + _imul(t ^ (t >> 7), 61 | t)) & _mask32) ^ t;
    return ((t ^ (t >> 14)) & _mask32) / 4294967296;
  };
}

/// `count` numbers in [0,1) from `seed`.
List<double> scatter(int seed, int count) {
  final rnd = mulberry32(seed);
  return List<double>.generate(count, (_) => rnd(), growable: false);
}

/// RN `withAlpha(hex, alpha)`: the colour at `alpha` 0..1.
Color withAlpha(Color color, double alpha) =>
    color.withValues(alpha: alpha.clamp(0.0, 1.0));

/// RN `lerpColor`: RGB lerp between two opaque colours.
Color lerpColor(Color a, Color b, double t) => Color.lerp(a, b, t.clamp(0.0, 1.0))!;

/// RN `flattenOver`: `color` at `alpha` composited over an opaque `base`,
/// returned OPAQUE — pixel-identical to drawing the translucent colour where
/// nothing else sits between the layer and `base`, and cheaper to composite.
Color flattenOver(Color color, double alpha, Color base) {
  final a = alpha.clamp(0.0, 1.0);
  int mix(double c, double bc) => (c * 255 * a + bc * 255 * (1 - a)).round();
  return Color.fromARGB(255, mix(color.r, base.r), mix(color.g, base.g), mix(color.b, base.b));
}
