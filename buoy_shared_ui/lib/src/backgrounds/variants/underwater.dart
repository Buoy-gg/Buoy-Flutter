/// Ports packages/shared/src/ui/backgrounds/variants/underwater.tsx — the
/// underwater family: Abyss (a surface light fanning into the deep), Bubbles
/// (rising through the light) and Jellyfish (a bloom of glowing bells pulsing
/// past on the current).
///
/// Same scene contract as RN: lit from the surface, near-black at the bottom,
/// everything moving in tens of seconds; scatter tables from fixed seeds;
/// vertical travel tiles (everything drawn twice, one height apart,
/// translated a full height per loop so the seam never shows); geometry
/// sized from the WINDOW, not the modal, so resizing the modal reveals more
/// or less water rather than stretching the light.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../painting.dart';
import '../rng.dart';

// ============================================================================
// Shared water
// ============================================================================

class _Ray {
  const _Ray(this.at, this.tilt, this.size, this.alpha);
  final double at;
  final double tilt; // degrees
  final double size; // fraction of window width
  final double alpha;
}

/// God rays: elongated squashed radial glows hanging from above the surface.
/// The shimmer is one opacity over the whole fan (pulse 9s, 0.6 → 1).
void _drawRays(Canvas canvas, Size size, Size window, List<_Ray> rays, double t) {
  final shimmer = interpolate(pulsePhase(t, 9), [0, 1], [0.6, 1]);
  for (final ray in rays) {
    final d = window.width * ray.size;
    final cx = size.width * ray.at;
    final cy = -d * 0.35 + d / 2;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(ray.tilt * math.pi / 180);
    canvas.scale(0.2, 1.15);
    drawRadialGlow(canvas,
        centre: Offset.zero,
        size: d,
        color: const Color(0xFF2C6373),
        alpha: ray.alpha * shimmer,
        rings: 7,
        falloff: 1.6);
    canvas.restore();
  }
}

typedef _ParticlePainter = void Function(Canvas canvas, Offset at, double size);

/// A band of particles travelling a full surface-height per loop — "down" is
/// marine snow, "up" is anything buoyant. `sway` (px) adds a whole-layer
/// side-to-side wobble keyframed onto the same clock.
void _drawDriftBand(
  Canvas canvas,
  Size size, {
  required List<double> table,
  required int count,
  required double travelS,
  required bool down,
  double sway = 0,
  required double t,
  required _ParticlePainter render,
}) {
  final h = size.height;
  final p = loopPhase(t, travelS);
  final ty = down ? p * h : -p * h;
  final tx = interpolate(p, [0, 0.25, 0.5, 0.75, 1], [0, sway, 0, -sway, 0]);
  final top = down ? -h : 0.0;
  canvas.save();
  canvas.translate(tx, top + ty);
  for (var i = 0; i < count; i++) {
    final x = table[i * 3] * size.width;
    final y = table[i * 3 + 1] * h;
    final s = table[i * 3 + 2];
    render(canvas, Offset(x, y), s);
    render(canvas, Offset(x, y + h), s);
  }
  canvas.restore();
}

/// The shared floor: base coat + surface light, then the scene, then the
/// vignette. Everything clips to the surface.
void _drawWater(
  Canvas canvas,
  Size size, {
  required Color base,
  required Color wash,
  required double washAlpha,
  double vignette = 0.5,
  required void Function() scene,
}) {
  canvas.clipRect(Offset.zero & size);
  drawBase(canvas, size, base);
  drawLinearFade(canvas, Rect.fromLTWH(0, 0, size.width, size.height * 0.55),
      color: wash, from: washAlpha, to: 0, flattenBase: base);
  scene();
  drawVignette(canvas, size,
      color: const Color(0xFF010304), alpha: vignette, spread: 0.36);
}

Size _window(BuildContext context) => MediaQuery.sizeOf(context);

// ============================================================================
// Abyss — a surface light fanning into the deep
// ============================================================================

const Color _abyssBase = Color(0xFF04080F);

/// Beams: [angle° (90 = straight down), squash, alpha, colour] — brightest
/// near vertical, dimming toward the fan's edges. Each is the Lighthouse
/// construction: a squashed glow in the right half of an end-pivot box.
const List<(double, double, double, Color)> _abyssBeams = [
  (46, 0.05, 0.08, Color(0xFF35598F)),
  (64, 0.07, 0.12, Color(0xFF466FA8)),
  (81, 0.09, 0.16, Color(0xFF5580BE)),
  (97, 0.08, 0.15, Color(0xFF5580BE)),
  (114, 0.06, 0.11, Color(0xFF466FA8)),
  (133, 0.05, 0.07, Color(0xFF35598F)),
];

void _drawRayFan(Canvas canvas, Size size, Size window, double t) {
  final shimmer = interpolate(pulsePhase(t, 9), [0, 1], [0.65, 1]);
  final reach = window.height * 0.62;
  final bloom = math.min(math.min(window.width, window.height) * 0.42, 360.0);
  final sx = size.width * 0.5;
  const sy = -10.0;
  for (final (deg, squash, alpha, color) in _abyssBeams) {
    canvas.save();
    canvas.translate(sx, sy);
    canvas.rotate(deg * math.pi / 180);
    // Right half of the pivot box: the glow's centre sits `reach/2` along
    // the beam, squashed across it.
    canvas.translate(reach / 2, 0);
    canvas.scale(1, squash);
    drawRadialGlow(canvas,
        centre: Offset.zero, size: reach, color: color, alpha: alpha * shimmer, rings: 8, falloff: 1.5);
    canvas.restore();
  }
  // The source: a modest surface bloom and a hot core, half off-screen.
  drawRadialGlow(canvas,
      centre: Offset(sx, sy), size: bloom, color: const Color(0xFFBFD9F5), alpha: 0.16 * shimmer, rings: 24, falloff: 1.9);
  drawRadialGlow(canvas,
      centre: Offset(sx, sy), size: 72, color: const Color(0xFFE8F2FC), alpha: 0.3 * shimmer, rings: 12, falloff: 1.5);
}

/// Stride 3: x, y, size-draw. Nearer bands are sparser and faster.
const List<({int count, double travelS, int seed})> _snowBands = [
  (count: 22, travelS: 30, seed: 0x61f3),
  (count: 14, travelS: 21, seed: 0x8d2b),
  (count: 8, travelS: 14, seed: 0xc55d),
];
final List<List<double>> _snowTables =
    _snowBands.map((b) => scatter(b.seed, b.count * 3)).toList(growable: false);

_ParticlePainter _snowFlake(double dia, double alpha, [Color color = const Color(0xFFA8D8E0)]) {
  final paint = Paint()..color = withAlpha(color, alpha);
  return (canvas, at, _) => canvas.drawCircle(at, dia / 2, paint);
}

/// The original marine snow: plain dots, nearer bands bigger and brighter.
final List<_ParticlePainter> _abyssRenders = [
  _snowFlake(1.3, 0.26),
  _snowFlake(1.9, 0.38),
  _snowFlake(2.6, 0.5),
];

class Abyss extends StatelessWidget {
  const Abyss({super.key, required this.width, required this.height, required this.animated});
  final double width;
  final double height;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final window = _window(context);
    return BackgroundCanvas(
      animated: animated,
      painter: (clock) => _ScenePainter(clock, (canvas, size, t) {
        _drawWater(canvas, size,
            base: _abyssBase,
            wash: const Color(0xFF12264A),
            washAlpha: 0.55,
            scene: () {
              _drawRayFan(canvas, size, window, t);
              for (var i = 0; i < _snowBands.length; i++) {
                _drawDriftBand(canvas, size,
                    table: _snowTables[i],
                    count: _snowBands[i].count,
                    travelS: _snowBands[i].travelS,
                    down: true,
                    t: t,
                    render: _abyssRenders[i]);
              }
            });
      }),
    );
  }
}

// ============================================================================
// Bubbles — rising through the light
// ============================================================================

const List<_Ray> _bubbleRays = [_Ray(0.3, -10, 0.95, 0.2), _Ray(0.68, 6, 0.8, 0.16)];

const List<({int count, double dia, double alpha, double travelS, double sway, int seed})>
    _bubbleBands = [
  (count: 14, dia: 3, alpha: 0.3, travelS: 26, sway: 4, seed: 0x71a9),
  (count: 10, dia: 5, alpha: 0.42, travelS: 18, sway: -6, seed: 0x93cd),
  (count: 7, dia: 8, alpha: 0.54, travelS: 12, sway: 8, seed: 0xb5ef),
];
final List<List<double>> _bubbleTables =
    _bubbleBands.map((b) => scatter(b.seed, b.count * 3)).toList(growable: false);

/// A bubble is a RING with an off-centre highlight — the highlight is the
/// entire difference between "dot" and "bubble".
_ParticlePainter _bubble(double dia, double alpha) {
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = withAlpha(const Color(0xFF9FE5F2), alpha);
  final hi = Paint()..color = withAlpha(const Color(0xFFD8F5FB), alpha + 0.18);
  return (canvas, at, size) {
    final d = dia * (0.7 + size * 0.6);
    final h = math.max(1.2, d * 0.22);
    final tl = at - Offset(d / 2, d / 2);
    canvas.drawCircle(at, d / 2, ring);
    canvas.drawCircle(tl + Offset(d * 0.24 + h / 2, d * 0.18 + h / 2), h / 2, hi);
  };
}

class Bubbles extends StatelessWidget {
  const Bubbles({super.key, required this.width, required this.height, required this.animated});
  final double width;
  final double height;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final window = _window(context);
    return BackgroundCanvas(
      animated: animated,
      painter: (clock) => _ScenePainter(clock, (canvas, size, t) {
        _drawWater(canvas, size,
            base: const Color(0xFF030608),
            wash: const Color(0xFF102833),
            washAlpha: 0.5,
            scene: () {
              _drawRays(canvas, size, window, _bubbleRays, t);
              for (var i = 0; i < _bubbleBands.length; i++) {
                final b = _bubbleBands[i];
                _drawDriftBand(canvas, size,
                    table: _bubbleTables[i],
                    count: b.count,
                    travelS: b.travelS,
                    down: false,
                    sway: b.sway,
                    t: t,
                    render: _bubble(b.dia, b.alpha));
              }
            });
      }),
    );
  }
}

// ============================================================================
// Jellyfish — pulsing past on the current
// ============================================================================

const List<_Ray> _jellyRays = [_Ray(0.25, -12, 0.9, 0.18), _Ray(0.62, 5, 0.85, 0.15)];

class _JellySpec {
  const _JellySpec(this.x, this.w, this.travelS, this.pulseS, this.pulses, this.sway, this.dim, this.phase);
  final double x, w, travelS, pulseS, sway, phase;
  final bool pulses, dim;
}

/// `phase` staggers where each jelly is in its climb at mount, so the water
/// is never empty while they all wait at the bottom. Mount order is paint
/// order: small dim jellies first — they read as distance (slower, no pulse)
/// and the big ones drift over them.
const List<_JellySpec> _jellies = [
  _JellySpec(0.5, 18, 60, 3.0, false, 8, true, 0.78),
  _JellySpec(0.78, 16, 64, 3.0, false, 7, true, 0.62),
  _JellySpec(0.2, 14, 70, 3.0, false, -6, true, 0.3),
  _JellySpec(0.12, 54, 40, 3.0, true, -18, false, 0.85),
  _JellySpec(0.28, 46, 34, 2.6, true, 16, false, 0.55),
  _JellySpec(0.45, 40, 38, 3.15, true, 14, false, 0.35),
  _JellySpec(0.68, 36, 46, 3.4, true, -12, false, 0.2),
  _JellySpec(0.88, 28, 52, 2.85, true, 10, false, 0.05),
];

/// Tentacles as fractions of the bell width: [dx, length, thick, tilt°].
const List<(double, double, double, double)> _tentacles = [
  (-0.32, 1.1, 1, -5),
  (-0.1, 1.35, 1, -2),
  (0.14, 1.2, 1, 3),
  (0.34, 0.95, 1, 6),
  (-0.22, 0.6, 1.5, -3),
  (0.24, 0.55, 1.5, 4),
];

void _drawJelly(Canvas canvas, Size size, _JellySpec j, double t) {
  final rise = loopPhase(t, j.travelS);
  final squish = j.pulses ? pulsePhase(t, j.pulseS) : 0.0;
  final w = j.w;
  final bellH = w * 0.78;
  final jellyH = w * 2.2;
  final travel = size.height + jellyH * 1.5;
  // Piecewise phase offset: same climb speed on both segments, with the
  // (invisible) top→bottom teleport at t = 1 - phase.
  final wrap = 1 - j.phase;
  final ty = interpolate(rise, [0, wrap, math.min(wrap + 0.0001, 0.9999), 1],
      [-travel * j.phase, -travel, 0, -travel * j.phase]);
  final tx = interpolate(rise, [0, 0.2, 0.45, 0.7, 1], [0, j.sway, -j.sway * 0.6, j.sway * 0.8, 0]);
  final scaleX = 1 + 0.07 * squish;
  final scaleY = 1 - 0.1 * squish;
  final stroke = j.dim ? 0.16 : 0.3;

  canvas.save();
  // Starts just below the surface's bottom edge and exits above the top, so
  // the loop's snap back happens entirely off-screen. Box is w*2 wide.
  canvas.translate(size.width * j.x - w + tx, size.height + ty);

  // Bioluminescent aura, then the pulsing bell over it.
  drawRadialGlow(canvas,
      centre: Offset(w, bellH / 2), size: w * 1.8, color: const Color(0xFF7DEBF7), alpha: j.dim ? 0.08 : 0.14, rings: 6, falloff: 1.8);

  canvas.save();
  // Bell box: left w/2, top 0, size w × bellH, scaled about its centre.
  canvas.translate(w / 2 + w / 2, bellH / 2);
  canvas.scale(scaleX, scaleY);
  canvas.translate(-w / 2, -bellH / 2);
  final bell = RRect.fromRectAndCorners(
    Rect.fromLTWH(0, 0, w, bellH),
    topLeft: Radius.circular(w / 2),
    topRight: Radius.circular(w / 2),
    bottomLeft: Radius.circular(w * 0.18),
    bottomRight: Radius.circular(w * 0.18),
  );
  canvas.drawRRect(bell, Paint()..color = withAlpha(const Color(0xFF67E8F9), 0.09));
  canvas.save();
  canvas.clipRRect(bell);
  // Inner glow: a soft fill lighting the whole bell from inside, and (on the
  // bright jellies) a small hot core near the dome's crown — the lantern
  // look. Both live INSIDE the clipped bell so the glow reads as internal.
  drawRadialGlow(canvas,
      centre: Offset(w * 0.05 + w * 0.45, -w * 0.12 + w * 0.45), size: w * 0.9, color: const Color(0xFF7DEBF7), alpha: j.dim ? 0.2 : 0.38, rings: 6, falloff: 1.6);
  if (!j.dim) {
    drawRadialGlow(canvas,
        centre: Offset(w * 0.25 + w * 0.25, w * 0.06 + w * 0.25), size: w * 0.5, color: const Color(0xFFD9FBFF), alpha: 0.28, rings: 5, falloff: 1.4);
  }
  canvas.restore();
  canvas.drawRRect(
      bell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = withAlpha(const Color(0xFF8FE9F7), stroke));
  canvas.restore();

  final tentacle = Paint()
    ..strokeCap = StrokeCap.round
    ..color = withAlpha(const Color(0xFF8FE9F7), j.dim ? 0.12 : 0.2);
  for (final (dx, len, thick, tilt) in _tentacles) {
    canvas.save();
    canvas.translate(w + dx * w + thick / 2, bellH - 2);
    canvas.rotate(tilt * math.pi / 180);
    tentacle.strokeWidth = thick;
    canvas.drawLine(Offset.zero, Offset(0, w * len), tentacle);
    canvas.restore();
  }
  canvas.restore();
}

final List<double> _jellySnow = scatter(0xd7a3, 14 * 3);

class Jellyfish extends StatelessWidget {
  const Jellyfish({super.key, required this.width, required this.height, required this.animated});
  final double width;
  final double height;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final window = _window(context);
    final snow = _snowFlake(1.4, 0.3);
    return BackgroundCanvas(
      animated: animated,
      painter: (clock) => _ScenePainter(clock, (canvas, size, t) {
        _drawWater(canvas, size,
            base: const Color(0xFF030608),
            wash: const Color(0xFF102833),
            washAlpha: 0.5,
            scene: () {
              _drawRays(canvas, size, window, _jellyRays, t);
              _drawDriftBand(canvas, size,
                  table: _jellySnow, count: 14, travelS: 32, down: true, t: t, render: snow);
              for (final j in _jellies) {
                _drawJelly(canvas, size, j, t);
              }
            });
      }),
    );
  }
}

// ============================================================================

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.clock, this.draw) : super(repaint: clock);
  final ValueListenable<double> clock;
  final void Function(Canvas canvas, Size size, double t) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size, clock.value);

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => oldDelegate.clock != clock;
}
