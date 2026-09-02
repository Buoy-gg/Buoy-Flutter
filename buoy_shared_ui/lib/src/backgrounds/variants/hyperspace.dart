/// Ports packages/shared/src/ui/backgrounds/variants/hyperspace.tsx — the
/// Everlights `HyperspaceBackground`, the Star Wars "lightspeed" field: crisp
/// ROUND points streaming out of a centre vanishing point on the 3D depth
/// projection `screen = plane / z`.
///
/// THE FIELD IS EXACT: one mulberry32 stream seeded `0x5747 ^ 260`, pulling
/// `ang, rad, z0, tw` per star in the original's call order — same 260
/// stars, same sqrt-biased radii with the 12% clear centre, same palette pick
/// formula, same z sweep (1.0 → 0.06), same speed (0.55 z-units/sec), same
/// `0.15 + 0.85·near²` brightness with a 6% fade at both ends of a star's
/// life. Stars are round dots, NOT streaks.
///
/// Where this is CLOSER to the original than RN: RN had to quantise each
/// star's start phase `z0` into 8 "shells" (one animated node per shell, 260
/// per-star nodes being too many). A painter costs the same per star, so
/// `z0` stays continuous here — no shell wrap to hide.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../painting.dart';
import '../rng.dart';

const Color _baseColor = Color(0xFF050505);

// The original's constants, verbatim (variant 1, "lightspeed").
const int _count = 260;
const double _speed = 0.55; // z-units/sec → one life = 1/0.55 s
const double _baseDia = 3.6; // sprite diameter px at z=1
const double _plane = 0.5;
const double _zFar = 1.0;
const double _zNear = 0.06;
const double _zSpan = _zFar - _zNear;
/// The lit core of the 64px sprite is r=4 → 12.5% of the stamp.
const double _coreFrac = 0.125;
const double _cycleS = 1 / _speed;

const List<Color> _palette = [Color(0xFFFFFFFF), Color(0xFFB3D9FF), Color(0xFF8CB3FF)];

class _Star {
  const _Star(this.px, this.py, this.z0, this.color);

  /// Plane offsets — screen position is centre + (p/z)·centre.
  final double px;
  final double py;
  final double z0;
  final Color color;
}

/// The original field, regenerated — ONE rng stream, original call order
/// (ang, rad, z0, tw per star), original seed. Any other order or seed is a
/// different sky.
List<_Star> _buildField() {
  final rnd = mulberry32(0x5747 ^ _count);
  final stars = <_Star>[];
  for (var i = 0; i < _count; i++) {
    final ang = rnd() * math.pi * 2;
    // sqrt-biased outward, inner 12% clear of the vanishing point.
    final rad = (0.12 + 0.88 * math.sqrt(rnd())) * _plane;
    final z0 = rnd();
    final tw = rnd() * math.pi * 2;
    stars.add(_Star(
      math.cos(ang) * rad,
      math.sin(ang) * rad,
      z0,
      // The original's exact (quirky) pick: floor((tw·0.5 + 0.5)·n) % n.
      _palette[((tw * 0.5 + 0.5) * _palette.length).floor() % _palette.length],
    ));
  }
  return stars;
}

final List<_Star> _field = _buildField();

/// S(p) = 1/z with z falling linearly over the phase — the projection.
double _scaleAt(double p) => 1 / (_zFar - p * _zSpan);

/// The original's brightness: 0.15 + 0.85·near², faded over the first and
/// last 6% of a star's life.
double _opacityAt(double p) {
  var bright = 0.15 + 0.85 * p * p;
  if (p < 0.06) {
    bright *= p / 0.06;
  } else if (p > 0.94) {
    bright *= (1 - p) / 0.06;
  }
  return math.min(1, bright);
}

class Hyperspace extends StatelessWidget {
  const Hyperspace({
    super.key,
    required this.width,
    required this.height,
    required this.animated,
  });

  final double width;
  final double height;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    return BackgroundCanvas(
      animated: animated,
      painter: (clock) => _HyperspacePainter(clock),
    );
  }
}

class _HyperspacePainter extends CustomPainter {
  _HyperspacePainter(this.clock) : super(repaint: clock);

  final ValueListenable<double> clock;
  final Paint _dot = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    drawBase(canvas, size, _baseColor);

    final t = loopPhase(clock.value, _cycleS);
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Core at the sprite's lit 12.5% (0.45px at z=1) with a floor so the far
    // stars land on a pixel; halo disc at the sprite's α0.30, 2.4× the core.
    final core = math.max(0.5, _baseDia * _coreFrac);
    final halo = core * 2.4;

    for (final star in _field) {
      final p = (t + star.z0) % 1.0;
      final opacity = _opacityAt(p);
      if (opacity <= 0.002) continue;
      final s = _scaleAt(p);
      // The original's projection: sx = cx + px·cx, sy = cy + py·cy (offsets
      // scale with the HALF-extent — elliptical, exactly as there), and the
      // whole layer scales by S about the centre.
      final x = cx + star.px * cx * s;
      final y = cy + star.py * cy * s;
      if (x < -halo || y < -halo || x > size.width + halo || y > size.height + halo) {
        continue;
      }
      _dot.color = withAlpha(star.color, 0.3 * opacity);
      canvas.drawCircle(Offset(x, y), halo * s / 2, _dot);
      _dot.color = withAlpha(star.color, opacity);
      canvas.drawCircle(Offset(x, y), core * s / 2, _dot);
    }

    drawVignette(canvas, size, alpha: 0.3, spread: 0.3);
  }

  @override
  bool shouldRepaint(_HyperspacePainter oldDelegate) => oldDelegate.clock != clock;
}
