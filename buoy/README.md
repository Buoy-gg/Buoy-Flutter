# Buoy for Flutter

**Devtools that live in your Flutter app — and stream live to your desktop and your AI editor.**

One dependency wires the whole Buoy suite: a floating in-app devtools menu, the [Buoy Desktop](https://buoy.gg) dashboard connection, and the Buoy MCP server for AI-editor access to your app's runtime.

> **Beta** — eleven tools ship today: network, storage, console, env, routes, images, impersonate, image overlay, events timeline, Riverpod inspector, and a performance monitor. A few from the [React Native suite](https://buoy.gg) (React Query, Redux, Zustand) aren't on Flutter yet. Vote for what's next on the [roadmap](https://buoy.gg/roadmap).

## Install

```sh
flutter pub add buoy
```

## Quick start

```dart
import 'package:buoy/buoy.dart';

MaterialApp(
  builder: (context, child) => BuoyDevTools(
    deviceName: 'My App',
    child: child ?? const SizedBox.shrink(),
  ),
)
```

One widget — that's the whole setup. Every installed Buoy tool self-registers: HTTP capture, the floating in-app menu, live desktop sync, and the MCP server connection. Optional props: `licenseKey` (Pro), `socketUrl` (physical devices), `tools` (your own custom tools).

## The three surfaces

1. **In your app** — floating bubble → dial → tool panels.
2. **On your desktop** — every device's tools, live, in one dashboard.
3. **In your AI editor** — the Buoy MCP server reads your app's runtime: network traffic, logs, routes, state, and more.

---

📚 [Docs](https://buoy.gg) · [Roadmap](https://buoy.gg/roadmap) · [React Native version](https://github.com/Buoy-gg/buoy)

Proprietary software. © Buoy LLC. [Terms](https://buoy.gg/terms)
