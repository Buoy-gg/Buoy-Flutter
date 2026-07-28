# buoy_perf_monitor

Buoy performance monitor for Flutter — a **pure-Dart** hybrid sampler with a live
on-device HUD, streaming to the [Buoy Desktop](https://buoy.gg) dashboard.

- **FPS + jank** from `SchedulerBinding.addTimingsCallback` (build = Dart UI
  thread, raster = GPU thread). FPS is activity-gated: an idle Flutter app
  renders no frames, so the HUD dashes (`—`) at rest — honest, not a fake 60.
- **Memory (RSS)** from `dart:io` `ProcessInfo.currentRss` — flows on a 250 ms
  timer even while the UI is still.
- **CPU** from `/proc/self/stat` on Android; `0` on iOS (no pure-Dart source).

No native libraries, no FFI, no platform channels — only `shared_preferences`
(already a `buoy_core` dependency).

## Usage

The `buoy` umbrella registers this tool automatically. To use it standalone:

```dart
import 'package:buoy_perf_monitor/buoy_perf_monitor.dart';
import 'package:flutter/foundation.dart';

void main() {
  if (kDebugMode) registerBuoyPerfMonitor();
  runApp(const MyApp());
}
```

Open the **PERF** tool from the floating dial to see live metrics; toggle the HUD
overlay on to keep it on top of your app while you navigate.
