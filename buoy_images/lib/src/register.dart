import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';

import 'images_sync_adapter.dart';
import 'images_tool/images_modal.dart';

bool _registered = false;

/// One-call setup for the Images tool: registers the tool + sync adapter with
/// [Buoy]. Idempotent. Called automatically by the `buoy` umbrella widget; apps
/// depending on `buoy_images` directly call it once before `runApp` (or let the
/// `BuoyDevTools` mount trigger it via the umbrella).
///
/// Capture itself is opt-in per image: use [BuoyImage] in place of `Image` /
/// `CachedNetworkImage`. Flutter has no app-wide `Image` decorator hook (unlike
/// RN's `unstable_setImageComponentDecorator`), so only wrapped images appear
/// in the registry.
void registerBuoyImages() {
  if (_registered) return;
  _registered = true;

  Buoy.registerTool(
    BuoyTool(
      id: 'images',
      name: 'Images',
      description: 'Image loads, caching, failures, and oversize checks',
      // RN IMAGES_ICON_COLOR photo-violet (#C084FC).
      color: const Color(0xFFC084FC),
      icon: (size, _) => BuoyIcon(imagesIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => ImagesModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: imagesSyncAdapter,
  );
}
