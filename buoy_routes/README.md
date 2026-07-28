# buoy_routes

Buoy route inspector for Flutter — a live navigation timeline, a jump-to-route
sitemap, and a navigation-stack view that stream live to
[Buoy Desktop](https://buoy.gg).

Part of the [Buoy](https://buoy.gg) devtools suite. Ports `@buoy-gg/route-events`
1:1: the same events timeline, route sitemap, navigation stack, and sync protocol
(v3 `{events, sitemap, stack}` with remote `navigate`/`stack*` actions).

## Usage

`buoy_routes` captures navigation from [`go_router`](https://pub.dev/packages/go_router).
Add `BuoyRouteObserver.instance` to your router's `observers` and hand the router
to `registerBuoyRoutes` so the sitemap and remote navigation work:

```dart
import 'package:buoy/buoy.dart';
import 'package:go_router/go_router.dart';

final _router = GoRouter(
  observers: [BuoyRouteObserver.instance],
  routes: [ /* ... */ ],
);

void main() {
  if (kDebugMode) registerBuoyRoutes(router: _router);
  runApp(const MyApp());
}
```

When you use the `buoy` umbrella (`BuoyDevTools`), the tool auto-registers for the
in-app dial; you still attach the observer and pass the router as above so the
sitemap, stack, and MCP `navigate` action light up.

Plain-Navigator apps (no go_router) still get the events timeline and stack via
`BuoyRouteObserver`; the sitemap needs go_router.

## License

Proprietary. Free in development; Pro features require a license. See
[buoy.gg/pricing](https://buoy.gg/pricing).
