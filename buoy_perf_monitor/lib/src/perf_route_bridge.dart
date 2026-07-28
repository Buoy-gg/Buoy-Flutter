/// Ports packages/perf-monitor/src/perf-monitor/utils/routeEventsBridge.ts +
/// routeNavigation.ts.
///
/// RN lazily `require()`s @buoy-gg/route-events; Dart has no runtime require,
/// so this bridges to `buoy_routes` directly — the same package that already
/// owns go_router attachment, the sitemap, and the remote `navigate` action.
/// Everything degrades gracefully when no router is attached (the automation
/// runner then reports "navigation unavailable", exactly like RN without
/// expo-router).
library;

import 'dart:async';

import 'package:buoy_routes/buoy_routes.dart';

import 'route_validation.dart';

/// True when a [GoRouter] is attached, i.e. the runner can drive navigation.
bool isNavigationAvailable() => BuoyRoutesController.instance.hasRouter;

/// Newest route pathname the route store has seen ("" when unknown).
/// RN `getCurrentRoute()`.
String getCurrentRoute() {
  final events = RouteEventStore.instance.getEvents();
  if (events.isEmpty) return '';
  return events.last.pathname;
}

/// Flattened sitemap pathnames (RN `useSafeRouteList`). Empty when no router
/// is attached — callers treat that as "skip validation".
List<String> getRouteList() {
  final out = <String>[];
  void walk(List<RouteInfo> routes) {
    for (final r in routes) {
      if (!r.isInternal && r.path.isNotEmpty) out.add(r.path);
      if (r.children.isNotEmpty) walk(r.children);
    }
  }

  walk(BuoyRoutesController.instance.sitemap());
  final seen = <String>{};
  final unique = [
    for (final p in out)
      if (seen.add(p)) p,
  ]..sort();
  return unique;
}

/// The live navigation stack, top-of-stack last (RN `useSafeNavigationStack`).
List<StackDisplayItem> getNavigationStack() =>
    NavigationStackStore.instance.getStack();

/// Subscribe to route changes (RN `subscribeRouteChanges`).
void Function() subscribeRouteChanges(void Function(String pathname) fn) =>
    RouteEventStore.instance.onEvent((event) => fn(event.pathname));

class NavigateAndWaitResult {
  const NavigateAndWaitResult({
    required this.matched,
    required this.fellBackToSleep,
    required this.timedOut,
  });

  /// True when the route observer fired for the requested pathname in time.
  final bool matched;

  /// True when no observer was available — the caller can't tell if nav worked.
  final bool fellBackToSleep;

  /// True when the timeout elapsed with no matching route event.
  final bool timedOut;
}

/// Build the concrete location for a case: pathname + encoded query params.
String buildLocation(String pathname, Map<String, String>? params) {
  if (params == null || params.isEmpty) return pathname;
  final query = [
    for (final e in params.entries)
      '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
  ].join('&');
  return pathname.contains('?') ? '$pathname&$query' : '$pathname?$query';
}

/// Imperatively navigate, then wait for the route store to report a pathname
/// matching [expectedPathname]. Resolves with how the wait ended (RN
/// `navigateAndWait`). Throws when no router is attached.
Future<NavigateAndWaitResult> navigateAndWait({
  required String expectedPathname,
  required String pathname,
  Map<String, String>? params,
  required int timeoutMs,
}) async {
  if (!isNavigationAvailable()) {
    throw StateError(
      'Navigation unavailable — no GoRouter registered. Call '
      'registerBuoyRoutes(router: myRouter) so the benchmark runner can drive it.',
    );
  }

  final completer = Completer<NavigateAndWaitResult>();

  // Wire the listener BEFORE navigating so a fast-firing event isn't missed.
  final unsubscribe = subscribeRouteChanges((observed) {
    if (observed.isEmpty) return;
    if (!pathnameMatches(observed, expectedPathname)) return;
    if (!completer.isCompleted) {
      completer.complete(const NavigateAndWaitResult(
        matched: true,
        fellBackToSleep: false,
        timedOut: false,
      ));
    }
  });

  Timer? timeout;
  void cleanup() {
    timeout?.cancel();
    timeout = null;
    unsubscribe();
  }

  try {
    BuoyRoutesController.instance.navigate(buildLocation(pathname, params));
  } catch (err) {
    cleanup();
    rethrow;
  }

  timeout = Timer(Duration(milliseconds: timeoutMs < 50 ? 50 : timeoutMs), () {
    if (!completer.isCompleted) {
      completer.complete(const NavigateAndWaitResult(
        matched: false,
        fellBackToSleep: false,
        timedOut: true,
      ));
    }
  });

  final result = await completer.future;
  cleanup();
  return result;
}

Future<void> sleep(int ms) =>
    Future<void>.delayed(Duration(milliseconds: ms < 0 ? 0 : ms));
