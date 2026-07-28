/// Ports packages/image-overlay/src/preset.tsx (`createImageOverlayTool` +
/// `imageOverlayToolPreset` + `IMAGE_OVERLAY_ICON_COLOR`).
///
/// Registers the image-overlay tool with [Buoy] AND mounts its standalone
/// overlay into [BuoyOverlayHost] — the Flutter analog of RN's
/// `FloatingDevTools` auto-mounting `<ImageOverlayStandalone/>`. Argless and
/// idempotent, so the `buoy` umbrella can call it safely.
///
/// Unlike every other Buoy tool, image-overlay has **no sync adapter** (it's a
/// pure-UI tool) — [Buoy.registerTool] is called without one, so it announces
/// no desktop-sync tool.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';

import 'image_overlay_standalone.dart';
import 'image_overlay_tool/image_overlay_modal.dart';

bool _registered = false;

/// RN `IMAGE_OVERLAY_ICON_COLOR` (#A855F7).
const Color kImageOverlayColor = Color(0xFFA855F7);

/// Register the image-overlay tool + its overlay layer. Idempotent.
void registerBuoyImageOverlay() {
  if (_registered) return;
  _registered = true;

  // Mount the full-screen overlay that draws over the app, outside the modal.
  BuoyOverlayHost.instance
      .register((context) => const ImageOverlayStandalone());

  Buoy.registerTool(
    BuoyTool(
      // RN preset id 'image-overlay', name 'IMG'. ImageOverlayIcon (#A855F7)
      // is an image/overlay glyph → BuoyIcons.image.
      id: 'image-overlay',
      name: 'IMG',
      description: 'Design mockup overlay',
      color: kImageOverlayColor,
      icon: (size, _) => BuoyIcon(imageOverlayIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) =>
          ImageOverlayModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    // No adapter — parity with the RN package (the only tool without one).
  );
}
