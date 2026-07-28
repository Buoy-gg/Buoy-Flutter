/// Ports packages/perf-monitor/src/perf-monitor/utils/BenchmarkStorage.ts.
///
/// Persists reports through `shared_preferences` under the RN key namespace
/// (`@react_buoy/perf-monitor/index`, `@react_buoy/perf-monitor/report/<id>`)
/// so the desktop Batches list and MCP `get_batch_report` read the exact same
/// `IndexEntry` shape. Index read-modify-writes are serialized on a mutation
/// chain — RN's fix for "desktop bulk-delete fans out N parallel deletes and
/// only one lands".
///
/// Render-capture mirrors (`renderCommits`/`renderTotalMs`/`topRenderers`) are
/// omitted: Flutter has no React commit profiler (spike parity table); every
/// consumer treats them as optional.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'perf_types.dart';

const String benchmarkIndexKey = '@react_buoy/perf-monitor/index';
const String benchmarkReportPrefix = '@react_buoy/perf-monitor/report/';

String _reportKey(String id) => '$benchmarkReportPrefix$id';

/// The per-run summary that rides in EVERY sync snapshot (RN `IndexEntry`).
/// This — not the full report — is what `rankBatchFromIndex` /
/// `get_batch_report` / the desktop list consume, so every field name is
/// load-bearing.
class BenchmarkIndexEntry {
  const BenchmarkIndexEntry({
    required this.id,
    required this.createdAt,
    required this.name,
    this.route,
    this.durationMs,
    this.sampleCount,
    this.jsFpsAvg,
    this.uiFpsAvg,
    this.cpuAvg,
    this.memMaxMb,
    this.jsJankFrames,
    this.uiJankFrames,
    this.deviceMaxRefreshRate,
    this.source,
    this.batchId,
    this.batchIndex,
    this.batchFailureReason,
    this.params,
    this.caseId,
    this.runIndex,
    this.isMedianRun,
  });

  final String id;
  final int createdAt;
  final String name;
  final String? route;
  final int? durationMs;
  final int? sampleCount;
  final double? jsFpsAvg;
  final double? uiFpsAvg;
  final double? cpuAvg;
  final double? memMaxMb;
  final int? jsJankFrames;
  final int? uiJankFrames;
  final double? deviceMaxRefreshRate;
  final String? source;
  final String? batchId;
  final int? batchIndex;
  final String? batchFailureReason;
  final Map<String, String>? params;
  final String? caseId;
  final int? runIndex;
  final bool? isMedianRun;

  Map<String, Object?> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'name': name,
        if (route != null) 'route': route,
        if (durationMs != null) 'durationMs': durationMs,
        if (sampleCount != null) 'sampleCount': sampleCount,
        if (jsFpsAvg != null) 'jsFpsAvg': jsFpsAvg,
        if (uiFpsAvg != null) 'uiFpsAvg': uiFpsAvg,
        if (cpuAvg != null) 'cpuAvg': cpuAvg,
        if (memMaxMb != null) 'memMaxMb': memMaxMb,
        if (jsJankFrames != null) 'jsJankFrames': jsJankFrames,
        if (uiJankFrames != null) 'uiJankFrames': uiJankFrames,
        if (deviceMaxRefreshRate != null)
          'deviceMaxRefreshRate': deviceMaxRefreshRate,
        if (source != null) 'source': source,
        if (batchId != null) 'batchId': batchId,
        if (batchIndex != null) 'batchIndex': batchIndex,
        if (batchFailureReason != null)
          'batchFailureReason': batchFailureReason,
        if (params != null) 'params': params,
        if (caseId != null) 'caseId': caseId,
        if (runIndex != null) 'runIndex': runIndex,
        if (isMedianRun != null) 'isMedianRun': isMedianRun,
      };

  static BenchmarkIndexEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, Object?>();
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    double? d(Object? v) => v is num && v.toDouble().isFinite
        ? v.toDouble()
        : null;
    int? i(Object? v) => v is num && v.toDouble().isFinite ? v.round() : null;
    final rawParams = json['params'];
    return BenchmarkIndexEntry(
      id: id,
      createdAt: i(json['createdAt']) ?? 0,
      name: json['name'] is String ? json['name'] as String : 'Untitled run',
      route: json['route'] is String ? json['route'] as String : null,
      durationMs: i(json['durationMs']),
      sampleCount: i(json['sampleCount']),
      jsFpsAvg: d(json['jsFpsAvg']),
      uiFpsAvg: d(json['uiFpsAvg']),
      cpuAvg: d(json['cpuAvg']),
      memMaxMb: d(json['memMaxMb']),
      jsJankFrames: i(json['jsJankFrames']),
      uiJankFrames: i(json['uiJankFrames']),
      deviceMaxRefreshRate: d(json['deviceMaxRefreshRate']),
      source: json['source'] is String ? json['source'] as String : null,
      batchId: json['batchId'] is String ? json['batchId'] as String : null,
      batchIndex: i(json['batchIndex']),
      batchFailureReason: json['batchFailureReason'] is String
          ? json['batchFailureReason'] as String
          : null,
      params: rawParams is Map
          ? {
              for (final e in rawParams.entries)
                e.key.toString(): '${e.value ?? ''}',
            }
          : null,
      caseId: json['caseId'] is String ? json['caseId'] as String : null,
      runIndex: i(json['runIndex']),
      isMedianRun:
          json['isMedianRun'] is bool ? json['isMedianRun'] as bool : null,
    );
  }

  static BenchmarkIndexEntry fromReport(BenchmarkReport report) {
    final stats = report.stats;
    return BenchmarkIndexEntry(
      id: report.id,
      createdAt: report.createdAt,
      name: report.metadata.name,
      route: report.metadata.route,
      durationMs: stats.durationMs,
      sampleCount: stats.sampleCount,
      jsFpsAvg: stats.jsFps.avg,
      uiFpsAvg: stats.uiFps.avg,
      cpuAvg: stats.cpuUsage.avg,
      memMaxMb: stats.memoryUsage.max,
      jsJankFrames: stats.jsJankFrames,
      uiJankFrames: stats.uiJankFrames,
      deviceMaxRefreshRate: stats.deviceMaxRefreshRate,
      source: report.metadata.source,
      batchId: report.metadata.batchId,
      batchIndex: report.metadata.batchIndex,
      batchFailureReason: report.metadata.batchFailureReason,
      params: report.metadata.params,
      caseId: report.metadata.caseId,
      runIndex: report.metadata.runIndex,
      isMedianRun: report.metadata.isMedianRun,
    );
  }
}

// ── Index-change notification ───────────────────────────────────────────────
// Fired whenever the saved-recordings index changes (save / delete / clear).
// The modal's list view and the sync adapter subscribe so they re-render
// without polling.
final Set<void Function()> _indexListeners = {};

void Function() subscribeBenchmarkIndex(void Function() listener) {
  _indexListeners.add(listener);
  return () => _indexListeners.remove(listener);
}

void _notifyIndexChanged() {
  for (final listener in [..._indexListeners]) {
    try {
      listener();
    } catch (_) {
      // ignore listener errors
    }
  }
}

class BenchmarkStorage {
  const BenchmarkStorage._();

  /// Serializes index read-modify-write so concurrent mutations can't clobber
  /// each other (RN `indexMutationChain`).
  static Future<void> _chain = Future<void>.value();

  static Future<List<BenchmarkIndexEntry>> _readIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(benchmarkIndexKey);
      if (raw == null || raw.isEmpty) return [];
      final parsed = jsonDecode(raw);
      if (parsed is! List) return [];
      return [
        for (final e in parsed)
          ?BenchmarkIndexEntry.fromJson(e),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeIndex(List<BenchmarkIndexEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      benchmarkIndexKey,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  static Future<void> _mutateIndex(
    List<BenchmarkIndexEntry> Function(List<BenchmarkIndexEntry>) mutator,
  ) {
    final run = _chain.then<void>((_) async {
      final index = await _readIndex();
      await _writeIndex(mutator(index));
    }).catchError((Object e, StackTrace s) {
      if (kDebugMode) debugPrint('[perf-monitor] index mutation failed: $e');
    });
    _chain = run;
    return run;
  }

  /// Persist a report + its index entry (RN `save`).
  static Future<void> save(BenchmarkReport report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _reportKey(report.id),
        jsonEncode(report.toJson()),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[perf-monitor] failed to save benchmark: $e');
      return;
    }
    final entry = BenchmarkIndexEntry.fromReport(report);
    await _mutateIndex(
      (index) => [entry, ...index.where((e) => e.id != report.id)],
    );
    _notifyIndexChanged();
  }

  /// Newest-first index (RN `list`).
  static Future<List<BenchmarkIndexEntry>> list() async {
    final index = await _readIndex();
    index.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return index;
  }

  /// Full report blob by id (RN `load`). Null when missing/corrupt.
  static Future<BenchmarkReport?> load(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_reportKey(id));
      if (raw == null || raw.isEmpty) return null;
      return BenchmarkReport.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_reportKey(id));
    } catch (_) {
      // best-effort
    }
    await _mutateIndex((index) => [...index.where((e) => e.id != id)]);
    _notifyIndexChanged();
  }

  static Future<void> deleteMany(List<String> ids) async {
    if (ids.isEmpty) return;
    final idSet = ids.toSet();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in idSet) {
        await prefs.remove(_reportKey(id));
      }
    } catch (_) {
      // best-effort
    }
    await _mutateIndex((index) => [...index.where((e) => !idSet.contains(e.id))]);
    _notifyIndexChanged();
  }

  /// Cascade-delete every report in a batch; returns the count removed
  /// (RN `deleteBatch`).
  static Future<int> deleteBatch(String batchId) async {
    if (batchId.isEmpty) return 0;
    final index = await _readIndex();
    final ids = [
      for (final e in index)
        if (e.batchId == batchId) e.id,
    ];
    if (ids.isEmpty) return 0;
    await deleteMany(ids);
    return ids.length;
  }

  static Future<void> clear() async {
    final index = await _readIndex();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in index) {
        await prefs.remove(_reportKey(entry.id));
      }
    } catch (_) {
      // best-effort
    }
    await _mutateIndex((_) => []);
    _notifyIndexChanged();
  }
}
