/// Ports packages/perf-monitor/src/perf-monitor/utils/modalViewPersistence.ts.
///
/// Remembers which screen the user had open inside the perf modal under
/// `@react_buoy/perf-monitor/modal-view`, so a hot restart (or the modal being
/// reopened) lands them back where they were instead of the default list.
///
/// Heavy payloads are never persisted — only the identifying id, rehydrated
/// through [BenchmarkStorage] on boot, so the blob stays tiny and can't
/// restore into a deleted report.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String modalViewKey = '@react_buoy/perf-monitor/modal-view';

/// The persisted view union (RN `PersistedModalView`). `kind` is one of
/// `list | detail | settings | automate | batch-report | compare | diagnostics`.
class PersistedModalView {
  const PersistedModalView({
    required this.kind,
    this.reportId,
    this.batchId,
    this.reportIds,
  });

  final String kind;
  final String? reportId;
  final String? batchId;
  final List<String>? reportIds;

  Map<String, Object?> toJson() => {
        'kind': kind,
        if (reportId != null) 'reportId': reportId,
        if (batchId != null) 'batchId': batchId,
        if (reportIds != null) 'reportIds': reportIds,
      };
}

/// Validate a decoded blob. Null when the shape is unusable (caller falls back
/// to the default landing).
PersistedModalView? sanitizeModalView(Object? raw) {
  if (raw is! Map) return null;
  final json = raw.cast<String, Object?>();
  final kind = json['kind'];
  if (kind is! String) return null;
  switch (kind) {
    case 'list':
    case 'settings':
    case 'automate':
    case 'diagnostics':
      return PersistedModalView(kind: kind);
    case 'detail':
      final id = json['reportId'];
      if (id is! String || id.isEmpty) return null;
      return PersistedModalView(kind: 'detail', reportId: id);
    case 'batch-report':
      final id = json['batchId'];
      if (id is! String || id.isEmpty) return null;
      return PersistedModalView(kind: 'batch-report', batchId: id);
    case 'compare':
      final ids = json['reportIds'];
      if (ids is! List) return null;
      final reportIds = [
        for (final id in ids)
          if (id is String && id.isNotEmpty) id,
      ];
      if (reportIds.length < 2) return null;
      return PersistedModalView(kind: 'compare', reportIds: reportIds);
    default:
      return null;
  }
}

Future<PersistedModalView?> loadModalView() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(modalViewKey);
    if (raw == null || raw.isEmpty) return null;
    return sanitizeModalView(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

Future<void> saveModalView(PersistedModalView view) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(modalViewKey, jsonEncode(view.toJson()));
  } catch (_) {
    // best-effort
  }
}

Future<void> clearModalView() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(modalViewKey);
  } catch (_) {
    // best-effort
  }
}
