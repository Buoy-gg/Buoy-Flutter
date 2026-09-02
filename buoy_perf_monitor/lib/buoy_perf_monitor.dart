/// Buoy performance monitor for Flutter.
///
/// A pure-Dart hybrid sampler ([PerfMonitorController]) — FrameTiming FPS/jank
/// (`SchedulerBinding.addTimingsCallback`) + `ProcessInfo.currentRss` memory +
/// Android `/proc` CPU — driving a draggable live HUD (via [BuoyOverlayHost])
/// and a live-monitoring modal, streaming to Buoy Desktop through
/// [perfMonitorSyncAdapter]. Call [registerBuoyPerfMonitor] once (or let the
/// `buoy` umbrella do it). No native code, FFI, or plugins beyond
/// shared_preferences.
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoyOverlayHost, BuoySyncClient, BuoyTool;

export 'src/perf_types.dart';
export 'src/aggregate.dart';
export 'src/fps_derive.dart';
export 'src/windowed_stats.dart';
export 'src/proc_cpu.dart';
export 'src/perf_settings.dart';
export 'src/hud_preferences.dart';
export 'src/perf_monitor_controller.dart';
export 'src/perf_monitor_sync_adapter.dart';

// Benchmarks (recording → storage → reports)
export 'src/benchmark_recorder.dart' show benchmarkRecorder, mark;
export 'src/benchmark_storage.dart'
    show BenchmarkStorage, BenchmarkIndexEntry, subscribeBenchmarkIndex;
export 'src/compute_median_run.dart';
export 'src/aggregate_library.dart';
export 'src/compare_delta.dart';
export 'src/exporters.dart' show formatReportAsMarkdown, formatReportAsJson;

// Automation
export 'src/automation_runner.dart'
    show
        automationRunner,
        applyShuffle,
        shuffleIndices,
        hashStringToU32,
        clampRunsPerCase,
        clampCoolDownMs,
        clampDiscardWarmup,
        withBatchWarmup,
        warmupCaseName,
        isWarmupRun;
export 'src/automation_settings.dart';
export 'src/case_sets.dart';
export 'src/parse_automation_cases.dart';
export 'src/compute_case_labels.dart';
export 'src/route_validation.dart';
export 'src/batch_time_estimate.dart';
export 'src/pending_batch.dart';
export 'src/modal_view_persistence.dart';

export 'src/perf_tool/perf_monitor_modal.dart';
export 'src/perf_tool/perf_sparkline.dart'
    show buildSparklineColumns, SparklineColumns, SparklineScale;
export 'src/perf_tool/perf_card_chart.dart' show kCardBucketCount;
export 'src/perf_tool/perf_hud_body.dart' show kCardBodyHeight;
export 'src/perf_tool/perf_hud_surface.dart' show hudHeightFor;
export 'src/register.dart';
