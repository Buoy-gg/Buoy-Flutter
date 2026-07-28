/// Buoy Images tool for Flutter.
///
/// A live registry of every image loaded through [BuoyImage] — cache verdict
/// (memory/disk/network), load timing, decoded-vs-displayed oversize audit,
/// estimated decoded/wasted memory, and a failure log — with per-image
/// reload/retry, simulation overrides, and live streaming to Buoy Desktop + the
/// MCP server (`get_images`, `image_action`, `set_image_simulation`).
///
/// Flutter has no app-wide `Image` decorator hook, so capture is opt-in: use
/// [BuoyImage] in place of `Image` / `CachedNetworkImage`. Registration is
/// automatic via the `buoy` umbrella widget, or call [registerBuoyImages] once.
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

// The capture widget, the record model, the store, actions, and the adapter.
// `image_format.dart` / `image_export.dart` stay internal (their `formatBytes`/
// `formatMs` would clash with buoy_shared_ui's) — import them by path if needed.
export 'src/buoy_image.dart';
export 'src/image_record.dart';
export 'src/images_actions.dart'
    show
        ImagesActions,
        ImageOverride,
        OverrideSource,
        OverrideKind,
        NetworkMode,
        ActionResult;
export 'src/images_store.dart';
export 'src/images_sync_adapter.dart' show imagesSyncAdapter;
export 'src/register.dart';
