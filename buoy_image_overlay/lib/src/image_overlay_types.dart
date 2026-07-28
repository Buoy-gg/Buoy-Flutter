/// Ports packages/image-overlay/src/imageOverlay/types/index.ts.
///
/// The overlay state model shared between the control modal and the standalone
/// overlay layer, plus the discovered-target descriptor.
library;

import 'package:flutter/widgets.dart';

/// A screen-space bounding rect (RN `MeasuredRect`). In Flutter these are the
/// tracked widget's `RenderBox.localToGlobal(Offset.zero)` + `size`.
@immutable
class MeasuredRect {
  const MeasuredRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is MeasuredRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// RN `OverlayMode` — `"component"` (match a tagged widget), `"free"` (drag
/// anywhere), or `null` (nothing chosen yet).
enum OverlayMode { component, free }

/// RN `ImageOverlayState`. Immutable; mutate via [copyWith]. Field names + defaults
/// mirror `DEFAULT_STATE` in ImageOverlayController.ts exactly.
@immutable
class ImageOverlayState {
  const ImageOverlayState({
    this.mode,
    this.enabled = false,
    this.imageUri,
    this.imageWidth,
    this.imageHeight,
    this.targetTag,
    this.targetLabel,
    this.targetRect,
    this.showOutline = true,
    this.opacity = 0.5,
    this.scale = 1.0,
    this.offsetX = 0,
    this.offsetY = 0,
    this.invertX = false,
    this.invertY = false,
    this.locked = false,
    this.freeX = 0,
    this.freeY = 0,
    this.freeWidth = 200,
    this.freeHeight = 200,
  });

  final OverlayMode? mode;
  final bool enabled;
  final String? imageUri;
  final double? imageWidth;
  final double? imageHeight;

  // Component match mode.
  final int? targetTag;
  final String? targetLabel;
  final MeasuredRect? targetRect;
  final bool showOutline;
  final double opacity;
  final double scale;
  final double offsetX;
  final double offsetY;
  final bool invertX;
  final bool invertY;
  final bool locked;

  // Free placement mode.
  final double freeX;
  final double freeY;
  final double freeWidth;
  final double freeHeight;

  /// Returns a copy with the given fields replaced. Pass [clearImageSize] /
  /// [clearTargetRect] / [clearMode] to force a field back to `null` (Dart
  /// can't distinguish "omitted" from "set to null" without a sentinel).
  ImageOverlayState copyWith({
    OverlayMode? mode,
    bool? enabled,
    String? imageUri,
    double? imageWidth,
    double? imageHeight,
    int? targetTag,
    String? targetLabel,
    MeasuredRect? targetRect,
    bool? showOutline,
    double? opacity,
    double? scale,
    double? offsetX,
    double? offsetY,
    bool? invertX,
    bool? invertY,
    bool? locked,
    double? freeX,
    double? freeY,
    double? freeWidth,
    double? freeHeight,
    bool clearMode = false,
    bool clearImageSize = false,
    bool clearTargetRect = false,
  }) {
    return ImageOverlayState(
      mode: clearMode ? null : (mode ?? this.mode),
      enabled: enabled ?? this.enabled,
      imageUri: imageUri ?? this.imageUri,
      imageWidth: clearImageSize ? null : (imageWidth ?? this.imageWidth),
      imageHeight: clearImageSize ? null : (imageHeight ?? this.imageHeight),
      targetTag: targetTag ?? this.targetTag,
      targetLabel: targetLabel ?? this.targetLabel,
      targetRect: clearTargetRect ? null : (targetRect ?? this.targetRect),
      showOutline: showOutline ?? this.showOutline,
      opacity: opacity ?? this.opacity,
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      invertX: invertX ?? this.invertX,
      invertY: invertY ?? this.invertY,
      locked: locked ?? this.locked,
      freeX: freeX ?? this.freeX,
      freeY: freeY ?? this.freeY,
      freeWidth: freeWidth ?? this.freeWidth,
      freeHeight: freeHeight ?? this.freeHeight,
    );
  }
}

/// RN `DiscoveredTarget`. In Flutter the `key` (a `GlobalKey`) replaces the RN
/// fiber/instance — it's what we measure.
@immutable
class DiscoveredTarget {
  const DiscoveredTarget({
    required this.label,
    required this.testID,
    required this.key,
    this.componentName,
  });

  final String label;

  /// The synthetic identifier shown in the target list, mirroring RN's
  /// `testID="image-target:Label"`.
  final String testID;

  /// The registered widget's key — used to measure its `RenderBox`.
  final GlobalKey key;

  final String? componentName;
}
