# Buoy Network Inspector for Flutter

**See every HTTP request your Flutter app makes — in the app, on your desktop, and from your AI editor.**

Buoy captures all `dart:io` traffic in one hook: `package:http`, dio, `Image.network`, cached images, GraphQL clients. Inspect requests in a floating in-app panel, stream them live to the [Buoy Desktop](https://buoy.gg) dashboard, or query them from your editor via the Buoy MCP server.

> **Beta** — the network inspector is the first Buoy tool on Flutter. The full [React Native suite](https://buoy.gg) is coming to Flutter tool by tool; vote for what's next on the [roadmap](https://buoy.gg/roadmap).

## Install

```sh
flutter pub add buoy_network
```

## Quick start

```dart
import 'package:buoy_network/buoy_network.dart';

void main() {
  if (kDebugMode) registerBuoyNetwork();   // capture + tool registration
  runApp(const MyApp());
}

// In your MaterialApp:
builder: (context, child) => BuoyDevTools(
  deviceName: 'My App',
  child: child ?? const SizedBox.shrink(),
),
```

That's it — `registerBuoyNetwork()` installs the HTTP hook and registers the tool; `BuoyDevTools` mounts the in-app panel and auto-connects to Buoy Desktop. (Or use the [`buoy`](https://pub.dev/packages/buoy) umbrella and skip even the register call.)

## What gets captured

Everything that rides `dart:io`'s `HttpClient`: `package:http`, dio (attributed separately), Flutter's own image loading, `cached_network_image` misses, graphql_flutter/ferry. Request/response headers and bodies, timing, status, errors — with GraphQL operation names when tagged via `X-Request-Client: graphql`.

Known gaps (documented, by design): `cupertino_http`/`cronet_http` native clients, gRPC, secondary isolates, Flutter web.

## Buoy Desktop

The [desktop dashboard](https://buoy.gg) shows live traffic from every connected device — simulators connect automatically (`localhost`), physical devices take a `socketUrl`. The same connection powers the Buoy MCP server, so your AI editor can read your app's traffic.

---

📚 [Docs](https://buoy.gg) · [Roadmap](https://buoy.gg/roadmap) · [React Native version](https://github.com/Buoy-gg/buoy)

Proprietary software. © Buoy LLC. [Terms](https://buoy.gg/terms)
