/// Ports packages/images/src/store/imageEventStore.ts + store/insights.ts +
/// state.ts.
///
/// Bounded singleton buffer of [ImageRecord]s fed by the capture layer
/// ([BuoyImage]). Frame-coalesced emit so bursty image grids don't turn every
/// event into its own rebuild (RN uses requestAnimationFrame; Flutter uses a
/// post-frame callback). All derived math (needed pixels, oversize factor,
/// decoded/wasted bytes, stats) and cross-record insights live here too.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

import 'image_record.dart';

/// Max records retained before the oldest are dropped (RN MAX_RECORDS).
const int _maxRecords = 500;

/// loadCount at/above this flags render-thrash reload storms (RN).
const int _retryStormThreshold = 5;

/// RN's iOS 4-concurrent-load limit heuristic (kept for wire parity).
const int _concurrentLoadLimit = 4;

class ImagesStore {
  ImagesStore._();
  static final ImagesStore instance = ImagesStore._();

  final List<ImageRecord> _records = [];
  final Map<int, ImageRecord> _byId = {};
  int _nextId = 1;
  final List<void Function()> _listeners = [];
  bool _emitScheduled = false;

  /// Snapshot identity changes only on emit (RN parity).
  List<ImageRecord> _snapshot = const [];

  void _emit() {
    if (_emitScheduled) return;
    _emitScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _emitScheduled = false;
      for (final listener in List.of(_listeners)) {
        listener();
      }
    });
  }

  void _invalidate() {
    _snapshot = List.of(_records);
    _emit();
  }

  ImageRecord createRecord({
    required ImageLib lib,
    required String uri,
    required SourceKind sourceKind,
  }) {
    final record = ImageRecord(
      id: _nextId++,
      lib: lib,
      uri: uri,
      sourceKind: sourceKind,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _records.add(record);
    _byId[record.id] = record;
    if (_records.length > _maxRecords) {
      final dropCount = _records.length - _maxRecords;
      final dropped = _records.sublist(0, dropCount);
      _records.removeRange(0, dropCount);
      for (final d in dropped) {
        _byId.remove(d.id);
      }
    }
    _invalidate();
    return record;
  }

  /// Notify after mutating a record in place (records are owned by the store).
  void touch() => _invalidate();

  ImageRecord? getRecord(int id) => _byId[id];

  /// Newest-last buffer snapshot (RN getSnapshot).
  List<ImageRecord> getSnapshot() => _snapshot;

  /// Newest-last live list, for the in-app tool.
  List<ImageRecord> get records => List.unmodifiable(_records);

  void Function() subscribe(void Function() onChange) {
    _listeners.add(onChange);
    return () => _listeners.remove(onChange);
  }

  /// Clear the registry, keeping in-flight loads so events don't orphan (RN).
  void clearRecords() {
    _records.retainWhere(
      (r) =>
          r.mounted &&
          r.status != ImageStatus.loaded &&
          r.status != ImageStatus.error,
    );
    _byId
      ..clear()
      ..addEntries(_records.map((r) => MapEntry(r.id, r)));
    _invalidate();
  }
}

// ---------------------------------------------------------------------------
// Derived math (shared by rows, detail, and stats) — RN imageEventStore.ts
// ---------------------------------------------------------------------------

/// Physical pixels needed to fill the laid-out box 1:1 (RN neededPixels).
ImageDimensions? neededPixels(ImageRecord record) {
  final layout = record.layout;
  if (layout == null || layout.width <= 0 || layout.height <= 0) return null;
  final scale = record.devicePixelRatio;
  return ImageDimensions(
    (layout.width * scale).round(),
    (layout.height * scale).round(),
  );
}

/// Linear oversize factor: how many times larger (per axis, area-normalized)
/// the decoded bitmap is vs what the box needs. 1 = perfect, 2 = 4× the pixels.
double? oversizeFactor(ImageRecord record) {
  final needed = neededPixels(record);
  final intrinsic = record.intrinsic;
  if (needed == null || intrinsic == null) return null;
  final neededArea = needed.width * needed.height;
  final intrinsicArea = intrinsic.width * intrinsic.height;
  if (neededArea <= 0 || intrinsicArea <= 0) return null;
  return math.sqrt(intrinsicArea / neededArea);
}

/// Estimated decoded-bitmap memory for a loaded record (RGBA8888).
int estDecodedBytes(ImageRecord record) {
  final intrinsic = record.intrinsic;
  if (intrinsic == null) return 0;
  return intrinsic.width * intrinsic.height * 4;
}

/// Decoded bytes beyond what the laid-out box needs (0 if not oversized).
int estWastedBytes(ImageRecord record) {
  final needed = neededPixels(record);
  final intrinsic = record.intrinsic;
  if (needed == null || intrinsic == null) return 0;
  final wasted =
      (intrinsic.width * intrinsic.height - needed.width * needed.height) * 4;
  return wasted < 0 ? 0 : wasted;
}

ImageStats computeStats(List<ImageRecord> list) {
  var loading = 0, loaded = 0, errors = 0, networkLoads = 0;
  var decoded = 0, wasted = 0;
  for (final r in list) {
    if ((r.status == ImageStatus.loading || r.status == ImageStatus.pending) &&
        r.mounted) {
      loading++;
    }
    if (r.status == ImageStatus.loaded) loaded++;
    if (r.status == ImageStatus.error) errors++;
    if (r.progressSeen || r.cacheVerdict == CacheVerdict.none) networkLoads++;
    if (r.mounted && r.status == ImageStatus.loaded) {
      decoded += estDecodedBytes(r);
      wasted += estWastedBytes(r);
    }
  }
  return ImageStats(
    total: list.length,
    loading: loading,
    loaded: loaded,
    errors: errors,
    networkLoads: networkLoads,
    estDecodedBytes: decoded,
    estWastedBytes: wasted,
  );
}

// ---------------------------------------------------------------------------
// Cross-record insights — RN store/insights.ts
// ---------------------------------------------------------------------------

ImageInsights computeInsights(List<ImageRecord> records) {
  final byUri = <String, int>{};
  final retryStorms = <({int id, String uri, int loadCount})>[];
  final layoutShifters = <({int id, String uri, int shifts})>[];
  var missingAlt = 0;
  var loadingCount = 0;

  for (final r in records) {
    if (r.mounted && r.uri.isNotEmpty) {
      byUri[r.uri] = (byUri[r.uri] ?? 0) + 1;
    }
    if (r.loadCount >= _retryStormThreshold) {
      retryStorms.add((id: r.id, uri: r.uri, loadCount: r.loadCount));
    }
    if (r.layoutShifts > 0) {
      layoutShifters.add((id: r.id, uri: r.uri, shifts: r.layoutShifts));
    }
    if (r.mounted && r.hasAltText == false) missingAlt++;
    if (r.mounted && r.status == ImageStatus.loading) loadingCount++;
  }

  final duplicates =
      byUri.entries.where((e) => e.value > 1).map((e) => (uri: e.key, count: e.value)).toList()
        ..sort((a, b) => b.count - a.count);
  retryStorms.sort((a, b) => b.loadCount - a.loadCount);

  return ImageInsights(
    duplicates: duplicates,
    retryStorms: retryStorms,
    queueSaturated: loadingCount > _concurrentLoadLimit,
    missingAlt: missingAlt,
    layoutShifters: layoutShifters,
  );
}

/// Compact one-line chips (RN insightChips). Empty = all clear.
List<String> insightChips(ImageInsights insights) {
  final chips = <String>[];
  if (insights.duplicates.isNotEmpty) {
    final extra = insights.duplicates.fold<int>(0, (n, d) => n + d.count - 1);
    final plural = insights.duplicates.length > 1 ? 's' : '';
    chips.add(
      '${insights.duplicates.length} duplicate URL$plural ($extra redundant loads)',
    );
  }
  if (insights.retryStorms.isNotEmpty) {
    final plural = insights.retryStorms.length > 1 ? 's' : '';
    chips.add('${insights.retryStorms.length} retry storm$plural');
  }
  if (insights.queueSaturated) chips.add('image queue saturated (>4 loading)');
  if (insights.missingAlt > 0) chips.add('${insights.missingAlt} missing alt text');
  if (insights.layoutShifters.isNotEmpty) {
    final plural = insights.layoutShifters.length > 1 ? 's' : '';
    chips.add('${insights.layoutShifters.length} layout-shifting image$plural');
  }
  return chips;
}
