/// Ports the wiring in packages/route-events/src/RouteTracker.tsx +
/// useRouteObserver.ts + useNavigationStack.ts (the parts that observe the
/// router and feed the stores + run navigation actions).
///
/// [BuoyRoutesController] is the device-side brain: it captures navigation into
/// [RouteEventStore] + [NavigationStackStore], builds the sitemap, and executes
/// the remote/UI navigation actions.
///
/// **go_router is the authoritative source** when a [GoRouter] is registered.
/// go_router uses Page-based routing and sets no `Route.settings.name` for
/// path-only routes, so a [NavigatorObserver] alone can't recover the pathname;
/// instead we listen to `router.routerDelegate` and read
/// `currentConfiguration` (a `RouteMatchList`). [BuoyRouteObserver] is the
/// fallback capture for plain-Navigator apps and DEFERS while a router is
/// attached (so events aren't double-emitted).
///
/// Gotcha (verified go_router 17.3): `RouteMatchList.uri`/`.pathParameters`
/// ignore `ImperativeRouteMatch` (i.e. `context.push`), so the current location
/// is read from `currentConfiguration.last.matchedLocation`, and the stack from
/// `currentConfiguration.matches` (which DOES include the pushed match).
library;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:go_router/go_router.dart';

import 'route_parser.dart';
import 'routes_capture.dart';

class BuoyRoutesController {
  BuoyRoutesController._();
  static final BuoyRoutesController instance = BuoyRoutesController._();

  GoRouter? _router;
  VoidCallback? _detachRouterListener;

  // Event de-dup / timing (RN previousPathnameRef / previousTimestampRef).
  String? _lastPathname;
  int? _lastTimestamp;

  int? _sitemapUpdatedAt;

  // Observer fallback state (plain-Navigator apps, no go_router).
  final List<RawStackEntry> _observerEntries = [];

  bool get hasRouter => _router != null;
  int? get sitemapUpdatedAt => _sitemapUpdatedAt;

  // ── Router attachment ─────────────────────────────────────────────────────

  /// Attach (or replace) the app's [GoRouter]. Listens to its delegate so route
  /// changes become events + stack updates, and enables the sitemap + navigate
  /// action. Idempotent for the same router.
  void attachRouter(GoRouter router) {
    if (identical(_router, router)) return;
    _detachRouterListener?.call();
    _router = router;
    _sitemapUpdatedAt = DateTime.now().millisecondsSinceEpoch;
    void listener() => _onRouterChanged();
    router.routerDelegate.addListener(listener);
    _detachRouterListener = () => router.routerDelegate.removeListener(listener);
    // Capture the initial location so the timeline/stack fill in without a
    // first navigation (RN's mount-time emit).
    _onRouterChanged();
  }

  void _onRouterChanged() {
    final router = _router;
    if (router == null) return;
    final config = router.routerDelegate.currentConfiguration;
    if (config.isEmpty) return;

    final current = config.last; // leaf, follows ImperativeRouteMatch
    final pathname = _clean(current.matchedLocation);
    final params = Map<String, Object?>.from(config.pathParameters);
    final segments = _segmentsOf(pathname);

    _emitIfChanged(pathname, params, segments);
    _pushStack(_buildGoRouterStack(config));
  }

  // ── Observer fallback (no go_router) ───────────────────────────────────────

  /// Called by [BuoyRouteObserver]. No-op while a [GoRouter] is attached
  /// (go_router is authoritative). `entries` is the current stack top-first?
  /// No — bottom-first (index 0 = root).
  void handleObserverStack(List<RawStackEntry> entries) {
    if (_router != null) return;
    _observerEntries
      ..clear()
      ..addAll(entries);
    if (entries.isNotEmpty) {
      final top = entries.last;
      _emitIfChanged(_clean(top.pathname), top.params, _segmentsOf(top.pathname));
    }
    _pushStack(buildStack(entries));
  }

  // ── Event emission ─────────────────────────────────────────────────────────

  void _emitIfChanged(
    String pathname,
    Map<String, Object?> params,
    List<String> segments,
  ) {
    if (pathname == _lastPathname) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeSince = _lastTimestamp == null ? null : now - _lastTimestamp!;
    RouteEventStore.instance.record(RouteChangeEvent(
      pathname: pathname,
      params: params,
      segments: segments,
      timestamp: now,
      previousPathname: _lastPathname,
      timeSincePrevious: timeSince,
    ));
    _lastPathname = pathname;
    _lastTimestamp = now;
  }

  // ── Stack building (go_router) ──────────────────────────────────────────────

  void _pushStack(List<StackDisplayItem> stack) {
    NavigationStackStore.instance.setStack(stack);
  }

  List<StackDisplayItem> _buildGoRouterStack(RouteMatchList config) {
    final leaves = <RouteMatch>[];
    void collect(List<RouteMatchBase> matches) {
      for (final m in matches) {
        if (m is ShellRouteMatch) {
          collect(m.matches);
        } else if (m is RouteMatch) {
          leaves.add(m);
        }
      }
    }

    collect(config.matches);

    final entries = <RawStackEntry>[
      for (final m in leaves)
        (
          key: m.pageKey.value,
          name: _nameOf(m),
          pathname: _clean(m.matchedLocation),
          params: _extractPathParams(m.route.path, m.matchedLocation),
        ),
    ];
    return buildStack(entries);
  }

  String _nameOf(RouteMatch m) {
    final name = m.route.name;
    if (name != null && name.isNotEmpty) return name;
    final segs = _segmentsOf(m.matchedLocation);
    return segs.isEmpty ? 'index' : segs.last;
  }

  // ── Navigation actions (UI + remote) ────────────────────────────────────────

  /// Remote/UI navigate to a concrete path (RN `router.navigate`).
  Object navigate(String path) {
    final router = _router;
    if (router == null) {
      throw StateError('go_router is not available on this device');
    }
    router.go(path);
    return {'navigated': path};
  }

  void navigateToIndex(int index) {
    final stack = NavigationStackStore.instance.getStack();
    if (index < 0 || index >= stack.length) return;
    _router?.go(stack[index].pathname);
  }

  void popToIndex(int index) {
    final stack = NavigationStackStore.instance.getStack();
    if (index < 0 || index >= stack.length) return;
    // Navigating to the target route effectively pops everything above it.
    _router?.go(stack[index].pathname);
  }

  void goBack() {
    final router = _router;
    if (router == null) return;
    if (router.canPop()) router.pop();
  }

  void popToTop() {
    final stack = NavigationStackStore.instance.getStack();
    if (stack.isEmpty) return;
    _router?.go(stack.first.pathname);
  }

  // ── Sitemap ──────────────────────────────────────────────────────────────

  /// The parsed route tree (RN RouteInfo shape). Empty when no go_router.
  List<RouteInfo> sitemap() {
    final router = _router;
    if (router == null) return const [];
    return RouteInfo.fromGoRoutes(router.configuration.routes);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _clean(String location) {
    if (location.isEmpty) return '/';
    // Strip a query string for the pathname (RN pathname excludes params).
    final q = location.indexOf('?');
    final path = q >= 0 ? location.substring(0, q) : location;
    return path.isEmpty ? '/' : path;
  }

  static List<String> _segmentsOf(String pathname) {
    return pathname.split('/').where((s) => s.isNotEmpty).toList();
  }

  /// Best-effort per-route params: match `:name` tokens in the route template
  /// against the concrete matched location (exact for flat routers).
  static Map<String, Object?> _extractPathParams(
    String template,
    String location,
  ) {
    final tTokens = template.split('/').where((t) => t.isNotEmpty).toList();
    final lTokens =
        _clean(location).split('/').where((t) => t.isNotEmpty).toList();
    if (tTokens.length != lTokens.length) return const {};
    final params = <String, Object?>{};
    for (var i = 0; i < tTokens.length; i++) {
      final t = tTokens[i];
      if (t.startsWith(':')) {
        var name = t.substring(1);
        final paren = name.indexOf('(');
        if (paren >= 0) name = name.substring(0, paren);
        params[name] = lTokens[i];
      }
    }
    return params;
  }
}
