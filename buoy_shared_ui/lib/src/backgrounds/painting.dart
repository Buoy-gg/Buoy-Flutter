/// Ports the drawing + animation primitives of
/// packages/shared/src/ui/backgrounds/primitives.tsx onto a `CustomPainter`.
///
/// RN has to FAKE every gradient out of stacked translucent `View`s (a
/// devtool may not force Skia or SVG into someone's app) and run each layer
/// on its own native-driven `Animated` loop. Flutter draws real gradients and
/// repaints one canvas per frame, so the whole subsystem collapses to:
///
///  - [BackgroundCanvas]: ONE ticker per preset, exposing elapsed seconds
///    through a `ValueNotifier` the painter listens to. Every "loop" and
///    "pulse" in a scene is derived from that clock ([loopPhase],
///    [pulsePhase]) with its own period — no per-layer controllers. The
///    ticker stops while the app is backgrounded (a decorative loop is pure
///    battery burn) and never starts when `animated` is false.
///  - [drawRadialGlow] / [drawLinearFade] / [drawVignette]: the ring / strip
///    stacks as true gradients, with the SAME alpha profile RN's ring count
///    and falloff produce (stops are computed from the ring formula), so the
///    look is preserved without the banding.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import 'rng.dart';

// ============================================================================
// The clock
// ============================================================================

/// RN `useLoop(durationMs)`: a 0→1 sawtooth with the given period.
double loopPhase(double seconds, double periodSeconds) =>
    periodSeconds <= 0 ? 0 : (seconds / periodSeconds) % 1.0;

/// RN `usePulse(durationMs)`: a 0→1→0 breathe, each half eased
/// `Easing.inOut(Easing.quad)`.
double pulsePhase(double seconds, double periodSeconds) {
  final p = loopPhase(seconds, periodSeconds);
  final x = p < 0.5 ? p * 2 : 2 - p * 2;
  return x < 0.5 ? 2 * x * x : 1 - math.pow(-2 * x + 2, 2) / 2;
}

/// Multi-stop linear interpolation (RN `Animated.interpolate` with
/// `inputRange` / `outputRange`, clamped at both ends).
double interpolate(double v, List<double> input, List<double> output) {
  if (v <= input.first) return output.first;
  if (v >= input.last) return output.last;
  for (var i = 1; i < input.length; i++) {
    if (v <= input[i]) {
      final span = input[i] - input[i - 1];
      final t = span == 0 ? 0.0 : (v - input[i - 1]) / span;
      return output[i - 1] + (output[i] - output[i - 1]) * t;
    }
  }
  return output.last;
}

/// One preset's surface: a ticker-driven [CustomPaint]. `painter` receives
/// the clock (elapsed seconds) as a listenable and must pass it as its
/// `repaint`. With `animated: false` the clock never advances.
class BackgroundCanvas extends StatefulWidget {
  const BackgroundCanvas({
    super.key,
    required this.animated,
    required this.painter,
  });

  final bool animated;
  final CustomPainter Function(ValueListenable<double> clock) painter;

  @override
  State<BackgroundCanvas> createState() => _BackgroundCanvasState();
}

class _BackgroundCanvasState extends State<BackgroundCanvas>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ValueNotifier<double> _clock = ValueNotifier(0);
  late final Ticker _ticker = createTicker((elapsed) {
    _clock.value = elapsed.inMicroseconds / 1e6;
  });
  late final CustomPainter _painter = widget.painter(_clock);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(BackgroundCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated != widget.animated) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // RN: AppState "active" restarts the loops, anything else stops them.
    _sync(foreground: state == AppLifecycleState.resumed);
  }

  bool _foreground = true;

  void _sync({bool? foreground}) {
    if (foreground != null) _foreground = foreground;
    final run = widget.animated && _foreground;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _painter, size: Size.infinite),
    );
  }
}

// ============================================================================
// Gradients (RN RadialGlow / LinearFade / Vignette / Base)
// ============================================================================

/// RN `RadialGlow`: a soft disc of `size` centred at `centre`, peak (centre)
/// `alpha`, `falloff` > 1 concentrating the light in the middle. RN stacks
/// `rings` concentric discs of equal per-ring alpha with radii on the
/// falloff curve; the gradient stops here reproduce that exact cumulative
/// alpha at each ring edge, then fade to 0 at the rim (RN's outermost ring
/// ends in a hard edge at ~5% alpha — invisible on a dark surface).
void drawRadialGlow(
  Canvas canvas, {
  required Offset centre,
  required double size,
  required Color color,
  double alpha = 0.35,
  int rings = 8,
  double falloff = 1.7,
  Paint? paint,
}) {
  if (size <= 0) return;
  final per = 1 - math.pow(1 - alpha, 1 / rings);
  final stops = <double>[];
  final colors = <Color>[];
  // Ring k (0 = outermost) has radius fraction ((rings-k)/rings)^falloff and
  // a point inside it is covered by k+1 rings.
  for (var k = rings - 1; k >= 0; k--) {
    stops.add(math.pow((rings - k) / rings, falloff).toDouble());
    colors.add(withAlpha(color, 1 - math.pow(1 - per, k + 1).toDouble()));
  }
  stops.add(1.0);
  colors.add(withAlpha(color, 0));
  final radius = size / 2;
  final shader = ui.Gradient.radial(centre, radius, colors, stops);
  final p = (paint ?? Paint())..shader = shader;
  canvas.drawCircle(centre, radius, p);
}

enum FadeDirection { down, up, left, right }

/// RN `LinearFade`: `color` fading from alpha `from` at the start edge to
/// `to` at the end edge across `rect`.
void drawLinearFade(
  Canvas canvas,
  Rect rect, {
  required Color color,
  double from = 0,
  double to = 1,
  FadeDirection direction = FadeDirection.down,
  Color? flattenBase,
}) {
  if (rect.isEmpty) return;
  Color at(double a) =>
      flattenBase == null ? withAlpha(color, a) : flattenOver(color, a, flattenBase);
  final (start, end) = switch (direction) {
    FadeDirection.down => (rect.topCenter, rect.bottomCenter),
    FadeDirection.up => (rect.bottomCenter, rect.topCenter),
    FadeDirection.right => (rect.centerLeft, rect.centerRight),
    FadeDirection.left => (rect.centerRight, rect.centerLeft),
  };
  final paint = Paint()
    ..shader = ui.Gradient.linear(start, end, [at(from), at(to)]);
  canvas.drawRect(rect, paint);
}

/// RN `Vignette`: edge darkening as four fades (cheaper than a real radial
/// vignette, and at these alphas the corners read as round anyway).
void drawVignette(
  Canvas canvas,
  Size size, {
  Color color = const Color(0xFF000000),
  double alpha = 0.55,
  double spread = 0.34,
}) {
  final bandH = size.height * spread;
  final bandW = size.width * spread;
  drawLinearFade(canvas, Rect.fromLTWH(0, 0, size.width, bandH),
      color: color, from: alpha, to: 0, direction: FadeDirection.down);
  drawLinearFade(canvas, Rect.fromLTWH(0, size.height - bandH, size.width, bandH),
      color: color, from: 0, to: alpha, direction: FadeDirection.down);
  drawLinearFade(canvas, Rect.fromLTWH(0, 0, bandW, size.height),
      color: color, from: alpha, to: 0, direction: FadeDirection.right);
  drawLinearFade(canvas, Rect.fromLTWH(size.width - bandW, 0, bandW, size.height),
      color: color, from: 0, to: alpha, direction: FadeDirection.right);
}

/// RN `Base`: the flat wash under every preset.
void drawBase(Canvas canvas, Size size, Color color) {
  canvas.drawRect(Offset.zero & size, Paint()..color = color);
}
