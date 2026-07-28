/// Ports packages/route-events/src/RouteObserver.ts + stores/routeEventStore.ts
/// + stores/navigationStackStore.ts + the StackDisplayItem model from
/// useNavigationStack.ts.
///
/// The device-side event + stack model. [RouteChangeEvent] and
/// [StackDisplayItem] serialize to the exact RN JSON field names — the route
/// timeline, the desktop Stack tab, and the MCP `get_routes` tool consume them.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

/// Ports RN `RouteChangeEvent`. One navigation event (newest-first in the store).
class RouteChangeEvent {
  const RouteChangeEvent({
    required this.pathname,
    required this.params,
    required this.segments,
    required this.timestamp,
    this.previousPathname,
    this.timeSincePrevious,
  });

  final String pathname;
  final Map<String, Object?> params;
  final List<String> segments;

  /// Milliseconds since epoch.
  final int timestamp;
  final String? previousPathname;

  /// Milliseconds since the previous event.
  final int? timeSincePrevious;

  Map<String, Object?> toJson() => {
    'pathname': pathname,
    'params': params,
    'segments': segments,
    'timestamp': timestamp,
    if (previousPathname != null) 'previousPathname': previousPathname,
    if (timeSincePrevious != null) 'timeSincePrevious': timeSincePrevious,
  };
}

/// Ports RN `routeEventStore` (BaseEventStore, storeName "route-events",
/// maxEvents 500). The controller feeds events via [record]; capture lifecycle
/// hooks are no-ops because emission is driven by the router/observer, not by
/// subscriber count.
class RouteEventStore extends BaseEventStore<RouteChangeEvent> {
  RouteEventStore() : super(storeName: 'route-events', maxEvents: 500);

  static final RouteEventStore instance = RouteEventStore();

  @override
  void startCapturing() {}

  @override
  void stopCapturing() {}

  @override
  bool isCapturing() => true;

  /// Record a new navigation event (RN `routeObserver.emit` → `addEvent`).
  void record(RouteChangeEvent event) => addEvent(event);
}

/// Ports RN `StackDisplayItem` (useNavigationStack.ts).
class StackDisplayItem {
  const StackDisplayItem({
    required this.key,
    required this.name,
    required this.pathname,
    required this.params,
    required this.isFocused,
    required this.index,
    required this.canPop,
  });

  final String key;
  final String name;
  final String pathname;
  final Map<String, Object?> params;
  final bool isFocused;
  final int index;
  final bool canPop;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'pathname': pathname,
    'params': params,
    'isFocused': isFocused,
    'index': index,
    'canPop': canPop,
  };
}

/// A raw stack entry before index/focus/canPop are computed — the shared input
/// for both the go_router (RouteMatchList) and NavigatorObserver stack builders.
typedef RawStackEntry = ({String key, String name, String pathname, Map<String, Object?> params});

/// Ports the `buildStack` mapping in useNavigationStack.ts: assign index,
/// mark the last item focused, and set `canPop` for everything above the root.
/// Pure (no Flutter/go_router) so it can be unit-tested against RN expectations.
List<StackDisplayItem> buildStack(List<RawStackEntry> entries) {
  final result = <StackDisplayItem>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    var pathname = e.pathname.isEmpty ? '/' : e.pathname;
    result.add(StackDisplayItem(
      key: e.key,
      name: e.name,
      pathname: pathname,
      params: e.params,
      isFocused: i == entries.length - 1,
      index: i,
      canPop: i > 0,
    ));
  }
  return result;
}

/// Ports RN `navigationStackStore` — holds the latest serializable stack and
/// notifies listeners (the sync adapter subscribes so the dashboard Stack tab
/// updates). The live navigation actions stay on [BuoyRoutesController]; this
/// store is data-only.
class NavigationStackStore {
  NavigationStackStore._();
  static final NavigationStackStore instance = NavigationStackStore._();

  List<StackDisplayItem> _stack = const [];
  final Set<void Function()> _listeners = {};

  List<StackDisplayItem> getStack() => _stack;

  void setStack(List<StackDisplayItem> stack) {
    _stack = stack;
    for (final listener in {..._listeners}) {
      listener();
    }
  }

  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}
