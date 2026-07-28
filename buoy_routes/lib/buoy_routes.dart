/// Buoy route inspector for Flutter.
///
/// Attach [BuoyRouteObserver] to your `GoRouter(observers: [...])`, call
/// [registerBuoyRoutes] with the router, and mount the `buoy` umbrella — the
/// route timeline, sitemap, and navigation stack stream to Buoy Desktop and the
/// MCP server. Ports `@buoy-gg/route-events` 1:1 (sync protocol v3
/// `{events, sitemap, stack}`).
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

export 'src/buoy_route_observer.dart';
export 'src/register.dart';
export 'src/route_parser.dart' show RouteInfo, RouteType, RouteGroup, RouteStats;
export 'src/routes_capture.dart'
    show RouteChangeEvent, StackDisplayItem, RouteEventStore, NavigationStackStore;
export 'src/routes_controller.dart' show BuoyRoutesController;
export 'src/routes_sync_adapter.dart' show routeEventsSyncAdapter;
