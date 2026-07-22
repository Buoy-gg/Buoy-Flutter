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
  if (kDebugMode) {
    BuoyHttpOverrides.install();                    // capture everything
    BuoySyncClient(
      deviceName: 'My App',
      deviceId: 'my-app',
      platform: Platform.isIOS ? 'ios' : 'android',
      tools: {'network': networkSyncAdapter},       // stream to Buoy Desktop
    ).connect();
    NetworkEventStore.instance.subscribe(() {});    // keep in-app panel live
  }
  runApp(const MyApp());
}
```

Mount the in-app panel with `BuoyDevTools` + a `BuoyTool` using `NetworkModal` — see [`example/`](example/lib/main.dart).

## What gets captured

Everything that rides `dart:io`'s `HttpClient`: `package:http`, dio (attributed separately), Flutter's own image loading, `cached_network_image` misses, graphql_flutter/ferry. Request/response headers and bodies, timing, status, errors — with GraphQL operation names when tagged via `X-Request-Client: graphql`.

Known gaps (documented, by design): `cupertino_http`/`cronet_http` native clients, gRPC, secondary isolates, Flutter web.

## Buoy Desktop

The [desktop dashboard](https://buoy.gg) shows live traffic from every connected device — simulators connect automatically (`localhost`), physical devices take a `socketUrl`. The same connection powers the Buoy MCP server, so your AI editor can read your app's traffic.

---

📚 [Docs](https://buoy.gg) · [Roadmap](https://buoy.gg/roadmap) · [React Native version](https://github.com/Buoy-gg/buoy)

Proprietary software. © Buoy LLC. [Terms](https://buoy.gg/terms)
