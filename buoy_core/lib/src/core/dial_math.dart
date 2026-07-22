/// Dial menu layout math and animation timing, ported 1:1 from
/// @buoy-gg/floating-tools-core `dial.ts`. Pure Dart — no Flutter imports —
/// so it stays unit-testable and reusable when this graduates to a package.
library;

import 'dart:math' as math;

/// Number of slots in the dial (unused slots render as placeholder dots).
const int maxDialSlots = 6;

/// First icon sits at the top of the circle.
const double dialStartAngle = -math.pi / 2;

const double dialButtonSize = 80;
const double dialIconSize = 60;
const double dialIconPadding = 20;
const int dialGridLineCount = 6;

class DialLayout {
  const DialLayout({
    required this.circleSize,
    required this.circleRadius,
    required this.iconRadius,
    required this.iconSize,
    required this.buttonSize,
  });

  final double circleSize;
  final double circleRadius;
  final double iconRadius;
  final double iconSize;
  final double buttonSize;
}

DialLayout getDialLayout(
  double screenWidth, {
  double maxCircleSize = 320,
  double circleSizeRatio = 0.75,
  double iconSize = dialIconSize,
  double iconPadding = dialIconPadding,
}) {
  final circleSize = math.min(screenWidth * circleSizeRatio, maxCircleSize);
  final circleRadius = circleSize / 2;
  return DialLayout(
    circleSize: circleSize,
    circleRadius: circleRadius,
    iconRadius: circleRadius - iconSize / 2 - iconPadding,
    iconSize: iconSize,
    buttonSize: dialButtonSize,
  );
}

class IconPosition {
  const IconPosition({required this.x, required this.y, required this.angle});

  final double x;
  final double y;

  /// Angle in radians.
  final double angle;
}

double getIconAngle(
  int index,
  int totalIcons, [
  double startAngle = dialStartAngle,
]) {
  final anglePerIcon = (2 * math.pi) / totalIcons;
  return startAngle + anglePerIcon * index;
}

IconPosition getIconPosition(
  int index,
  int totalIcons,
  double radius, [
  double startAngle = dialStartAngle,
]) {
  final angle = getIconAngle(index, totalIcons, startAngle);
  return IconPosition(
    x: radius * math.cos(angle),
    y: radius * math.sin(angle),
    angle: angle,
  );
}

List<IconPosition> getAllIconPositions(
  int totalIcons,
  double radius, [
  double startAngle = dialStartAngle,
]) => [
  for (var i = 0; i < totalIcons; i++)
    getIconPosition(i, totalIcons, radius, startAngle),
];

/// Rotation angles in degrees for the dial's background grid lines.
List<double> getGridLineRotations([int count = dialGridLineCount]) => [
  for (var i = 0; i < count; i++) i * (360 / count),
];

// =============================
// Animation timing (dialAnimationConfig)
// =============================

/// Entrance/exit/continuous timing from `dialAnimationConfig`. Curve shapes
/// (the CSS-bezier spring approximations) live in the UI layer since Dart
/// `Curve`s are a Flutter type.
class DialAnimation {
  // Entrance sequence.
  static const backdropInMs = 400;
  static const dialScaleSpringDamping = 15.0;
  static const dialScaleSpringStiffness = 150.0;
  static const rotationMs = 800;
  static const rotationDegrees = 360.0;
  static const centerButtonDelayMs = 300;
  static const iconsDelayMs = 500;
  static const iconsInMs = 600;

  /// Total entrance timeline (icons delay + icons duration).
  static const entranceTotalMs = iconsDelayMs + iconsInMs;

  // Exit sequence.
  static const iconsOutMs = 300;
  static const dialScaleOutMs = 250;
  static const backdropOutMs = 200;
  static const exitTotalMs = 300;

  // Continuous pulse on the circle.
  static const pulseMinScale = 0.98;
  static const pulseMaxScale = 1.02;
  static const pulseHalfPeriodMs = 1000;

  // Icon entrance.
  static const staggerRatio = 0.1;
  static const spiralStartRotation = math.pi * 2;
  static const spiralEndRotation = 0.0;
  static const opacityInputRange = [0.0, 0.3, 1.0];
  static const opacityOutputRange = [0.0, 0.3, 1.0];
}

/// Interpolation input range for a staggered icon: [0, delayStart, settleStart, 1].
List<double> getIconStaggerInputRange(
  int index,
  int totalIcons, {
  double staggerRatio = DialAnimation.staggerRatio,
}) {
  final staggerDelay = index * staggerRatio;
  final maxStagger = (totalIcons - 1) * staggerRatio;
  return [0, staggerDelay, staggerDelay + (1 - maxStagger), 1];
}

/// Map the master 0–1 progress through an icon's stagger window.
double getStaggeredIconProgress(
  double masterProgress,
  int index,
  int totalIcons,
) {
  final range = getIconStaggerInputRange(index, totalIcons);
  if (masterProgress <= range[1]) return 0;
  if (masterProgress >= range[2]) return 1;
  final t = (masterProgress - range[1]) / (range[2] - range[1]);
  return t.clamp(0.0, 1.0);
}

class SpiralPosition {
  const SpiralPosition({
    required this.x,
    required this.y,
    required this.rotation,
    required this.scale,
    required this.opacity,
  });

  final double x;
  final double y;
  final double rotation;
  final double scale;
  final double opacity;
}

/// Icon position along the spiral entrance path: flies out from the center
/// (distance 0 → radius) while un-rotating (2π → 0), fading in.
SpiralPosition getSpiralAnimationPosition(
  double progress,
  int index,
  int totalIcons,
  double radius, [
  double startAngle = dialStartAngle,
]) {
  final finalPos = getIconPosition(index, totalIcons, radius, startAngle);
  final p = progress.clamp(0.0, 1.0);

  final rotation =
      DialAnimation.spiralStartRotation +
      (DialAnimation.spiralEndRotation - DialAnimation.spiralStartRotation) * p;
  final distance = radius * p;
  final spiralAngle = finalPos.angle + rotation;

  final spiralX = distance * math.cos(spiralAngle);
  final spiralY = distance * math.sin(spiralAngle);

  // Blend the spiral path toward the final resting position as p → 1.
  final x = spiralX + (finalPos.x - spiralX) * p;
  final y = spiralY + (finalPos.y - spiralY) * p;

  return SpiralPosition(
    x: x,
    y: y,
    rotation: rotation,
    scale: p,
    opacity: _interpolateOpacity(p),
  );
}

double _interpolateOpacity(double p) {
  const input = DialAnimation.opacityInputRange;
  const output = DialAnimation.opacityOutputRange;
  if (p <= input[0]) return output[0];
  if (p <= input[1]) {
    final t = (p - input[0]) / (input[1] - input[0]);
    return output[0] + (output[1] - output[0]) * t;
  }
  final t = (p - input[1]) / (input[2] - input[1]);
  return output[1] + (output[2] - output[1]) * t;
}
