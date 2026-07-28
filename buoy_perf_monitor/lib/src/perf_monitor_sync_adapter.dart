/// Ports packages/perf-monitor/src/perf-monitor/sync/perfMonitorSyncAdapter.ts
/// — the FULL adapter (live + recordings + automation).
///
/// toolId `perf-monitor`, **version 1**. Full external parity with the
/// on-device tool:
///  - `index`: the saved-recordings index (small per-run summaries). Full
///    reports are fetched on demand via `loadReport`.
///  - `live`: the device's real-time state — enabled flag + [PerfSnapshot]
///    (FPS/CPU/mem + history) + recording state + pending save + automation.
///  - actions: the RN action set verbatim, so MCP `run_benchmark_batch`,
///    `get_batch_report`, `compare_reports` and `get/set_benchmark_settings`
///    drive a Flutter device with zero server changes.
///
/// `automationCompleted` latches the last terminal batch status STICKILY until
/// `acknowledgeAutomation` — the transient `done` is otherwise coalesced away
/// by the 200 ms snapshot throttle and the desktop would miss the completion.
library;

import 'package:buoy_core/buoy_core.dart';

import 'automation_runner.dart';
import 'automation_settings.dart';
import 'benchmark_recorder.dart';
import 'benchmark_storage.dart';
import 'perf_monitor_controller.dart';
import 'perf_types.dart';

/// Cached index — re-read on every index change so `getSnapshot` stays sync.
List<BenchmarkIndexEntry> _cachedIndex = const [];

/// A stopped-but-unsaved recording held so the desktop can prompt for a name
/// (mirrors the on-device inline stop→name→save flow).
BenchmarkReport? _pendingReport;

/// onChange captured from `subscribe`, so an action that mutates state
/// `getSnapshot` reads can push a fresh snapshot.
void Function()? _notify;

/// Last terminal automation status (done / cancelled), held sticky until the
/// desktop acknowledges it.
AutomationStatus? _lastCompletedAutomation;

Future<void> _refreshIndex() async {
  try {
    _cachedIndex = await BenchmarkStorage.list();
  } catch (_) {
    // Keep the last known index; a later refresh retries.
  }
}

/// Start a manual recording on the device, auto-named from the current route
/// + time (RN `startManualRecording`).
BenchmarkMetadata buildManualMetadata(String? route) {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final time = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  final label = (route != null && route.isNotEmpty) ? route : 'Manual run';
  return BenchmarkMetadata(
    name: '$label · $time',
    route: (route != null && route.isNotEmpty) ? route : null,
    source: 'manual',
  );
}

/// The perf-monitor sync adapter.
final ToolSyncAdapter perfMonitorSyncAdapter = ToolSyncAdapter(
  version: 1,
  getSnapshot: () {
    final c = PerfMonitorController.instance;
    final pending = _pendingReport;
    return {
      'index': [for (final e in _cachedIndex) e.toJson()],
      // The device's saved benchmark settings so a remote driver can read and
      // show them in plain English. `cases` are omitted: they're the user's
      // last case list, irrelevant to a driver that supplies its own matrix,
      // and would bloat every snapshot tick.
      'automationConfig':
          AutomationConfigStore.instance.current.toJson(includeCases: false),
      'live': {
        // "enabled" = "is the device sampling for this desktop tool" — HUD on
        // OR desktop silent sampling. The desktop lights its own HUD off this.
        'enabled': c.isEnabled() || c.isRemoteSampling(),
        'isRecording': benchmarkRecorder.isRecording(),
        'startedAt': benchmarkRecorder.getStartedAt(),
        'snapshot': c.getSnapshot().toJson(),
        'pendingSave': pending == null
            ? null
            : {
                'defaultName': pending.metadata.name,
                'sampleCount': pending.samples.length,
              },
        'automation': automationRunner.getStatus().toJson(),
        'automationCompleted': _lastCompletedAutomation?.toJson(),
      },
    };
  },
  subscribe: (onChange) {
    _notify = onChange;
    final c = PerfMonitorController.instance;
    // Recordings index (save / delete / clear).
    final unsubIndex = subscribeBenchmarkIndex(() {
      _refreshIndex().then((_) => onChange());
    });
    // Live metrics (250 ms tick while enabled) + enabled flag + recording.
    final unsubSnapshot = c.subscribe((_) => onChange());
    final unsubEnabled = c.subscribeEnabled((_) => onChange());
    final unsubRecording = benchmarkRecorder.subscribe((_) => onChange());
    // Automation phase transitions; latch terminal states so getSnapshot can
    // report them stickily.
    final unsubAutomation = automationRunner.subscribe((status) {
      if (status.phase == 'done' || status.phase == 'cancelled') {
        _lastCompletedAutomation = status;
      }
      onChange();
    });
    final unsubConfig =
        AutomationConfigStore.instance.subscribe((_) => onChange());
    // Prime the caches for the first snapshot.
    _refreshIndex().then((_) => onChange());
    AutomationConfigStore.instance.load().then((_) => onChange());
    return () {
      _notify = null;
      unsubIndex();
      unsubSnapshot();
      unsubEnabled();
      unsubRecording();
      unsubAutomation();
      unsubConfig();
    };
  },
  actions: {
    // ── Live monitoring ──────────────────────────────────────────────────
    /// Start/stop SILENT sampling for the desktop tool — streams live metrics
    /// without showing the device's own HUD (RN `setRemoteSampling`).
    'setEnabled': (params) {
      final enabled = params is Map && params['enabled'] == true;
      PerfMonitorController.instance.setRemoteSampling(enabled);
      return null;
    },

    // ── Recording ────────────────────────────────────────────────────────
    /// Start a manual recording on the device (auto-names + captures route).
    'startRecording': (_) {
      if (benchmarkRecorder.isRecording()) return null;
      benchmarkRecorder.start(buildManualMetadata(_currentRouteSafe()));
      _notify?.call();
      return null;
    },

    /// Stop the active recording but DON'T save — hold the report so the
    /// desktop can prompt for a name. Empty recordings are dropped.
    'stopRecording': (_) {
      final report = benchmarkRecorder.stop();
      _pendingReport =
          (report != null && report.samples.isNotEmpty) ? report : null;
      _notify?.call();
      final pending = _pendingReport;
      return pending == null
          ? null
          : {
              'defaultName': pending.metadata.name,
              'sampleCount': pending.samples.length,
            };
    },

    /// Persist the held recording under the desktop-chosen name.
    'savePending': (params) async {
      final report = _pendingReport;
      _pendingReport = null;
      _notify?.call();
      if (report == null) return null;
      final rawName = params is Map ? params['name'] : null;
      final trimmed = rawName is String ? rawName.trim() : '';
      final finalName = trimmed.isNotEmpty ? trimmed : report.metadata.name;
      await benchmarkRecorder.saveReport(
        report.copyWith(metadata: report.metadata.copyWith(name: finalName)),
      );
      return null;
    },

    /// Drop the held recording without saving (desktop prompt cancelled).
    'discardPending': (_) {
      _pendingReport = null;
      _notify?.call();
      return null;
    },

    /// Drop a timeline marker during a recording.
    'mark': (params) {
      final label = params is Map && params['label'] is String
          ? params['label'] as String
          : null;
      benchmarkRecorder.mark(label);
      return null;
    },

    // ── Automation batch (driven from the desktop "Automate" view / MCP) ──
    /// Run a benchmark batch with the driver-authored config. The device owns
    /// navigation + recording + storage; status streams back via
    /// `live.automation`. Fire-and-forget — the promise resolves when the whole
    /// batch finishes, so we deliberately don't await it here.
    'startAutomation': (params) {
      final rawConfig = params is Map ? params['config'] : null;
      if (rawConfig == null) return null;
      final config = sanitizeAutomationConfig(rawConfig);
      automationRunner.start(config).catchError((Object _) {
        // Failures surface through the mirrored status (failures array) and
        // per-run placeholder reports; never leave an unhandled rejection.
        return automationRunner.getStatus();
      });
      return null;
    },

    /// Request cancellation of the in-flight batch.
    'cancelAutomation': (_) {
      automationRunner.cancel();
      return null;
    },

    /// Reset a finished/cancelled batch to idle AND clear the sticky
    /// completion. The desktop calls this once it has landed on the batch
    /// report (and on tool-open, to discard a stale prior completion).
    'acknowledgeAutomation': (_) {
      _lastCompletedAutomation = null;
      automationRunner.acknowledge();
      _notify?.call();
      return null;
    },

    /// Force a fresh read of the index and push it. The desktop calls this on
    /// tool-open so a snapshot primed with an empty index during boot (storage
    /// not ready yet) gets corrected.
    'refreshIndex': (_) async {
      await _refreshIndex();
      _notify?.call();
      return null;
    },

    // ── Saved benchmark settings ─────────────────────────────────────────
    /// Read the device's saved benchmark settings so a driver can default its
    /// runs to the user's tuned profile instead of inventing its own.
    'getAutomationConfig': (_) async {
      await AutomationConfigStore.instance.load();
      return AutomationConfigStore.instance.current.toJson();
    },

    /// Persist benchmark settings on the device (sanitized).
    'setAutomationConfig': (params) async {
      final rawConfig = params is Map ? params['config'] : null;
      if (rawConfig == null) {
        return AutomationConfigStore.instance.current.toJson();
      }
      await AutomationConfigStore.instance
          .save(sanitizeAutomationConfig(rawConfig));
      _notify?.call();
      return AutomationConfigStore.instance.current.toJson();
    },

    // ── Saved-recordings management ──────────────────────────────────────
    /// Fetch a full report (samples + stats) by id.
    'loadReport': (params) async {
      final id = params is Map ? params['id'] : null;
      if (id is! String) return null;
      final report = await BenchmarkStorage.load(id);
      return report?.toJson();
    },

    /// Delete one saved recording; the device re-emits its index.
    'deleteReport': (params) async {
      final id = params is Map ? params['id'] : null;
      if (id is! String) return null;
      await BenchmarkStorage.delete(id);
      return null;
    },

    /// Delete every run in an automation batch.
    'deleteBatch': (params) async {
      final batchId = params is Map ? params['batchId'] : null;
      if (batchId is! String) return 0;
      return BenchmarkStorage.deleteBatch(batchId);
    },

    /// Clear all saved recordings.
    'clearAll': (_) async {
      await BenchmarkStorage.clear();
      return null;
    },
  },
);

/// Current route, or null when buoy_routes isn't wired. Kept behind a helper
/// so the adapter file doesn't hard-depend on the bridge's import order.
String? _currentRouteSafe() {
  try {
    final route = perfCurrentRouteProvider?.call();
    return (route != null && route.isNotEmpty) ? route : null;
  } catch (_) {
    return null;
  }
}

/// Injected by `registerBuoyPerfMonitor` so the adapter can auto-name manual
/// recordings with the current route without importing buoy_routes here.
String Function()? perfCurrentRouteProvider;
