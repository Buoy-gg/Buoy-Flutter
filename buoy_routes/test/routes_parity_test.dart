import 'package:buoy_routes/src/route_parser.dart';
import 'package:buoy_routes/src/route_template.dart';
import 'package:buoy_routes/src/routes_capture.dart';
import 'package:buoy_routes/src/routes_sync_adapter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('route template (RN getRouteTemplate)', () {
    test('numeric id collapses to [id]', () {
      expect(getRouteTemplate('/pokemon/42', ['pokemon', '42']),
          '/pokemon/[id]');
    });

    test('uuid collapses to [id]', () {
      expect(
        getRouteTemplate('/u/2b8f1e00-0000-4000-8000-000000000000',
            ['u', '2b8f1e00-0000-4000-8000-000000000000']),
        '/u/[id]',
      );
    });

    test('fully static route returns null', () {
      expect(getRouteTemplate('/settings', ['settings']), isNull);
    });

    test('no segments returns null', () {
      expect(getRouteTemplate('/', const []), isNull);
    });
  });

  group('RouteChangeEvent wire shape', () {
    test('toJson matches RN field names and omits null optionals', () {
      final e = RouteChangeEvent(
        pathname: '/pokemon/pikachu',
        params: const {'id': 'pikachu'},
        segments: const ['pokemon', 'pikachu'],
        timestamp: 1000,
        previousPathname: '/',
        timeSincePrevious: 250,
      );
      expect(e.toJson(), {
        'pathname': '/pokemon/pikachu',
        'params': {'id': 'pikachu'},
        'segments': ['pokemon', 'pikachu'],
        'timestamp': 1000,
        'previousPathname': '/',
        'timeSincePrevious': 250,
      });

      final first = RouteChangeEvent(
        pathname: '/',
        params: const {},
        segments: const [],
        timestamp: 1,
      );
      expect(first.toJson().containsKey('previousPathname'), isFalse);
      expect(first.toJson().containsKey('timeSincePrevious'), isFalse);
    });
  });

  group('stack transitions (RN buildStack)', () {
    test('push sequence marks last focused, canPop above root, indices', () {
      final stack = buildStack(const [
        (key: 'a', name: 'index', pathname: '/', params: {}),
        (key: 'b', name: 'console-demo', pathname: '/console-demo', params: {}),
      ]);
      expect(stack.length, 2);
      expect(stack[0].index, 0);
      expect(stack[0].isFocused, isFalse);
      expect(stack[0].canPop, isFalse);
      expect(stack[1].index, 1);
      expect(stack[1].isFocused, isTrue);
      expect(stack[1].canPop, isTrue);
    });

    test('single-entry stack: root focused, cannot pop', () {
      final stack =
          buildStack(const [(key: 'a', name: 'index', pathname: '/', params: {})]);
      expect(stack.single.isFocused, isTrue);
      expect(stack.single.canPop, isFalse);
    });

    test('empty path normalizes to /', () {
      final stack =
          buildStack(const [(key: 'a', name: 'root', pathname: '', params: {})]);
      expect(stack.single.pathname, '/');
    });

    test('StackDisplayItem.toJson matches RN field names', () {
      final stack = buildStack(const [
        (key: 'k', name: 'pokemon', pathname: '/pokemon/x', params: {'id': 'x'}),
      ]);
      expect(stack.single.toJson(), {
        'key': 'k',
        'name': 'pokemon',
        'pathname': '/pokemon/x',
        'params': {'id': 'x'},
        'isFocused': true,
        'index': 0,
        'canPop': false,
      });
    });
  });

  group('sitemap from go_router tree (RN RouteInfo shape)', () {
    Widget stub(BuildContext c, GoRouterState s) => const SizedBox.shrink();

    test('flat routes: index / dynamic / static classification + params', () {
      final routes = RouteInfo.fromGoRoutes([
        GoRoute(path: '/', builder: stub),
        GoRoute(path: '/pokemon/:id', builder: stub),
        GoRoute(path: '/console-demo', builder: stub),
      ]);

      expect(routes.map((r) => r.path).toList(),
          ['/', '/pokemon/[id]', '/console-demo']);
      expect(routes[0].type, RouteType.indexRoute);
      expect(routes[0].name, 'index');
      expect(routes[1].type, RouteType.dynamic);
      expect(routes[1].params, ['id']);
      expect(routes[2].type, RouteType.static);
      expect(routes[2].name, 'console-demo');
    });

    test('normalizes :param to RN [param] bracket notation', () {
      final routes = RouteInfo.fromGoRoutes([
        GoRoute(path: '/user/:uid/post/:pid', builder: stub),
      ]);
      expect(routes.single.path, '/user/[uid]/post/[pid]');
      expect(routes.single.params, ['uid', 'pid']);
      expect(routes.single.type, RouteType.dynamic);
    });

    test('nested children build full paths and depth', () {
      final routes = RouteInfo.fromGoRoutes([
        GoRoute(
          path: '/a',
          builder: stub,
          routes: [GoRoute(path: 'b', builder: stub)],
        ),
      ]);
      expect(routes.single.path, '/a');
      expect(routes.single.depth, 0);
      expect(routes.single.children.single.path, '/a/b');
      expect(routes.single.children.single.depth, 1);
    });

    test('RouteInfo.toJson carries every RN field', () {
      final info = RouteInfo.fromGoRoutes([
        GoRoute(path: '/pokemon/:id', builder: stub),
      ]).single;
      final json = info.toJson();
      expect(json.keys.toSet(), {
        'path',
        'name',
        'type',
        'params',
        'nodeType',
        'contextKey',
        'isInternal',
        'children',
        'depth',
      });
      expect(json['type'], 'dynamic'); // RN wire string
      expect(json['nodeType'], 'route');
      expect(json['isInternal'], isFalse);
    });

    test('stats + organize groups (RN RouteParser)', () {
      final routes = RouteInfo.fromGoRoutes([
        GoRoute(path: '/', builder: stub),
        GoRoute(path: '/pokemon/:id', builder: stub),
        GoRoute(path: '/console-demo', builder: stub),
      ]);
      final stats = RouteParser.getRouteStats(routes);
      expect(stats.total, 3);
      expect(stats.dynamic, 1);
      expect(stats.static, 1);

      final groups = RouteParser.organizeRoutes(routes);
      expect(groups.any((g) => g.title == 'Root Routes'), isTrue);
      expect(groups.any((g) => g.title == 'Dynamic Routes'), isTrue);
    });
  });

  group('sync adapter (routeEventsSyncAdapter v3)', () {
    test('version + action names match RN', () {
      expect(routeEventsSyncAdapter.version, 3);
      expect(
        routeEventsSyncAdapter.actions.keys.toSet(),
        {
          'clearEvents',
          'navigate',
          'stackNavigateToIndex',
          'stackPopToIndex',
          'stackGoBack',
          'stackPopToTop',
        },
      );
    });

    test('snapshot is {events, sitemap, stack} with RN-shaped members', () {
      RouteEventStore.instance.clearEvents();
      RouteEventStore.instance.record(RouteChangeEvent(
        pathname: '/',
        params: const {},
        segments: const [],
        timestamp: 42,
      ));
      NavigationStackStore.instance.setStack(buildStack(const [
        (key: 'a', name: 'index', pathname: '/', params: {}),
      ]));

      final snap = routeEventsSyncAdapter.getSnapshot() as Map<String, Object?>;
      expect(snap.keys.toSet(), {'events', 'sitemap', 'stack'});

      final events = snap['events'] as List;
      expect(events.first, containsPair('pathname', '/'));

      final sitemap = snap['sitemap'] as Map;
      expect(sitemap.keys.toSet(), {'routes', 'source', 'lastUpdatedAt'});
      expect(sitemap['routes'], isA<List>());
      // No router attached in this unit test → empty routes, null source.
      expect(sitemap['source'], isNull);

      final stack = snap['stack'] as List;
      expect(stack.first, containsPair('isFocused', true));
    });

    test('navigate without a router throws (RN parity)', () {
      final navigate = routeEventsSyncAdapter.actions['navigate']!;
      expect(() => navigate({'path': '/x'}), throwsStateError);
    });

    test('navigate requires a path param', () {
      final navigate = routeEventsSyncAdapter.actions['navigate']!;
      expect(() => navigate(const {}), throwsArgumentError);
    });
  });
}
