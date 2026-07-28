/// Types for the Riverpod state inspector — the Dart analog of
/// packages/jotai/src/jotai/types/index.ts, adapted from Jotai atoms to
/// Riverpod providers.
///
/// Where Jotai has two change categories (`write`/`initial`), Riverpod exposes
/// the full provider lifecycle, so [ProviderChangeCategory] adds `dispose` and
/// `error` (honest riverpod semantics; the UI badge/label map is below).
library;

/// Category of a captured provider change.
enum ProviderChangeCategory {
  /// Provider initialized (didAddProvider).
  initial,

  /// Provider value changed (didUpdateProvider).
  update,

  /// Provider disposed (didDisposeProvider).
  dispose,

  /// Provider threw / a Future/Stream emitted an error (providerDidFail).
  error,
}

/// Short badge text per category (jotai used INIT/WRITE; riverpod is honest).
String providerCategoryBadge(ProviderChangeCategory c) => switch (c) {
      ProviderChangeCategory.initial => 'INIT',
      ProviderChangeCategory.update => 'UPDATE',
      ProviderChangeCategory.dispose => 'DISPOSE',
      ProviderChangeCategory.error => 'ERROR',
    };

/// Wire string for the category (used in JSON snapshots/exports).
String providerCategoryName(ProviderChangeCategory c) => switch (c) {
      ProviderChangeCategory.initial => 'initial',
      ProviderChangeCategory.update => 'update',
      ProviderChangeCategory.dispose => 'dispose',
      ProviderChangeCategory.error => 'error',
    };

/// A captured provider change (RN `JotaiAtomChange`).
class ProviderChange {
  ProviderChange({
    required this.id,
    required this.providerLabel,
    required this.timestamp,
    required this.prevValue,
    required this.nextValue,
    required this.hasValueChange,
    required this.category,
    required this.changedKeys,
    required this.changedKeysCount,
    required this.diffSummary,
    required this.valuePreview,
  });

  final String id;
  final String providerLabel;
  final int timestamp;
  final Object? prevValue;
  final Object? nextValue;
  final bool hasValueChange;
  final ProviderChangeCategory category;
  final List<String> changedKeys;
  final int changedKeysCount;
  final String diffSummary;
  final String valuePreview;

  /// Serialized shape for the sync snapshot + events export (mirrors the RN
  /// jotai change JSON: id/atomLabel/timestamp/prevValue/nextValue/
  /// hasValueChange/changedKeys — plus riverpod's category).
  Map<String, Object?> toJson({Object? Function(Object?)? serialize}) {
    final s = serialize ?? (v) => v;
    return {
      'id': id,
      // Jotai wire field name kept for compatibility (an "atom" == a provider).
      'atomLabel': providerLabel,
      'timestamp': timestamp,
      'prevValue': s(prevValue),
      'nextValue': s(nextValue),
      'hasValueChange': hasValueChange,
      'category': providerCategoryName(category),
      'changedKeys': changedKeys,
    };
  }
}

/// Tracked provider metadata (RN `JotaiAtomInfo`). [currentValue] is the
/// last-observed value — an observer has no on-demand read, so this is updated
/// on every change rather than pulled live.
class ProviderInfo {
  ProviderInfo({
    required this.label,
    required this.color,
    this.changeCount = 0,
    this.currentValue,
    this.disposed = false,
  });

  final String label;
  final int color;
  int changeCount;
  Object? currentValue;
  bool disposed;
}

/// Serializable provider snapshot for the sync adapter (RN `JotaiAtomSnapshot`).
class ProviderSnapshot {
  const ProviderSnapshot({
    required this.label,
    required this.changeCount,
    required this.color,
    required this.currentValue,
  });

  final String label;
  final int changeCount;
  final int color;
  final Object? currentValue;

  Map<String, Object?> toJson() => {
        'label': label,
        'changeCount': changeCount,
        // Hex string to match RN's "#RRGGBB" color wire form.
        'color': '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        'currentValue': currentValue,
      };
}

/// Filter options for the change list (RN `JotaiFilter`).
class ProviderFilter {
  const ProviderFilter({
    this.searchText,
    this.providerLabels,
    this.onlyWithChanges = false,
  });

  final String? searchText;
  final List<String>? providerLabels;
  final bool onlyWithChanges;
}
