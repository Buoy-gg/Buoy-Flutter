# Buoy for Flutter

**Devtools that live in your Flutter app — and stream live to your desktop and your AI editor.**

One dependency wires the whole Buoy suite: a floating in-app devtools menu, the [Buoy Desktop](https://buoy.gg) dashboard connection, and the Buoy MCP server for AI-editor access to your app's runtime.

> **Beta** — the network inspector ships first; more tools are coming from the [React Native suite](https://buoy.gg) tool by tool. Vote for what's next on the [roadmap](https://buoy.gg/roadmap).

## Install

```sh
flutter pub add buoy
```

## Quick start

```dart
import 'package:buoy/buoy.dart';

void main() {
  if (kDebugMode) {
    BuoyHttpOverrides.install();
    BuoySyncClient(
      deviceName: 'My App',
      deviceId: 'my-app',
      platform: Platform.isIOS ? 'ios' : 'android',
      tools: {'network': networkSyncAdapter},
    ).connect();
    NetworkEventStore.instance.subscribe(() {});
  }
  runApp(const MyApp());
}
```

See [`example/`](example/lib/main.dart) for the in-app panel wiring.

## The three surfaces

1. **In your app** — floating bubble → dial → tool panels.
2. **On your desktop** — every device's tools, live, in one dashboard.
3. **In your AI editor** — the Buoy MCP server reads your app's runtime (network traffic today; more as tools land).

---

📚 [Docs](https://buoy.gg) · [Roadmap](https://buoy.gg/roadmap) · [React Native version](https://github.com/Buoy-gg/buoy)

Proprietary software. © Buoy LLC. [Terms](https://buoy.gg/terms)
