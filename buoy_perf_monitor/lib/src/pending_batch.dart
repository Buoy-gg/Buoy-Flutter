/// Ports packages/perf-monitor/src/perf-monitor/utils/pendingBatch.ts.
///
/// Cross-reload persistence for a batch in flight, under
/// `@react_buoy/perf-monitor/pending-batch`. Flutter forces
/// `reloadBetweenCases` off (Dart can't reload its realm), so the runner never
/// writes this slot itself — it's kept for storage/wire parity and so a state
/// blob written elsewhere can still be validated and resumed.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'automation_settings.dart';
import 'perf_types.dart';

const String pendingBatchKey = '@react_buoy/perf-monitor/pending-batch';

/// Older than this and the state is treated as orphaned (the app was killed
/// and the user moved on).
const int staleBatchTtlMs = 5 * 60000;

/// Hard cap on resume attempts, compared against `(cases.length + 2)`.
const int maxResumeCountHeadroom = 2;

/// Validate-and-coerce a decoded blob into a [PendingBatchState] (RN
/// `sanitize`). Null when required fields are missing.
PendingBatchState? sanitizePendingBatch(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, Object?>();

  final batchId = json['batchId'];
  if (batchId is! String || batchId.isEmpty) return null;

  final rawConfig = json['config'];
  if (rawConfig is! Map || rawConfig['cases'] is! List) return null;

  final startedAt = json['startedAt'];
  if (startedAt is! num) return null;

  final nextIndex = json['nextIndex'];
  if (nextIndex is! num || nextIndex < 0) return null;

  final completedReportIds = <String>[
    if (json['completedReportIds'] is List)
      for (final id in json['completedReportIds'] as List)
        if (id is String) id,
  ];

  final failures = <({int index, String reason})>[
    if (json['failures'] is List)
      for (final f in json['failures'] as List)
        if (f is Map && f['index'] is num && f['reason'] is String)
          (index: (f['index'] as num).round(), reason: f['reason'] as String),
  ];

  final resumeCount = json['resumeCount'];
  final lastReloadAt = json['lastReloadAt'];
  final nextRunIndex = json['nextRunIndex'];
  final rawPerCase = json['perCaseReportIds'];

  return PendingBatchState(
    batchId: batchId,
    config: sanitizeAutomationConfig(rawConfig),
    startedAt: startedAt.round(),
    nextIndex: nextIndex.round(),
    completedReportIds: completedReportIds,
    failures: failures,
    resumeCount: resumeCount is num ? resumeCount.round() : 0,
    lastReloadAt: lastReloadAt is num ? lastReloadAt.round() : null,
    nextRunIndex:
        nextRunIndex is num && nextRunIndex >= 0 ? nextRunIndex.round() : null,
    perCaseReportIds: rawPerCase is Map
        ? {
            for (final e in rawPerCase.entries)
              if (e.value is List)
                e.key.toString(): [
                  for (final id in e.value as List)
                    if (id is String) id,
                ],
          }
        : null,
  );
}

Future<void> savePendingBatch(PendingBatchState state) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingBatchKey, jsonEncode(state.toJson()));
  } catch (_) {
    // best-effort
  }
}

Future<PendingBatchState?> loadPendingBatch() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(pendingBatchKey);
    if (raw == null || raw.isEmpty) return null;
    return sanitizePendingBatch(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

Future<void> clearPendingBatch() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pendingBatchKey);
  } catch (_) {
    // best-effort
  }
}

/// True when the state looks too old to be a live batch.
bool isStalePendingBatch(PendingBatchState state, [int? now]) {
  final anchor = state.lastReloadAt ?? state.startedAt;
  return (now ?? DateTime.now().millisecondsSinceEpoch) - anchor >
      staleBatchTtlMs;
}

/// True when the batch has resumed more times than its case count plus
/// headroom — almost certainly a crash loop on the resumed case.
bool isResumeLoop(PendingBatchState state) =>
    state.resumeCount > state.config.cases.length + maxResumeCountHeadroom;
