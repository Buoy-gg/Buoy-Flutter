/// Ports packages/route-events/src/sync/routeEventsSyncAdapter.ts.
///
/// Field-for-field mirror of the RN adapter (version 3, same action names and
/// the `{events, sitemap, stack}` payload) so Buoy Desktop's Routes tool (both
/// the Sitemap AND Stack tabs) and the MCP `get_routes`/`navigate` tools work
/// with zero changes.
///
/// Subscribing attaches listeners to the route-event store + the navigation
/// stack store, so snapshots push as the app navigates. The `sitemap` carries
/// the parsed route tree (the desktop has no local router) and `navigate` /
/// `stack*` actions drive navigation on the device.
library;

import 'package:buoy_core/buoy_core.dart';

import 'routes_capture.dart';
import 'routes_controller.dart';

Map<String, Object?>? _asMap(Object? params) {
  if (params is Map<String, Object?>) return params;
  if (params is Map) return params.cast<String, Object?>();
  return null;
}

/// RN `getSitemapSnapshot` — the parsed route tree plus its metadata.
Map<String, Object?> _sitemapSnapshot() {
  final controller = BuoyRoutesController.instance;
  return {
    'routes': [for (final r in controller.sitemap()) r.toJson()],
    // Flutter has no expo-router build/src distinction.
    'source': null,
    'lastUpdatedAt': controller.sitemapUpdatedAt,
  };
}

/// The route-events tool's sync adapter — mirrors routeEventsSyncAdapter.ts.
final routeEventsSyncAdapter = ToolSyncAdapter(
  version: 3,
  getSnapshot: () => {
    'events': [for (final e in RouteEventStore.instance.getEvents()) e.toJson()],
    'sitemap': _sitemapSnapshot(),
    'stack': [
      for (final s in NavigationStackStore.instance.getStack()) s.toJson(),
    ],
  },
  subscribe: (onChange) {
    final unsubEvents =
        RouteEventStore.instance.subscribeToEvents((_) => onChange());
    final unsubStack = NavigationStackStore.instance.subscribe(onChange);
    return () {
      unsubEvents();
      unsubStack();
    };
  },
  actions: {
    'clearEvents': (_) {
      RouteEventStore.instance.clearEvents();
      return null;
    },
    // Navigate the device to a concrete path (the dashboard resolves any
    // dynamic params into a concrete path before invoking this).
    'navigate': (params) {
      final path = _asMap(params)?['path'] as String?;
      if (path == null) {
        throw ArgumentError("navigate requires a 'path' param");
      }
      return BuoyRoutesController.instance.navigate(path);
    },
    // Stack actions — delegate to the live controller (holds the router ref).
    'stackNavigateToIndex': (params) {
      final index = _asMap(params)?['index'];
      if (index is! num) {
        throw ArgumentError("stackNavigateToIndex requires a numeric 'index'");
      }
      BuoyRoutesController.instance.navigateToIndex(index.toInt());
      return {'navigatedToIndex': index.toInt()};
    },
    'stackPopToIndex': (params) {
      final index = _asMap(params)?['index'];
      if (index is! num) {
        throw ArgumentError("stackPopToIndex requires a numeric 'index'");
      }
      BuoyRoutesController.instance.popToIndex(index.toInt());
      return {'poppedToIndex': index.toInt()};
    },
    'stackGoBack': (_) {
      BuoyRoutesController.instance.goBack();
      return {'wentBack': true};
    },
    'stackPopToTop': (_) {
      BuoyRoutesController.instance.popToTop();
      return {'poppedToTop': true};
    },
  },
);
