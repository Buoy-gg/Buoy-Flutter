/// Ports packages/perf-monitor/src/preset.tsx (`perfMonitorPreset` +
/// `perfMonitorModalPreset` + `PERF_MONITOR_ENABLED_COLOR`).
///
/// Registers ONE `perf-monitor` tool with [Buoy] (color #22D3EE, stopwatch
/// BenchmarkIcon → `BuoyIcons.gauge`), whose modal is the live-monitoring view, AND
/// mounts the draggable HUD overlay into [BuoyOverlayHost] (gated on the
/// persisted `hud-enabled` key inside the controller). Also wires the B1 live
/// slice of the sync adapter. Idempotent — safe for the `buoy` umbrella.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';

import 'automation_settings.dart';
import 'case_sets.dart';
import 'perf_monitor_controller.dart';
import 'perf_monitor_sync_adapter.dart';
import 'perf_route_bridge.dart';
import 'perf_settings.dart';
import 'perf_tool/automation_progress_overlay.dart';
import 'perf_tool/perf_hud_overlay.dart';
import 'perf_tool/perf_monitor_modal.dart';

bool _registered = false;

/// RN `PERF_MONITOR_ENABLED_COLOR` (#22D3EE).
const Color kPerfMonitorColor = Color(0xFF22D3EE);

/// One-call setup for the perf-monitor tool: touches the controller singleton
/// (which restores the persisted HUD-enabled flag), mounts the HUD overlay, and
/// registers the tool + B1 sync adapter with [Buoy]. Idempotent.
void registerBuoyPerfMonitor() {
  if (_registered) return;
  _registered = true;

  // Touch the singleton so its constructor kicks off the persisted-enabled
  // restore (if the HUD was on last session it flips back on once storage
  // loads and the overlay picks it up).
  PerfMonitorController.instance;

  // Prime the persisted stores so the modal/HUD render the user's settings on
  // first paint instead of defaults-then-flicker.
  // ignore: discarded_futures
  PerfSettingsStore.instance.load();
  // ignore: discarded_futures
  AutomationConfigStore.instance.load();
  // ignore: discarded_futures
  CaseSetsStore.instance.load();

  // Let the sync adapter auto-name desktop-triggered recordings with the
  // current route without this package's adapter importing buoy_routes.
  perfCurrentRouteProvider = getCurrentRoute;

  // Mount the draggable HUD chip that draws over the app (self-gates on the
  // controller's enabled flag + modal-open suppression).
  BuoyOverlayHost.instance.register((context) => const PerfHudOverlay());

  // The batch-progress pill — visible whenever a batch runs, including while
  // the modal auto-hides itself (RN AutomationProgressOverlay).
  BuoyOverlayHost.instance
      .register((context) => const AutomationProgressOverlay());

  Buoy.registerTool(
    BuoyTool(
      id: 'perf-monitor',
      name: 'PERF',
      description: 'Live FPS / memory HUD + benchmarks',
      color: kPerfMonitorColor,
      // BenchmarkIcon is a stopwatch-with-bars → the speedometer glyph reads as
      // performance measurement.
      icon: (size, _) => BuoyIcon(benchmarkIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) =>
          PerfMonitorModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: perfMonitorSyncAdapter,
  );
}
