# buoy_impersonate

Buoy user-impersonation tool for Flutter — a 1:1 port of
[`@buoy-gg/impersonate`](https://buoy.gg). Test your app as any user/role without
logging out: search identities, activate an override, and inject the
impersonation header into your HTTP requests. State persists across launches and
mirrors live to Buoy Desktop.

## Usage

```dart
import 'package:buoy_impersonate/buoy_impersonate.dart';

// Register with your app's user search + optional cache-clear callbacks.
registerBuoyImpersonate(
  onSearchUsers: (query) async => api.searchUsers(query), // returns List<ImpersonateUser>
  onClearReactQuery: () => cache.clear(),
);

// Read the injected header from your HTTP client (Flutter has no global fetch
// to patch, so you apply it — e.g. a Dio interceptor):
dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
  options.headers.addAll(BuoyImpersonate.instance.impersonationHeaders);
  handler.next(options);
}));
```

Wrap your app in `BuoyDevTools` (from the `buoy` umbrella) to show the tool in
the floating dial.

## License

Proprietary — see LICENSE.
