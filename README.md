<div align="center">

# 🛟 Buoy for Flutter

**Devtools that live in your app. And answer to your agent.**

[Docs](https://buoy.gg) · [Quick Start](#-quick-start) · [Tools](#-the-tools) · [Desktop](#-one-live-session-three-ways-in) · [Pricing](https://buoy.gg/pricing)

[![pub version](https://img.shields.io/pub/v/buoy?style=flat-square&labelColor=1c1c1c&color=10B981)](https://pub.dev/packages/buoy)
[![license](https://img.shields.io/badge/license-proprietary-10B981?style=flat-square&labelColor=1c1c1c)](https://buoy.gg/terms)

Buoy is a floating dev menu that ships inside your Flutter app — every request, log, route, and frame, live on the phone, on your desktop, and in Claude or Cursor.

**Every tool is free. Pro unlocks production builds, MCP & unlimited capture.**

**🛟 The React Native version lives at [Buoy-gg/buoy](https://github.com/Buoy-gg/buoy).** Flutter and React Native devices stream to the same [Buoy Desktop](https://buoy.gg) dashboard and the same MCP server.

</div>

- **One widget, zero config** — drop in `BuoyDevTools` once; every Buoy tool you install self-registers and appears in the menu on its own
- **Eleven tools, one session** — network, storage, console, env, routes, images, impersonate, image overlay, events timeline, Riverpod inspector, and a performance monitor
- **Your agent can drive it** — Claude or Cursor reads live runtime state and taps real controls over MCP

---

## ⚡ Quick Start

```sh
flutter pub add buoy
```

```dart
import 'package:buoy/buoy.dart';
import 'package:flutter/material.dart';

MaterialApp(
  home: const HomeScreen(),
  builder: (context, child) => BuoyDevTools(
    deviceName: 'My App',
    child: child ?? const SizedBox.shrink(),
  ),
)
```

That's the whole setup. A floating dev menu appears inside your app.

> [!NOTE]
> Add `buoy` for the full suite, or install individual tool packages (e.g. `buoy_network`) à la carte — each self-registers into the menu. Every tool is free, no key or signup needed. Add a `licenseKey` prop to unlock [Pro](https://buoy.gg/pricing): production builds, the MCP server, and unlimited capture. On a physical device, pass `socketUrl` to reach your desktop broker.

---

## 🛟 One live session. Three ways in.

Every tool runs inside your app's process. The phone, the desktop, and your agent all see the same session, live.

- **📱 On the phone** — tap the floating menu. Works on any device, no cable, no desktop app.
- **🖥️ On the desktop** — [Buoy Desktop](https://buoy.gg) shows every connected device's tools, live, in one dashboard. Flutter and React Native devices sit side by side.
- **🤖 In your AI editor** — the Buoy MCP server lets Claude or Cursor read your app's runtime — network traffic, logs, routes, state — and drive it.

The broker that mirrors to desktop and MCP binds to localhost only — nothing leaves your machine.

---

## 🧰 The tools

| Tool | Package | What it does |
| --- | --- | --- |
| **Network** | [`buoy_network`](https://pub.dev/packages/buoy_network) | Captures all `dart:io` HTTP traffic (`package:http`, `dio`, image loads) via `HttpOverrides`, with an in-app panel. |
| **Storage** | [`buoy_storage`](https://pub.dev/packages/buoy_storage) | Browse and monitor `shared_preferences` (plus optional secure/MMKV seams) with live write monitoring and filters. |
| **Console** | [`buoy_console`](https://pub.dev/packages/buoy_console) | Captures `print`, `debugPrint`, and uncaught errors in a Chrome-DevTools-style Console panel with level filters and search. |
| **Env** | [`buoy_env`](https://pub.dev/packages/buoy_env) | Inspect and validate registered env vars with required-var checks, type detection, status badges, and a health score. |
| **Routes** | [`buoy_routes`](https://pub.dev/packages/buoy_routes) | A live navigation timeline, a jump-to-route sitemap, and a navigation-stack view for `go_router` apps. |
| **Images** | [`buoy_images`](https://pub.dev/packages/buoy_images) | A live registry of every image loaded through `BuoyImage` — cache verdicts, load timings, oversize audits, and a failure log. |
| **Impersonate** | [`buoy_impersonate`](https://pub.dev/packages/buoy_impersonate) | Test your app as any user without logging out — activate an override and read the injected header on-device. |
| **Image Overlay** | [`buoy_image_overlay`](https://pub.dev/packages/buoy_image_overlay) | Pin a design mockup over your running app at adjustable opacity for pixel-perfect UI comparison. |
| **Events** | [`buoy_events`](https://pub.dev/packages/buoy_events) | One chronological timeline aggregating every other tool's events, with source badges, filters, and MCP export. |
| **Riverpod** | [`buoy_riverpod`](https://pub.dev/packages/buoy_riverpod) | Browse every provider's live value and a prev→next write log with tree/split diffs. |
| **Perf Monitor** | [`buoy_perf_monitor`](https://pub.dev/packages/buoy_perf_monitor) | A pure-Dart sampler (FrameTiming FPS/jank + RSS memory) driving a live on-device HUD. Benchmarking is coming. |

Internal building blocks: [`buoy_core`](https://pub.dev/packages/buoy_core) (registry, floating shell, desktop-sync client) and [`buoy_shared_ui`](https://pub.dev/packages/buoy_shared_ui) (shared widgets and stores). The [`buoy`](https://pub.dev/packages/buoy) umbrella pulls in everything.

> [!NOTE]
> The React Native suite has a few tools that aren't on Flutter yet — React Query, Redux, Zustand, highlight-updates, and debug-borders. Vote for what lands next on the [roadmap](https://buoy.gg/roadmap).

---

## 💳 Every tool is free. Pro unlocks the rest.

Every tool is **free** — no key, no signup, no time limit.

**Pro** unlocks production builds, the MCP server, and unlimited capture. Activate with one prop:

```dart
BuoyDevTools(licenseKey: 'YOUR_LICENSE_KEY', child: child ?? const SizedBox.shrink())
```

➡️ [buoy.gg/pricing](https://buoy.gg/pricing)

---

## License

Proprietary software, made source-visible for transparency and debugging. Use in development is free; Pro features require a paid license. © Buoy LLC. All rights reserved. See the [Terms of Service](https://buoy.gg/terms) and [Pricing](https://buoy.gg/pricing).

---

<p align="center"><sub>Every request, log, and frame — on the phone, on your desktop, and in your agent. 🛟</sub></p>
