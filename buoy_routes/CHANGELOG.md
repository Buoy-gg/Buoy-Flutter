## 0.3.0

- Initial release of the Buoy route inspector for Flutter.
- Live navigation timeline: every route change (pathname, params, segments,
  timing, visit count) captured via a go_router delegate listener, with a
  `BuoyRouteObserver` fallback for plain-Navigator apps.
- Jump-to-route sitemap built from `GoRouter.configuration.routes`, normalized
  to the same route-tree shape `@buoy-gg/route-events` renders (static / dynamic
  / catch-all / index / layout / group), with search, stats, and a Home shortcut.
- Navigation-stack view: mounted screens, focused route, and Back / Go / Pop-To
  actions derived from `RouteMatchList`.
- Streams to Buoy Desktop / MCP via the route-events sync adapter (protocol v3,
  `{events, sitemap, stack}`) with remote `navigate` and `stack*` actions,
  matching `@buoy-gg/route-events` field-for-field.
