## 0.3.0

- Initial release: pure-Dart hybrid performance sampler (Phase B1).
  - FPS + jank from `SchedulerBinding.addTimingsCallback` (build/raster durations).
  - Memory (RSS) from `dart:io` `ProcessInfo.currentRss`, live even at idle.
  - CPU from `/proc/self/stat` on Android; `0` on iOS (no pure-Dart source).
  - Refresh rate learned from `platformDispatcher.displays`.
  - Draggable live HUD (pill / strip / full) via `BuoyOverlayHost`, gated on the
    persisted `hud-enabled` key.
  - Live-monitoring modal + a live-slice desktop sync adapter (`setEnabled`).
- No native code, FFI, or plugins beyond `shared_preferences`.
