/// Ports packages/route-events/src/RouteParser.ts (+ the expo-router→RouteInfo
/// read that expoRouterStore.ts feeds it).
///
/// [RouteInfo] is the byte-for-byte JSON shape the RN RouteParser emits — the
/// desktop Routes/Sitemap tab and the MCP `get_routes` tool consume it, so the
/// field names (`path, name, type, params, nodeType, contextKey, isInternal,
/// children, depth`) must match exactly.
///
/// RN reads expo-router's internal RouteNode tree. Flutter has no expo-router;
/// [RouteInfo.fromGoRoutes] introspects `GoRouter.configuration.routes` instead
/// and NORMALIZES go_router `:param` paths to RN bracket notation
/// (`/pokemon/:id` → `/pokemon/[id]`, params `['id']`) so the desktop sitemap
/// renders and its `[param]`→value navigation resolution works unchanged.
library;

import 'package:go_router/go_router.dart';

/// RN RouteType union — serialized to the exact RN strings via [wireName].
enum RouteType {
  static('static'),
  dynamic('dynamic'),
  catchAll('catch-all'),
  // Named `indexRoute` (not `index`) — Enum already defines an `index` getter.
  indexRoute('index'),
  layout('layout'),
  group('group'),
  notFound('not-found');

  const RouteType(this.wireName);

  /// The string the RN adapter emits (`route.type`).
  final String wireName;
}

/// Ports RN `RouteInfo`. All fields serialize to the RN JSON field names.
class RouteInfo {
  const RouteInfo({
    required this.path,
    required this.name,
    required this.type,
    required this.params,
    required this.nodeType,
    required this.contextKey,
    required this.isInternal,
    required this.children,
    required this.depth,
  });

  /// Full path (e.g. "/pokemon/[id]").
  final String path;

  /// Route segment/name (e.g. "[id]").
  final String name;
  final RouteType type;

  /// Dynamic parameter names (e.g. ["id"]).
  final List<String> params;

  /// Original node type (RN `'route' | 'layout' | ...`). Always 'route' or
  /// 'layout' here.
  final String nodeType;
  final String contextKey;
  final bool isInternal;
  final List<RouteInfo> children;

  /// Depth in the route tree (0 = root).
  final int depth;

  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'type': type.wireName,
    'params': params,
    'nodeType': nodeType,
    'contextKey': contextKey,
    'isInternal': isInternal,
    'children': [for (final c in children) c.toJson()],
    'depth': depth,
  };

  /// Build the nested [RouteInfo] tree from a go_router route list (typically
  /// `router.configuration.routes`).
  static List<RouteInfo> fromGoRoutes(List<RouteBase> routes) {
    final result = <RouteInfo>[];
    _traverse(routes, '', result, 0);
    return result;
  }

  static void _traverse(
    List<RouteBase> routes,
    String parentPath,
    List<RouteInfo> out,
    int depth,
  ) {
    for (final route in routes) {
      if (route is GoRoute) {
        final built = _buildPath(route.path, parentPath);
        final params = _extractParams(route.path);
        final info = RouteInfo(
          path: built,
          name: _nameFor(route, built),
          type: _detectType(built, params),
          params: params.map((p) => p.name).toList(),
          nodeType: 'route',
          contextKey: route.name ?? built,
          isInternal: false,
          children: [],
          depth: depth,
        );
        out.add(info);
        _traverse(route.routes, built, info.children, depth + 1);
      } else {
        // ShellRoute / StatefulShellRoute have no path — pass their children
        // through at the same level (go_router shells are pathless layouts).
        _traverse(route.routes, parentPath, out, depth);
      }
    }
  }

  /// Concatenate a (possibly relative) go_router segment onto the parent path,
  /// normalizing `:param`/`*` tokens to RN `[param]`/`[...param]` notation.
  static String _buildPath(String rawSegment, String parentPath) {
    final normalized = _normalizePath(rawSegment);
    if (normalized.startsWith('/')) return _collapse(normalized);
    if (parentPath.isEmpty || parentPath == '/') return _collapse('/$normalized');
    return _collapse('$parentPath/$normalized');
  }

  /// Collapse duplicate/trailing slashes (keep a single leading '/').
  static String _collapse(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '/';
    return '/${parts.join('/')}';
  }

  static String _normalizePath(String rawPath) {
    final tokens = rawPath.split('/').map(_normalizeToken);
    return tokens.join('/');
  }

  static String _normalizeToken(String token) {
    if (token == '*') return '[...splat]';
    if (token.startsWith(':')) {
      final name = _paramName(token);
      final isDeep = token.contains('(') && token.contains('*');
      return isDeep ? '[...$name]' : '[$name]';
    }
    return token;
  }

  static String _paramName(String token) {
    // ':id' or ':id(\d+)' → 'id'
    var name = token.substring(1);
    final paren = name.indexOf('(');
    if (paren >= 0) name = name.substring(0, paren);
    return name;
  }

  static List<({String name, bool deep})> _extractParams(String rawPath) {
    final params = <({String name, bool deep})>[];
    for (final token in rawPath.split('/')) {
      if (token == '*') {
        params.add((name: 'splat', deep: true));
      } else if (token.startsWith(':')) {
        params.add((
          name: _paramName(token),
          deep: token.contains('(') && token.contains('*'),
        ));
      }
    }
    return params;
  }

  static RouteType _detectType(
    String builtPath,
    List<({String name, bool deep})> params,
  ) {
    if (params.any((p) => p.deep)) return RouteType.catchAll;
    if (params.isNotEmpty) return RouteType.dynamic;
    if (builtPath == '/') return RouteType.indexRoute;
    return RouteType.static;
  }

  static String _nameFor(GoRoute route, String builtPath) {
    if (builtPath == '/') return 'index';
    final segs = builtPath.split('/').where((s) => s.isNotEmpty).toList();
    return route.name ?? (segs.isEmpty ? 'index' : segs.last);
  }
}

/// Ports RN `RouteGroup`.
class RouteGroup {
  const RouteGroup({required this.title, this.description, required this.routes});
  final String title;
  final String? description;
  final List<RouteInfo> routes;
}

/// Ports RN `RouteStats`.
class RouteStats {
  const RouteStats({
    required this.total,
    required this.static,
    required this.dynamic,
    required this.catchAll,
    required this.layouts,
    required this.groups,
  });
  final int total;
  final int static;
  final int dynamic;
  final int catchAll;
  final int layouts;
  final int groups;
}

/// Static helpers mirroring RN `RouteParser` (the display/filter/stat pipeline
/// the in-app sitemap runs on the parsed [RouteInfo] tree).
class RouteParser {
  const RouteParser._();

  static List<RouteInfo> flatten(List<RouteInfo> routes) {
    final out = <RouteInfo>[];
    void visit(RouteInfo r) {
      out.add(r);
      r.children.forEach(visit);
    }

    routes.forEach(visit);
    return out;
  }

  /// RN `organizeRoutes`.
  static List<RouteGroup> organizeRoutes(List<RouteInfo> routes) {
    final groups = <RouteGroup>[];
    final flat = flatten(routes);

    // Flatten before grouping, like every other bucket — static/index screens
    // nested under layouts must still be listed, or the stats header counts
    // routes the list never shows. Mirrors the RN fix.
    final staticRoutes = flat
        .where((r) =>
            r.type == RouteType.static || r.type == RouteType.indexRoute)
        .toList();
    final dynamicRoutes = flat
        .where((r) => r.type == RouteType.dynamic || r.type == RouteType.catchAll)
        .toList();
    final layoutRoutes = flat.where((r) => r.type == RouteType.layout).toList();
    final groupedRoutes = flat.where((r) => r.type == RouteType.group).toList();

    if (staticRoutes.isNotEmpty) {
      groups.add(RouteGroup(title: 'Static Routes', routes: staticRoutes));
    }
    if (dynamicRoutes.isNotEmpty) {
      groups.add(RouteGroup(
        title: 'Dynamic Routes',
        description: 'Routes that accept parameters',
        routes: dynamicRoutes,
      ));
    }
    if (layoutRoutes.isNotEmpty) {
      groups.add(RouteGroup(
        title: 'Layouts',
        description: 'Shared UI for nested screens',
        routes: layoutRoutes,
      ));
    }
    if (groupedRoutes.isNotEmpty) {
      groups.add(RouteGroup(title: 'Route Groups', routes: groupedRoutes));
    }
    return groups;
  }

  /// RN `getRouteStats`.
  static RouteStats getRouteStats(List<RouteInfo> routes) {
    final flat = flatten(routes);
    return RouteStats(
      total: flat.length,
      static: flat.where((r) => r.type == RouteType.static).length,
      dynamic: flat.where((r) => r.type == RouteType.dynamic).length,
      catchAll: flat.where((r) => r.type == RouteType.catchAll).length,
      layouts: flat.where((r) => r.type == RouteType.layout).length,
      groups: flat.where((r) => r.type == RouteType.group).length,
    );
  }

  /// RN `filterRoutes` — returns a flat filtered list.
  static List<RouteInfo> filterRoutes(List<RouteInfo> routes, String query) {
    if (query.isEmpty) return routes;
    final q = query.toLowerCase();
    return flatten(routes).where((r) {
      return r.path.toLowerCase().contains(q) ||
          r.name.toLowerCase().contains(q) ||
          r.type.wireName.toLowerCase().contains(q) ||
          r.params.any((p) => p.toLowerCase().contains(q));
    }).toList();
  }

  /// RN `sortRoutes` (default 'path').
  static List<RouteInfo> sortRoutes(List<RouteInfo> routes,
      [String sortBy = 'path']) {
    final sorted = [...routes];
    sorted.sort((a, b) {
      switch (sortBy) {
        case 'type':
          return a.type.wireName.compareTo(b.type.wireName);
        case 'name':
          return a.name.compareTo(b.name);
        case 'path':
        default:
          return a.path.compareTo(b.path);
      }
    });
    return sorted;
  }
}
