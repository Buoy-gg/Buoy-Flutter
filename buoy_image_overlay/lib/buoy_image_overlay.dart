/// Buoy image-overlay tool for Flutter.
///
/// Pin a design mockup on top of your running app at adjustable opacity for
/// pixel-perfect UI comparison — a 1:1 port of `@buoy-gg/image-overlay`. Two
/// modes: Free Placement (drag + aspect-locked resize anywhere) and Component
/// Match (overlay onto a widget tagged with [BuoyImageTarget]). Pure UI: no
/// data capture and, matching the RN package, no desktop-sync adapter.
///
/// Register with `registerBuoyImageOverlay()` (the `buoy` umbrella does this for
/// you). The overlay renders via `buoy_core`'s [BuoyOverlayHost], outside the
/// control modal, and survives navigation.
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoyOverlayHost, BuoySyncClient, BuoyTool;

export 'src/register.dart' show registerBuoyImageOverlay, kImageOverlayColor;
export 'src/image_overlay_controller.dart'
    show ImageOverlayController, providerForUri;
export 'src/image_overlay_types.dart'
    show ImageOverlayState, OverlayMode, MeasuredRect, DiscoveredTarget;
export 'src/image_target_registry.dart'
    show BuoyImageTarget, scanForImageTargets, measureTarget;
export 'src/image_overlay_standalone.dart' show ImageOverlayStandalone;
export 'src/image_overlay_tool/image_overlay_modal.dart' show ImageOverlayModal;
