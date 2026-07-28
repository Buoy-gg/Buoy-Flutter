/// Ports the NavigatorObserver role of packages/route-events/src/RouteTracker.tsx
/// (the React Navigation fallback path).
///
/// [BuoyRouteObserver] is a [NavigatorObserver] the app adds to its router's
/// `observers`. It is the universal capture for plain-Navigator apps (no
/// go_router): push/pop/replace/remove maintain an ordered stack and feed
/// [BuoyRoutesController], which turns it into events + the stack model.
///
/// When a [GoRouter] is registered the controller ignores these callbacks
/// (go_router's delegate is authoritative — see routes_controller.dart), but the
/// observer is still safe to attach and demonstrates the plain-Navigator path.
library;

import 'package:flutter/widgets.dart';

import 'routes_capture.dart';
import 'routes_controller.dart';

class BuoyRouteObserver extends NavigatorObserver {
  BuoyRouteObserver();

  /// Shared instance apps attach to `GoRouter(observers: [...])` /
  /// `MaterialApp(navigatorObservers: [...])`.
  static final BuoyRouteObserver instance = BuoyRouteObserver();

  final List<Route<dynamic>> _routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) return;
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      _routes[index] = newRoute;
    } else {
      _routes.add(newRoute);
    }
    _sync();
  }

  void _sync() {
    final entries = <RawStackEntry>[];
    for (var i = 0; i < _routes.length; i++) {
      final route = _routes[i];
      final settings = route.settings;
      final pathname = settings.name ?? '/';
      final args = settings.arguments;
      entries.add((
        key: '${identityHashCode(route)}',
        name: _nameOf(pathname),
        pathname: pathname,
        params: args is Map ? args.cast<String, Object?>() : const {},
      ));
    }
    BuoyRoutesController.instance.handleObserverStack(entries);
  }

  String _nameOf(String pathname) {
    final segs = pathname.split('/').where((s) => s.isNotEmpty).toList();
    return segs.isEmpty ? 'index' : segs.last;
  }
}
