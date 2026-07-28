/// Ports packages/route-events/src/preset.tsx + index.tsx.
///
/// One-call setup for the route inspector: registers the tool + sync adapter
/// with [Buoy] and (when given) attaches the app's [GoRouter] so the sitemap,
/// stack, and remote `navigate` action work. Idempotent.
///
/// Because the remote `navigate`/sitemap need the router instance, the `buoy`
/// umbrella can only register the TOOL arglessly (for the dial); the app must
/// still attach [BuoyRouteObserver] to its router's `observers` AND pass the
/// router here:
///
/// ```dart
/// final _router = GoRouter(observers: [BuoyRouteObserver.instance], routes: [...]);
/// registerBuoyRoutes(router: _router); // safe to call again after the umbrella
/// ```
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'routes_capture.dart';
import 'routes_controller.dart';
import 'routes_sync_adapter.dart';
import 'routes_tool/route_event_detail.dart';
import 'routes_tool/route_event_row.dart';
import 'routes_tool/routes_modal.dart';

bool _registered = false;

/// RN preset id — the sync toolId the desktop Routes tool and the MCP
/// `get_routes`/`navigate` tools target.
const String routeEventsToolId = 'route-events';

/// Register the route inspector. Pass [router] to enable the sitemap, stack, and
/// remote navigation; call with no router (e.g. from the umbrella) to just show
/// the tool in the dial. Both orders compose — the router can be attached after
/// the tool is registered.
void registerBuoyRoutes({GoRouter? router}) {
  if (router != null) BuoyRoutesController.instance.attachRouter(router);

  if (_registered) return;
  _registered = true;

  // Contribute the route source to the events-tool timeline (RN
  // `tryLoadRouteEventsSource` in autoDiscoverEventSources.ts).
  eventSourceRegistry.register(_routeEventSource());

  Buoy.registerTool(
    BuoyTool(
      id: routeEventsToolId,
      name: 'ROUTES',
      description: 'Route tracking & navigation inspector',
      // ROUTES_ICON_COLOR (floating-tools-core icon-data.ts) — orange.
      color: const Color(0xFFFF9F1C),
      icon: (size, _) => BuoyIcon(routesIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => RoutesModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: routeEventsSyncAdapter,
  );
}

// ── Events-tool source ───────────────────────────────────────────────────────

/// The route [EventSourceAdapter] for the unified timeline. [RouteEventStore]
/// extends [BaseEventStore]; subscription rides its `onEvent` per-event hook.
EventSourceAdapter _routeEventSource() => EventSourceAdapter(
      id: routeEventsToolId,
      name: 'Routes',
      eventSources: const [EventSourceIds.route],
      subscribe: (emit) => RouteEventStore.instance
          .onEvent((event) => emit(_transformRouteEvent(event))),
      subscriberCount: () =>
          RouteEventStore.instance.getSubscriberCounts().total,
      rowBuilder: (context, event, onPress) {
        final e = event.originalEvent as RouteChangeEvent;
        return RouteEventRow(
          event: e,
          visitNumber: 0,
          onNavigate: (pathname) {
            try {
              BuoyRoutesController.instance.navigate(pathname);
            } catch (_) {}
          },
          onPress: onPress,
        );
      },
      detailBuilder: (context, event, onNavigate) {
        final e = event.originalEvent as RouteChangeEvent;
        return RouteEventDetail(
          event: e,
          visitNumber: 1,
          onNavigate: onNavigate ??
              (pathname) {
                try {
                  BuoyRoutesController.instance.navigate(pathname);
                } catch (_) {}
              },
        );
      },
    );

int _routeUnifiedId = 0;

/// Ports `transformRouteEvent` (autoDiscoverEventSources.ts).
UnifiedEvent _transformRouteEvent(RouteChangeEvent e) {
  final paramCount = e.params.length;

  // Status: success for home or a route carrying params, else neutral.
  final status = (e.pathname == '/' || paramCount > 0)
      ? EventStatus.success
      : EventStatus.neutral;

  final parts = <String>[];
  if (paramCount > 0) {
    parts.add('$paramCount param${paramCount != 1 ? 's' : ''}');
  }
  final since = e.timeSincePrevious;
  if (since != null && since > 0) {
    parts.add(since < 1000 ? '${since}ms' : '${(since / 1000).toStringAsFixed(1)}s');
  }
  if (e.previousPathname != null && e.previousPathname != e.pathname) {
    parts.add('from ${e.previousPathname}');
  }

  return UnifiedEvent(
    id: 'route-${DateTime.now().millisecondsSinceEpoch}-${++_routeUnifiedId}',
    source: EventSourceIds.route,
    timestamp: e.timestamp,
    title: e.pathname.isEmpty ? '/' : e.pathname,
    subtitle: parts.isEmpty ? 'navigation' : parts.join(' · '),
    status: status,
    originalEvent: e,
    data: e.toJson(),
  );
}
