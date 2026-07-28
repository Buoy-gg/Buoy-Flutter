/// Ports packages/perf-monitor/src/perf-monitor/types/index.ts.
///
/// Every wire-facing type mirrors the RN interface field-for-field so the
/// desktop panels + MCP server read a byte-compatible payload. The RN-only
/// extras that don't map to Flutter (`reaFps`, `synthetic`, `renders`,
/// `environmentSignals`) are omitted per the spike's parity table — every
/// downstream consumer already tolerates their absence.
library;

/// Built-in color thresholds (RN `PERF_THRESHOLDS`).
///  - fpsGoodPct — value ≥ this fraction of device max refresh is green.
///  - fpsWarnPct — value ≥ this fraction is amber rather than red.
///  - cpuGoodMax — CPU% ≤ this is green.
///  - cpuWarnMax — CPU% ≤ this is amber rather than red.
class PerfThresholds {
  const PerfThresholds._();
  static const double fpsGoodPct = 0.9;
  static const double fpsWarnPct = 0.66;
  static const double cpuGoodMax = 40;
  static const double cpuWarnMax = 70;
}

double _num(Object? v, [double fallback = 0]) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : fallback;
  }
  return fallback;
}

int _int(Object? v, [int fallback = 0]) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d.round() : fallback;
  }
  return fallback;
}

/// One sample of performance metrics taken at a point in time
/// (RN `PerfSample`). `active` is Flutter-internal (NOT serialized): false for
/// idle ticks where no frames were produced, so the HUD can dash FPS and the
/// jank math can skip them — it keeps the wire shape identical to RN.
class PerfSample {
  const PerfSample({
    required this.timestamp,
    required this.jsFps,
    required this.uiFps,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.deviceMaxRefreshRate,
    this.active = true,
  });

  /// Wall-clock timestamp (ms since epoch).
  final int timestamp;

  /// Frames-per-second on the Dart UI thread (RN `jsFps`).
  final double jsFps;

  /// Delivered frame rate (RN `uiFps`).
  final double uiFps;

  /// Process CPU usage 0–100 (Android only; 0 on iOS).
  final double cpuUsage;

  /// Resident process memory in MB.
  final double memoryUsage;

  /// Device max refresh rate at sample time (e.g. 60, 120).
  final double deviceMaxRefreshRate;

  /// Flutter-internal: whether frames were actually produced this tick.
  final bool active;

  /// Wire shape — matches RN `PerfSample` (no `active` field).
  Map<String, Object?> toJson() => {
        'timestamp': timestamp,
        'jsFps': jsFps,
        'uiFps': uiFps,
        'cpuUsage': cpuUsage,
        'memoryUsage': memoryUsage,
        'deviceMaxRefreshRate': deviceMaxRefreshRate,
      };

  static PerfSample fromJson(Map<String, Object?> json) => PerfSample(
        timestamp: _int(json['timestamp']),
        jsFps: _num(json['jsFps']),
        uiFps: _num(json['uiFps']),
        cpuUsage: _num(json['cpuUsage']),
        memoryUsage: _num(json['memoryUsage']),
        deviceMaxRefreshRate: _num(json['deviceMaxRefreshRate'], 60),
      );
}

/// Min/max/avg/p95 for a single metric channel (RN `AggregateChannel`).
class AggregateChannel {
  const AggregateChannel({
    required this.min,
    required this.max,
    required this.avg,
    required this.p95,
  });

  final double min;
  final double max;
  final double avg;
  final double p95;

  static const AggregateChannel empty =
      AggregateChannel(min: 0, max: 0, avg: 0, p95: 0);

  Map<String, Object?> toJson() => {
        'min': min,
        'max': max,
        'avg': avg,
        'p95': p95,
      };

  static AggregateChannel fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final json = raw.cast<String, Object?>();
    return AggregateChannel(
      min: _num(json['min']),
      max: _num(json['max']),
      avg: _num(json['avg']),
      p95: _num(json['p95']),
    );
  }
}

/// Aggregated stats over a recording window (RN `PerfStatsAggregate`).
class PerfStatsAggregate {
  const PerfStatsAggregate({
    required this.sampleCount,
    required this.durationMs,
    required this.jsFps,
    required this.uiFps,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.jsJankFrames,
    required this.uiJankFrames,
    required this.deviceMaxRefreshRate,
  });

  final int sampleCount;
  final int durationMs;
  final AggregateChannel jsFps;
  final AggregateChannel uiFps;
  final AggregateChannel cpuUsage;
  final AggregateChannel memoryUsage;
  final int jsJankFrames;
  final int uiJankFrames;
  final double deviceMaxRefreshRate;

  Map<String, Object?> toJson() => {
        'sampleCount': sampleCount,
        'durationMs': durationMs,
        'jsFps': jsFps.toJson(),
        'uiFps': uiFps.toJson(),
        'cpuUsage': cpuUsage.toJson(),
        'memoryUsage': memoryUsage.toJson(),
        'jsJankFrames': jsJankFrames,
        'uiJankFrames': uiJankFrames,
        'deviceMaxRefreshRate': deviceMaxRefreshRate,
      };

  static PerfStatsAggregate fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final json = raw.cast<String, Object?>();
    return PerfStatsAggregate(
      sampleCount: _int(json['sampleCount']),
      durationMs: _int(json['durationMs']),
      jsFps: AggregateChannel.fromJson(json['jsFps']),
      uiFps: AggregateChannel.fromJson(json['uiFps']),
      cpuUsage: AggregateChannel.fromJson(json['cpuUsage']),
      memoryUsage: AggregateChannel.fromJson(json['memoryUsage']),
      jsJankFrames: _int(json['jsJankFrames']),
      uiJankFrames: _int(json['uiJankFrames']),
      deviceMaxRefreshRate: _num(json['deviceMaxRefreshRate'], 60),
    );
  }

  static const PerfStatsAggregate empty = PerfStatsAggregate(
    sampleCount: 0,
    durationMs: 0,
    jsFps: AggregateChannel.empty,
    uiFps: AggregateChannel.empty,
    cpuUsage: AggregateChannel.empty,
    memoryUsage: AggregateChannel.empty,
    jsJankFrames: 0,
    uiJankFrames: 0,
    deviceMaxRefreshRate: 60,
  );
}

/// A user-dropped marker captured during a recording (RN `BenchmarkMarker`).
class BenchmarkMarker {
  const BenchmarkMarker({required this.timestamp, this.label});

  final int timestamp;
  final String? label;

  Map<String, Object?> toJson() => {
        'timestamp': timestamp,
        if (label != null) 'label': label,
      };

  static BenchmarkMarker fromJson(Map<String, Object?> json) => BenchmarkMarker(
        timestamp: _int(json['timestamp']),
        label: json['label'] is String ? json['label'] as String : null,
      );
}

/// Metadata stored with a saved benchmark session (RN `BenchmarkMetadata`).
class BenchmarkMetadata {
  const BenchmarkMetadata({
    required this.name,
    this.notes,
    this.tags,
    this.route,
    this.source,
    this.batchId,
    this.batchIndex,
    this.batchFailureReason,
    this.params,
    this.runIndex,
    this.caseId,
    this.isMedianRun,
    this.retriedOnce,
  });

  /// Free-form label entered by the user.
  final String name;
  final String? notes;
  final List<String>? tags;

  /// Route auto-captured at recording start (from buoy_routes).
  final String? route;

  /// "manual" | "batch". Absent on legacy reports — treat as manual.
  final String? source;
  final String? batchId;
  final int? batchIndex;
  final String? batchFailureReason;
  final Map<String, String>? params;
  final int? runIndex;
  final String? caseId;
  final bool? isMedianRun;
  final bool? retriedOnce;

  BenchmarkMetadata copyWith({
    String? name,
    bool? isMedianRun,
  }) =>
      BenchmarkMetadata(
        name: name ?? this.name,
        notes: notes,
        tags: tags,
        route: route,
        source: source,
        batchId: batchId,
        batchIndex: batchIndex,
        batchFailureReason: batchFailureReason,
        params: params,
        runIndex: runIndex,
        caseId: caseId,
        isMedianRun: isMedianRun ?? this.isMedianRun,
        retriedOnce: retriedOnce,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        if (notes != null) 'notes': notes,
        if (tags != null) 'tags': tags,
        if (route != null) 'route': route,
        if (source != null) 'source': source,
        if (batchId != null) 'batchId': batchId,
        if (batchIndex != null) 'batchIndex': batchIndex,
        if (batchFailureReason != null)
          'batchFailureReason': batchFailureReason,
        if (params != null) 'params': params,
        if (runIndex != null) 'runIndex': runIndex,
        if (caseId != null) 'caseId': caseId,
        if (isMedianRun != null) 'isMedianRun': isMedianRun,
        if (retriedOnce != null) 'retriedOnce': retriedOnce,
      };

  static BenchmarkMetadata fromJson(Object? raw) {
    if (raw is! Map) return const BenchmarkMetadata(name: 'Untitled run');
    final json = raw.cast<String, Object?>();
    final rawParams = json['params'];
    return BenchmarkMetadata(
      name: json['name'] is String ? json['name'] as String : 'Untitled run',
      notes: json['notes'] is String ? json['notes'] as String : null,
      tags: json['tags'] is List
          ? [
              for (final t in json['tags'] as List)
                if (t is String) t,
            ]
          : null,
      route: json['route'] is String ? json['route'] as String : null,
      source: json['source'] is String ? json['source'] as String : null,
      batchId: json['batchId'] is String ? json['batchId'] as String : null,
      batchIndex: json['batchIndex'] is num
          ? (json['batchIndex'] as num).toInt()
          : null,
      batchFailureReason: json['batchFailureReason'] is String
          ? json['batchFailureReason'] as String
          : null,
      params: rawParams is Map
          ? {
              for (final e in rawParams.entries)
                e.key.toString(): '${e.value ?? ''}',
            }
          : null,
      runIndex:
          json['runIndex'] is num ? (json['runIndex'] as num).toInt() : null,
      caseId: json['caseId'] is String ? json['caseId'] as String : null,
      isMedianRun: json['isMedianRun'] is bool
          ? json['isMedianRun'] as bool
          : null,
      retriedOnce:
          json['retriedOnce'] is bool ? json['retriedOnce'] as bool : null,
    );
  }
}

/// Diagnostic row embedded in a report (RN `PerfDiagnostic`).
class PerfDiagnostic {
  const PerfDiagnostic({
    required this.id,
    required this.severity,
    required this.label,
    required this.detail,
    this.hint,
  });

  final String id;

  /// 'ok' | 'warn' | 'fail' | 'skip'. `fail` triggers the red banner.
  final String severity;
  final String label;
  final String detail;
  final String? hint;

  Map<String, Object?> toJson() => {
        'id': id,
        'severity': severity,
        'label': label,
        'detail': detail,
        if (hint != null) 'hint': hint,
      };

  static PerfDiagnostic fromJson(Map<String, Object?> json) => PerfDiagnostic(
        id: '${json['id'] ?? ''}',
        severity: '${json['severity'] ?? 'ok'}',
        label: '${json['label'] ?? ''}',
        detail: '${json['detail'] ?? ''}',
        hint: json['hint'] is String ? json['hint'] as String : null,
      );
}

/// A persisted benchmark session result (RN `BenchmarkReport`).
class BenchmarkReport {
  const BenchmarkReport({
    required this.id,
    required this.createdAt,
    required this.metadata,
    required this.samples,
    required this.stats,
    this.markers = const [],
    this.diagnostics,
  });

  final String id;
  final int createdAt;
  final BenchmarkMetadata metadata;
  final List<PerfSample> samples;
  final List<BenchmarkMarker> markers;
  final PerfStatsAggregate stats;
  final List<PerfDiagnostic>? diagnostics;

  BenchmarkReport copyWith({BenchmarkMetadata? metadata}) => BenchmarkReport(
        id: id,
        createdAt: createdAt,
        metadata: metadata ?? this.metadata,
        samples: samples,
        markers: markers,
        stats: stats,
        diagnostics: diagnostics,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'metadata': metadata.toJson(),
        'samples': [for (final s in samples) s.toJson()],
        'markers': [for (final m in markers) m.toJson()],
        'stats': stats.toJson(),
        if (diagnostics != null)
          'diagnostics': [for (final d in diagnostics!) d.toJson()],
      };

  static BenchmarkReport? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, Object?>();
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return BenchmarkReport(
      id: id,
      createdAt: _int(json['createdAt']),
      metadata: BenchmarkMetadata.fromJson(json['metadata']),
      samples: [
        if (json['samples'] is List)
          for (final s in json['samples'] as List)
            if (s is Map) PerfSample.fromJson(s.cast<String, Object?>()),
      ],
      markers: [
        if (json['markers'] is List)
          for (final m in json['markers'] as List)
            if (m is Map) BenchmarkMarker.fromJson(m.cast<String, Object?>()),
      ],
      stats: PerfStatsAggregate.fromJson(json['stats']),
      diagnostics: json['diagnostics'] is List
          ? [
              for (final d in json['diagnostics'] as List)
                if (d is Map) PerfDiagnostic.fromJson(d.cast<String, Object?>()),
            ]
          : null,
    );
  }
}

/// Per-metric mean + sample-stddev across a case's runs (RN
/// `PerCaseAggregate["spread"]`).
class MeanStddev {
  const MeanStddev({required this.mean, required this.stddev});
  final double mean;
  final double stddev;
  static const MeanStddev zero = MeanStddev(mean: 0, stddev: 0);
}

class RunSpread {
  const RunSpread({
    required this.jsFps,
    required this.uiFps,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.jsJankFrames,
    required this.uiJankFrames,
  });

  final MeanStddev jsFps;
  final MeanStddev uiFps;
  final MeanStddev cpuUsage;
  final MeanStddev memoryUsage;
  final MeanStddev jsJankFrames;
  final MeanStddev uiJankFrames;
}

/// One row in an automation batch (RN `AutomationCase`).
class AutomationCase {
  AutomationCase({
    required this.id,
    required this.name,
    Map<String, String>? params,
    this.route,
  }) : params = params ?? {};

  /// Editor-stable id (random per session, never persisted as meaningful).
  final String id;
  String name;
  Map<String, String> params;

  /// Optional override; falls back to [AutomationConfig.targetRoute].
  String? route;

  AutomationCase copy({String? id, String? name}) => AutomationCase(
        id: id ?? this.id,
        name: name ?? this.name,
        params: {...params},
        route: route,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'params': params,
        if (route != null) 'route': route,
      };
}

/// Persisted-and-restored configuration for an automation batch
/// (RN `AutomationConfig`).
class AutomationConfig {
  const AutomationConfig({
    required this.targetRoute,
    required this.bounceRoute,
    required this.perCaseDurationMs,
    required this.settleMs,
    required this.navTimeoutMs,
    required this.cases,
    this.reloadBetweenCases = false,
    this.reloadStrategy = 'auto',
    this.postReloadSettleMs,
    this.runsPerCase = 3,
    this.coolDownMs = 8000,
    this.discardWarmupRuns = 0,
    this.shuffleCases = true,
    this.captureRenders = true,
  });

  final String targetRoute;
  final String bounceRoute;
  final int perCaseDurationMs;
  final int settleMs;
  final int navTimeoutMs;
  final List<AutomationCase> cases;

  /// **Flutter deviation:** always false — Dart can't reload its realm the way
  /// RN's `DevSettings.reload()` does. Accepted-and-ignored so a config saved
  /// by the desktop/MCP round-trips unchanged.
  final bool reloadBetweenCases;
  final String reloadStrategy;
  final int? postReloadSettleMs;
  final int runsPerCase;
  final int coolDownMs;
  final int discardWarmupRuns;
  final bool shuffleCases;

  /// Accepted-and-ignored (no Flutter render-commit profiler yet).
  final bool captureRenders;

  AutomationConfig copyWith({
    String? targetRoute,
    String? bounceRoute,
    int? perCaseDurationMs,
    int? settleMs,
    int? navTimeoutMs,
    List<AutomationCase>? cases,
    bool? reloadBetweenCases,
    String? reloadStrategy,
    int? postReloadSettleMs,
    bool clearPostReloadSettleMs = false,
    int? runsPerCase,
    int? coolDownMs,
    int? discardWarmupRuns,
    bool? shuffleCases,
    bool? captureRenders,
  }) =>
      AutomationConfig(
        targetRoute: targetRoute ?? this.targetRoute,
        bounceRoute: bounceRoute ?? this.bounceRoute,
        perCaseDurationMs: perCaseDurationMs ?? this.perCaseDurationMs,
        settleMs: settleMs ?? this.settleMs,
        navTimeoutMs: navTimeoutMs ?? this.navTimeoutMs,
        cases: cases ?? this.cases,
        reloadBetweenCases: reloadBetweenCases ?? this.reloadBetweenCases,
        reloadStrategy: reloadStrategy ?? this.reloadStrategy,
        postReloadSettleMs: clearPostReloadSettleMs
            ? null
            : (postReloadSettleMs ?? this.postReloadSettleMs),
        runsPerCase: runsPerCase ?? this.runsPerCase,
        coolDownMs: coolDownMs ?? this.coolDownMs,
        discardWarmupRuns: discardWarmupRuns ?? this.discardWarmupRuns,
        shuffleCases: shuffleCases ?? this.shuffleCases,
        captureRenders: captureRenders ?? this.captureRenders,
      );

  /// Full wire shape. [includeCases] false mirrors the RN sync adapter, which
  /// strips `cases` from every snapshot tick.
  Map<String, Object?> toJson({bool includeCases = true}) => {
        'targetRoute': targetRoute,
        'bounceRoute': bounceRoute,
        'perCaseDurationMs': perCaseDurationMs,
        'settleMs': settleMs,
        'navTimeoutMs': navTimeoutMs,
        if (includeCases) 'cases': [for (final c in cases) c.toJson()],
        'reloadBetweenCases': reloadBetweenCases,
        'reloadStrategy': reloadStrategy,
        if (postReloadSettleMs != null)
          'postReloadSettleMs': postReloadSettleMs,
        'runsPerCase': runsPerCase,
        'coolDownMs': coolDownMs,
        'discardWarmupRuns': discardWarmupRuns,
        'shuffleCases': shuffleCases,
        'captureRenders': captureRenders,
      };
}

/// Cross-reload state for a batch in flight (RN `PendingBatchState`). Flutter
/// forces `reloadBetweenCases: false`, so this is only ever written when a
/// resume path is exercised — kept for wire/storage parity.
class PendingBatchState {
  const PendingBatchState({
    required this.batchId,
    required this.config,
    required this.startedAt,
    required this.nextIndex,
    required this.completedReportIds,
    required this.failures,
    required this.resumeCount,
    this.lastReloadAt,
    this.nextRunIndex,
    this.perCaseReportIds,
  });

  final String batchId;
  final AutomationConfig config;
  final int startedAt;
  final int nextIndex;
  final List<String> completedReportIds;
  final List<({int index, String reason})> failures;
  final int resumeCount;
  final int? lastReloadAt;
  final int? nextRunIndex;
  final Map<String, List<String>>? perCaseReportIds;

  Map<String, Object?> toJson() => {
        'batchId': batchId,
        'config': config.toJson(),
        'startedAt': startedAt,
        'nextIndex': nextIndex,
        'completedReportIds': completedReportIds,
        'failures': [
          for (final f in failures) {'index': f.index, 'reason': f.reason},
        ],
        'resumeCount': resumeCount,
        if (lastReloadAt != null) 'lastReloadAt': lastReloadAt,
        if (nextRunIndex != null) 'nextRunIndex': nextRunIndex,
        if (perCaseReportIds != null) 'perCaseReportIds': perCaseReportIds,
      };
}

/// Live status emitted by the automation runner (RN `AutomationStatus`).
/// Phase strings are the RN union verbatim: `idle | navigating-bounce |
/// navigating-target | settling | recording | saving | cooling-down |
/// reloading | done | cancelled`.
class AutomationStatus {
  const AutomationStatus({
    required this.phase,
    this.index,
    this.total,
    this.caseName,
    this.runIndex,
    this.runTotal,
    this.remainingMs,
    this.batchId,
    this.reportIds,
    this.failures,
  });

  final String phase;
  final int? index;
  final int? total;
  final String? caseName;
  final int? runIndex;
  final int? runTotal;
  final int? remainingMs;
  final String? batchId;
  final List<String>? reportIds;
  final List<({int index, String reason})>? failures;

  static const AutomationStatus idle = AutomationStatus(phase: 'idle');

  bool get isActive =>
      phase != 'idle' && phase != 'done' && phase != 'cancelled';

  Map<String, Object?> toJson() => {
        'phase': phase,
        if (index != null) 'index': index,
        if (total != null) 'total': total,
        if (caseName != null) 'caseName': caseName,
        if (runIndex != null) 'runIndex': runIndex,
        if (runTotal != null) 'runTotal': runTotal,
        if (remainingMs != null) 'remainingMs': remainingMs,
        if (batchId != null) 'batchId': batchId,
        if (reportIds != null) 'reportIds': reportIds,
        if (failures != null)
          'failures': [
            for (final f in failures!) {'index': f.index, 'reason': f.reason},
          ],
      };
}

/// Active data source (RN `PerfMode`). Flutter always reports `native` — it has
/// real RSS + a real delivered-frame-rate, so desktop consumers treat CPU/mem
/// as real (not the web `js-fallback` "BUSY" path).
enum PerfMode { native, jsFallback }

extension PerfModeWire on PerfMode {
  String get wire => this == PerfMode.native ? 'native' : 'js-fallback';
}

/// What the active sampler can report (RN `PerfCapabilities`). On Flutter:
/// cpu = Android-only; accurateMemory = true (RSS); trueUiFps = true (delivered
/// frame rate is independent of Dart-thread health); reaFrameCallback = false
/// (no worklet thread).
class PerfCapabilities {
  const PerfCapabilities({
    required this.cpu,
    required this.accurateMemory,
    required this.trueUiFps,
    required this.reaFrameCallback,
  });

  final bool cpu;
  final bool accurateMemory;
  final bool trueUiFps;
  final bool reaFrameCallback;

  Map<String, Object?> toJson() => {
        'cpu': cpu,
        'accurateMemory': accurateMemory,
        'trueUiFps': trueUiFps,
        'reaFrameCallback': reaFrameCallback,
      };
}

/// Snapshot pushed to UI subscribers each tick (RN `PerfSnapshot`).
class PerfSnapshot {
  const PerfSnapshot({
    required this.jsFps,
    required this.uiFps,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.deviceMaxRefreshRate,
    required this.history,
    required this.mode,
    required this.capabilities,
  });

  final double jsFps;
  final double uiFps;
  final double cpuUsage;
  final double memoryUsage;
  final double deviceMaxRefreshRate;
  final List<PerfSample> history;
  final PerfMode mode;
  final PerfCapabilities capabilities;

  Map<String, Object?> toJson() => {
        'jsFps': jsFps,
        'uiFps': uiFps,
        'cpuUsage': cpuUsage,
        'memoryUsage': memoryUsage,
        'deviceMaxRefreshRate': deviceMaxRefreshRate,
        'history': [for (final s in history) s.toJson()],
        'mode': mode.wire,
        'capabilities': capabilities.toJson(),
      };
}

/// Floating HUD layout modes (RN `HudMode`). Tap the chip to toggle.
///
///  - `strip`   the default: route row, four metric cells with sparklines.
///  - `compact` the same cells with no sparklines and no route row — the
///              numbers only, for when the HUD should stay out of the way.
///  - `card`    one rounded card per metric: a tinted identity badge, a large
///              value with a small unit suffix, the window hint, and a smooth
///              glowing line (bars for memory, a beat row for Rec).
///
/// Tapping the chip cycles strip → compact → card → strip.
///
/// The legacy `pill` / `full` modes were removed; a persisted value for either
/// migrates to [strip] rather than stranding the HUD in a mode that no longer
/// renders.
enum HudMode { strip, compact, card }

extension HudModeWire on HudMode {
  String get wire => name;
  static HudMode fromWire(Object? v) {
    switch (v) {
      case 'compact':
        return HudMode.compact;
      case 'card':
        return HudMode.card;
      case 'strip':
      default:
        return HudMode.strip;
    }
  }
}

/// Tap order shared by the floating chip and the modal's inline HUD (RN
/// `nextHudMode`): strip → compact → card → strip.
HudMode nextHudMode(HudMode mode) => switch (mode) {
      HudMode.strip => HudMode.compact,
      HudMode.compact => HudMode.card,
      HudMode.card => HudMode.strip,
    };

/// Persisted bubble preferences (RN `HudPreferences`).
class HudPreferences {
  const HudPreferences({
    required this.mode,
    required this.position,
    required this.hidden,
  });

  final HudMode mode;

  /// Last visible on-screen position. `(-1, -1)` = "use default top-right".
  final ({double x, double y}) position;
  final bool hidden;

  static const HudPreferences defaults = HudPreferences(
    mode: HudMode.strip,
    position: (x: -1, y: -1),
    hidden: false,
  );

  HudPreferences copyWith({
    HudMode? mode,
    ({double x, double y})? position,
    bool? hidden,
  }) =>
      HudPreferences(
        mode: mode ?? this.mode,
        position: position ?? this.position,
        hidden: hidden ?? this.hidden,
      );

  Map<String, Object?> toJson() => {
        'mode': mode.wire,
        'position': {'x': position.x, 'y': position.y},
        'hidden': hidden,
      };
}

/// User-tunable behaviors (RN `PerfSettings`). `captureRenders` /
/// `showLiveRenders` / `showReaFps` are accepted-and-ignored (no Flutter
/// analog) so the persisted JSON stays shape-compatible with the RN tool.
class PerfSettings {
  const PerfSettings({
    required this.autoStopOnBackground,
    required this.captureRenders,
    required this.showLiveRenders,
    required this.showJsFps,
    required this.showUiFps,
    required this.showCpu,
    required this.showMem,
    required this.showReaFps,
    required this.windowMs,
    required this.frameBudgetMode,
  });

  final bool autoStopOnBackground;
  final bool captureRenders;
  final bool showLiveRenders;
  final bool showJsFps;
  final bool showUiFps;
  final bool showCpu;
  final bool showMem;
  final bool showReaFps;
  final int windowMs;

  /// 'fps' or 'ms'.
  final String frameBudgetMode;

  static const PerfSettings defaults = PerfSettings(
    autoStopOnBackground: true,
    captureRenders: true,
    showLiveRenders: false,
    showJsFps: true,
    showUiFps: true,
    showCpu: true,
    showMem: true,
    showReaFps: true,
    windowMs: 5000,
    frameBudgetMode: 'fps',
  );

  PerfSettings copyWith({
    bool? autoStopOnBackground,
    bool? captureRenders,
    bool? showLiveRenders,
    bool? showJsFps,
    bool? showUiFps,
    bool? showCpu,
    bool? showMem,
    bool? showReaFps,
    int? windowMs,
    String? frameBudgetMode,
  }) =>
      PerfSettings(
        autoStopOnBackground: autoStopOnBackground ?? this.autoStopOnBackground,
        captureRenders: captureRenders ?? this.captureRenders,
        showLiveRenders: showLiveRenders ?? this.showLiveRenders,
        showJsFps: showJsFps ?? this.showJsFps,
        showUiFps: showUiFps ?? this.showUiFps,
        showCpu: showCpu ?? this.showCpu,
        showMem: showMem ?? this.showMem,
        showReaFps: showReaFps ?? this.showReaFps,
        windowMs: windowMs ?? this.windowMs,
        frameBudgetMode: frameBudgetMode ?? this.frameBudgetMode,
      );

  Map<String, Object?> toJson() => {
        'autoStopOnBackground': autoStopOnBackground,
        'captureRenders': captureRenders,
        'showLiveRenders': showLiveRenders,
        'showJsFps': showJsFps,
        'showUiFps': showUiFps,
        'showCpu': showCpu,
        'showMem': showMem,
        'showReaFps': showReaFps,
        'windowMs': windowMs,
        'frameBudgetMode': frameBudgetMode,
      };
}
