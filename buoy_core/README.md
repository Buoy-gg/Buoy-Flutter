# Buoy Core for Flutter

**The foundation of Buoy's in-app devtools for Flutter** — the floating bubble + dial shell, the tool registry, and the sync client that streams tools live to the [Buoy Desktop](https://buoy.gg) dashboard and the Buoy MCP server.

> **Beta** — you usually want a tool package (start with [`buoy_network`](https://pub.dev/packages/buoy_network)) or the [`buoy`](https://pub.dev/packages/buoy) umbrella; both bring `buoy_core` in.

## Install

```sh
flutter pub add buoy_core
```

## What's inside

- **`BuoyDevTools`** — the floating bubble + radial dial shell; wrap your app via `MaterialApp.builder` and register `BuoyTool`s.
- **`BuoySyncClient`** — device-side bridge speaking Buoy's sync protocol to the desktop broker: capabilities handshake, watch/backpressure, throttled snapshots, remote actions.
- **`ToolSyncAdapter`** — the contract any tool implements to sync: `getSnapshot` / `subscribe` / `actions`. Build your own tools with it.
- **`BuoyStorage`** — persisted devtools settings (bubble position, per-tool state).

See [`example/`](example/lib/main.dart) for a custom tool synced to the desktop in ~30 lines.

---

📚 [Docs](https://buoy.gg) · [Roadmap](https://buoy.gg/roadmap) · [React Native version](https://github.com/Buoy-gg/buoy)

Proprietary software. © Buoy LLC. [Terms](https://buoy.gg/terms)
