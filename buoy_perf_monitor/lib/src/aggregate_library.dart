/// Ports packages/perf-monitor/src/perf-monitor/utils/aggregateLibrary.ts.
///
/// Folds a flat index into the items the Library list renders: solo recordings
/// pass through 1:1; batch children collapse into one batch summary so a
/// 10-case batch shows as one card, not ten.
///
/// Worst-of-batch metrics are baked into the summary (min FPS across
/// non-failed children, max CPU/MEM, summed jank) so the card answers "is
/// anything wrong in this batch?" at a glance.
library;

import 'automation_runner.dart' show isWarmupRun;
import 'benchmark_storage.dart';

/// A Library row: either one solo run or a collapsed batch.
class LibraryItem {
  const LibraryItem.solo(BenchmarkIndexEntry this.entry)
      : isBatch = false,
        batchId = '',
        childIds = const [],
        caseCount = 0,
        failureCount = 0,
        createdAt = 0,
        route = null,
        routeCount = 0,
        pivotKey = null,
        pivotValueCount = 0,
        jsFpsAvg = 0,
        uiFpsAvg = 0,
        cpuAvg = 0,
        memMaxMb = 0,
        jsJankFrames = 0,
        uiJankFrames = 0,
        durationMs = 0,
        sampleCount = 0,
        deviceMaxRefreshRate = 0,
        baselineName = null;

  const LibraryItem.batch({
    required this.batchId,
    required this.childIds,
    required this.caseCount,
    required this.failureCount,
    required this.createdAt,
    required this.route,
    required this.routeCount,
    required this.pivotKey,
    required this.pivotValueCount,
    required this.jsFpsAvg,
    required this.uiFpsAvg,
    required this.cpuAvg,
    required this.memMaxMb,
    required this.jsJankFrames,
    required this.uiJankFrames,
    required this.durationMs,
    required this.sampleCount,
    required this.deviceMaxRefreshRate,
    required this.baselineName,
  })  : isBatch = true,
        entry = null;

  final bool isBatch;
  final BenchmarkIndexEntry? entry;

  final String batchId;
  final List<String> childIds;
  final int caseCount;
  final int failureCount;
  final int createdAt;
  final String? route;
  final int routeCount;
  final String? pivotKey;
  final int pivotValueCount;
  final double jsFpsAvg;
  final double uiFpsAvg;
  final double cpuAvg;
  final double memMaxMb;
  final int jsJankFrames;
  final int uiJankFrames;
  final int durationMs;
  final int sampleCount;
  final double deviceMaxRefreshRate;
  final String? baselineName;

  int get itemCreatedAt => isBatch ? createdAt : entry!.createdAt;
}

List<LibraryItem> aggregateLibrary(List<BenchmarkIndexEntry> entries) {
  final solos = <LibraryItem>[];
  final buckets = <String, List<BenchmarkIndexEntry>>{};
  for (final entry in entries) {
    // The batch warmup run is never part of the numbers (RN parity).
    if (isWarmupRun(entry.name)) continue;
    final batchId = entry.batchId;
    if (batchId == null) {
      solos.add(LibraryItem.solo(entry));
      continue;
    }
    (buckets[batchId] ??= []).add(entry);
  }

  final batches = [
    for (final e in buckets.entries) _buildBatchItem(e.key, e.value),
  ];

  final out = [...solos, ...batches];
  // Newest first by the item's own createdAt — for batches that's the earliest
  // child (so a finished batch jumps to the top).
  out.sort((a, b) => b.itemCreatedAt.compareTo(a.itemCreatedAt));
  return out;
}

LibraryItem _buildBatchItem(
  String batchId,
  List<BenchmarkIndexEntry> children,
) {
  final sorted = [...children]
    ..sort((a, b) => (a.batchIndex ?? 0).compareTo(b.batchIndex ?? 0));
  final nonFailed = [
    for (final c in sorted)
      if (c.batchFailureReason == null) c,
  ];
  final failureCount = sorted.length - nonFailed.length;

  final distinctRoutes = <String>{
    for (final c in sorted)
      if (c.route != null && c.route!.isNotEmpty) c.route!,
  };
  final routeCount = distinctRoutes.length;
  final route = routeCount == 1 ? distinctRoutes.first : null;

  // Pivot key: any param key whose value varies across children.
  final pivotKey = _findPivotKey(sorted);
  final pivotValueCount = pivotKey == null
      ? 0
      : <String>{for (final c in sorted) c.params?[pivotKey] ?? ''}.length;

  // Worst-of-batch snapshot across non-failed children only, so a
  // zero-sample failure doesn't drag JS FPS to 0 and paint everything JANK.
  final sample = nonFailed.isNotEmpty ? nonFailed : sorted;

  return LibraryItem.batch(
    batchId: batchId,
    childIds: [for (final c in sorted) c.id],
    caseCount: sorted.length,
    failureCount: failureCount,
    // Earliest child's timestamp drives sort order so the batch card moves to
    // the top the moment the first case lands.
    createdAt: sorted.map((c) => c.createdAt).reduce((a, b) => a < b ? a : b),
    route: route,
    routeCount: routeCount,
    pivotKey: pivotKey,
    pivotValueCount: pivotValueCount,
    jsFpsAvg: _minOf(sample, (c) => c.jsFpsAvg),
    uiFpsAvg: _minOf(sample, (c) => c.uiFpsAvg),
    cpuAvg: _maxOf(sample, (c) => c.cpuAvg),
    memMaxMb: _maxOf(sample, (c) => c.memMaxMb),
    jsJankFrames: _sumOf(sample, (c) => c.jsJankFrames?.toDouble()).round(),
    uiJankFrames: _sumOf(sample, (c) => c.uiJankFrames?.toDouble()).round(),
    durationMs: _sumOf(sample, (c) => c.durationMs?.toDouble()).round(),
    sampleCount: _sumOf(sample, (c) => c.sampleCount?.toDouble()).round(),
    deviceMaxRefreshRate:
        sample.isEmpty ? 0 : (sample.first.deviceMaxRefreshRate ?? 0),
    baselineName: _firstWhereOrNull(nonFailed, (c) => c.batchIndex == 0)?.name ??
        (nonFailed.isNotEmpty ? nonFailed.first.name : null) ??
        (sorted.isNotEmpty ? sorted.first.name : null),
  );
}

T? _firstWhereOrNull<T>(List<T> items, bool Function(T) test) {
  for (final it in items) {
    if (test(it)) return it;
  }
  return null;
}

String? _findPivotKey(List<BenchmarkIndexEntry> children) {
  if (children.length < 2) return null;
  final keys = <String>{
    for (final c in children) ...?c.params?.keys,
  };
  final sortedKeys = keys.toList()..sort();
  for (final key in sortedKeys) {
    final first = children.first.params?[key] ?? '';
    if (children.any((c) => (c.params?[key] ?? '') != first)) return key;
  }
  return null;
}

double _minOf(
  List<BenchmarkIndexEntry> items,
  double? Function(BenchmarkIndexEntry) pick,
) {
  var best = double.infinity;
  for (final it in items) {
    final v = pick(it);
    if (v != null && v.isFinite && v < best) best = v;
  }
  return best.isFinite ? best : 0;
}

double _maxOf(
  List<BenchmarkIndexEntry> items,
  double? Function(BenchmarkIndexEntry) pick,
) {
  var best = double.negativeInfinity;
  for (final it in items) {
    final v = pick(it);
    if (v != null && v.isFinite && v > best) best = v;
  }
  return best.isFinite ? best : 0;
}

double _sumOf(
  List<BenchmarkIndexEntry> items,
  double? Function(BenchmarkIndexEntry) pick,
) {
  var total = 0.0;
  for (final it in items) {
    final v = pick(it);
    if (v != null && v.isFinite) total += v;
  }
  return total;
}
