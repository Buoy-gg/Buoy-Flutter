/// Buoy devtools for Flutter — umbrella package.
///
/// One widget wires everything: wrap your app with [BuoyDevTools] (via
/// `MaterialApp.builder`) and every installed Buoy tool auto-registers —
/// HTTP capture, the in-app floating menu, live desktop sync, and the MCP
/// server connection. See https://buoy.gg for docs.
library;

export 'package:buoy_core/buoy_core.dart' hide BuoyDevTools;
export 'package:buoy_shared_ui/buoy_shared_ui.dart';
export 'package:buoy_network/buoy_network.dart' hide BuoyDevTools;
export 'package:buoy_perf_monitor/buoy_perf_monitor.dart'
    hide Buoy, BuoyDevTools, BuoyOverlayHost, BuoySyncClient, BuoyTool;
export 'package:buoy_riverpod/buoy_riverpod.dart'
    hide Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;
export 'package:buoy_storage/buoy_storage.dart'
    hide Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;
export 'package:buoy_console/buoy_console.dart'
    hide Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;
export 'package:buoy_env/buoy_env.dart'
    hide Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;
export 'package:buoy_events/buoy_events.dart'
    hide Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;
export 'package:buoy_routes/buoy_routes.dart'
    hide Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;
export 'package:buoy_images/buoy_images.dart'
    hide Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;
export 'package:buoy_impersonate/buoy_impersonate.dart'
    hide Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;
export 'package:buoy_image_overlay/buoy_image_overlay.dart'
    hide Buoy, BuoyDevTools, BuoyOverlayHost, BuoySyncClient, BuoyTool;

export 'src/buoy_devtools.dart';
