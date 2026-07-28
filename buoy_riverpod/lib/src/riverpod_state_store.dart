/// Riverpod state store — captures and stores provider changes.
///
/// Dart port of packages/jotai/src/jotai/utils/jotaiStateStore.ts, renamed
/// atom→provider. A singleton ring buffer of [ProviderChange] (max 200,
/// newest-first) plus a provider registry with each provider's last-observed
/// value, change count, and hash-derived color. Fed by [BuoyRiverpodObserver];
/// read by the modal UI + the sync adapter + the events source.
library;

import 'riverpod_types.dart';

// ── Provider color palette (RN ATOM_COLORS) ──────────────────────────────────

const Map<String, int> _providerColors = {
  'count': 0xFF10B981, // emerald
  'auth': 0xFF8B5CF6, // purple
  'user': 0xFF3B82F6, // blue
  'cart': 0xFFEC4899, // pink
  'app': 0xFF6366F1, // indigo
  'ui': 0xFFF59E0B, // amber
  'settings': 0xFF14B8A6, // teal
  'theme': 0xFF06B6D4, // cyan
  'nav': 0xFFF97316, // orange
  'form': 0xFFEF4444, // red
  'modal': 0xFFA855F7, // violet
  'filter': 0xFF84CC16, // lime
};

/// Hash-derive a stable color from a provider label (RN `getAtomColor`).
int providerColorFor(String label) {
  final lower = label.toLowerCase();
  final exact = _providerColors[lower];
  if (exact != null) return exact;
  for (final entry in _providerColors.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }

  var hash = 0;
  for (final code in label.codeUnits) {
    hash += code;
  }
  final hue = (hash * 137) % 360;
  const s = 0.7;
  const l = 0.6;
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - (((hue / 60) % 2) - 1).abs());
  final m = l - c / 2;
  double r = 0, g = 0, b = 0;
  if (hue < 60) {
    r = c;
    g = x;
  } else if (hue < 120) {
    r = x;
    g = c;
  } else if (hue < 180) {
    g = c;
    b = x;
  } else if (hue < 240) {
    g = x;
    b = c;
  } else if (hue < 300) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  int toByte(double v) => ((v + m) * 255).round().clamp(0, 255);
  return 0xFF000000 | (toByte(r) << 16) | (toByte(g) << 8) | toByte(b);
}

// ── Value preview + diff summary (RN helpers) ────────────────────────────────

/// RN `formatValuePreview` — a short one-line preview of a value.
String formatValuePreview(Object? value, [int maxLength = 40]) {
  if (value == null) return 'null';
  try {
    if (value is String) {
      return value.length > maxLength
          ? '"${value.substring(0, maxLength - 3)}..."'
          : '"$value"';
    }
    if (value is num || value is bool) return value.toString();
    if (value is List) {
      if (value.isEmpty) return '[]';
      final preview = value.toString();
      return preview.length > maxLength ? '[${value.length} items]' : preview;
    }
    if (value is Map) {
      if (value.isEmpty) return '{}';
      final preview = value.toString();
      if (preview.length <= maxLength) return preview;
      return '{ ${value.length} keys }';
    }
    final s = value.toString();
    return s.length > maxLength ? s.substring(0, maxLength) : s;
  } catch (_) {
    return '[complex]';
  }
}

/// RN `getValueDiffSummary` — "+1 -0 ~2 keys" for object changes.
({String summary, List<String> changedKeys, int changedCount}) valueDiffSummary(
  Object? prevValue,
  Object? nextValue,
) {
  if (identical(prevValue, nextValue) || prevValue == nextValue) {
    return (summary: 'no change', changedKeys: const [], changedCount: 0);
  }
  if (prevValue is! Map || nextValue is! Map) {
    return (summary: 'changed', changedKeys: const [], changedCount: 0);
  }

  final prevKeys = prevValue.keys.map((k) => '$k').toList();
  final nextKeys = nextValue.keys.map((k) => '$k').toList();
  final added = nextKeys.where((k) => !prevKeys.contains(k)).toList();
  final removed = prevKeys.where((k) => !nextKeys.contains(k)).toList();
  final changed = <String>[];
  for (final key in prevValue.keys) {
    if (nextValue.containsKey(key) && prevValue[key] != nextValue[key]) {
      changed.add('$key');
    }
  }

  final allChanged = [...added, ...removed, ...changed];
  final parts = <String>[];
  if (added.isNotEmpty) parts.add('+${added.length}');
  if (removed.isNotEmpty) parts.add('-${removed.length}');
  if (changed.isNotEmpty) parts.add('~${changed.length}');
  final total = allChanged.length;
  if (parts.isEmpty) {
    return (summary: 'nested change', changedKeys: const [], changedCount: 0);
  }
  return (
    summary: '${parts.join(" ")} ${total == 1 ? "key" : "keys"}',
    changedKeys: allChanged,
    changedCount: total,
  );
}

// ── Store ────────────────────────────────────────────────────────────────────

class RiverpodStateStore {
  RiverpodStateStore._();

  List<ProviderChange> _changes = [];
  final Map<String, ProviderInfo> _providers = {};
  final Set<void Function(List<ProviderChange>)> _listeners = {};
  final Set<void Function(List<ProviderInfo>)> _providerListeners = {};
  final Set<void Function(ProviderChange)> _newChangeListeners = {};
  final Set<void Function()> _clearListeners = {};
  int _maxChanges = 200;
  int _idCounter = 0;

  /// Whether capture is active (the UI's power toggle). When false, [_addChange]
  /// records nothing.
  bool isEnabled = true;

  // ── Change recording ────────────────────────────────────────────────────

  void _addChange({
    required String label,
    required Object? prevValue,
    required Object? nextValue,
    required ProviderChangeCategory category,
  }) {
    if (!isEnabled) return;

    final hasValueChange = prevValue != nextValue;
    final diff = valueDiffSummary(prevValue, nextValue);

    final change = ProviderChange(
      id: '${DateTime.now().millisecondsSinceEpoch}-${++_idCounter}',
      providerLabel: label,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      prevValue: prevValue,
      nextValue: nextValue,
      hasValueChange: hasValueChange,
      category: category,
      changedKeys: diff.changedKeys,
      changedKeysCount: diff.changedCount,
      diffSummary: diff.summary,
      valuePreview: formatValuePreview(nextValue),
    );

    _changes = [change, ..._changes];
    if (_changes.length > _maxChanges) {
      _changes = _changes.sublist(0, _maxChanges);
    }

    final info = _providers[label];
    if (info != null) info.changeCount++;

    _notifyChanges();
    _notifyProviders();
    for (final listener in List.of(_newChangeListeners)) {
      listener(change);
    }
  }

  /// Register a provider (if new) and log its initial value.
  void recordInitial(String label, Object? value) {
    _ensureProvider(label).currentValue = value;
    _addChange(
      label: label,
      prevValue: null,
      nextValue: value,
      category: ProviderChangeCategory.initial,
    );
  }

  /// Log a value update (didUpdateProvider).
  void recordUpdate(String label, Object? prev, Object? next) {
    final info = _ensureProvider(label);
    info.currentValue = next;
    info.disposed = false;
    _addChange(
      label: label,
      prevValue: prev,
      nextValue: next,
      category: ProviderChangeCategory.update,
    );
  }

  /// Log a dispose (didDisposeProvider). The provider stays in the registry
  /// (marked disposed) so its history remains browsable — a deliberate
  /// deviation from Jotai's `unregisterAtom` (riverpod autoDispose churns).
  void recordDispose(String label) {
    final info = _providers[label];
    if (info != null) info.disposed = true;
    _addChange(
      label: label,
      prevValue: info?.currentValue,
      nextValue: info?.currentValue,
      category: ProviderChangeCategory.dispose,
    );
  }

  /// Log an error (providerDidFail).
  void recordError(String label, Object error) {
    _ensureProvider(label);
    _addChange(
      label: label,
      prevValue: _providers[label]?.currentValue,
      nextValue: 'Error: $error',
      category: ProviderChangeCategory.error,
    );
  }

  ProviderInfo _ensureProvider(String label) {
    return _providers.putIfAbsent(
      label,
      () {
        final info = ProviderInfo(label: label, color: providerColorFor(label));
        _notifyProviders();
        return info;
      },
    );
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  List<ProviderChange> getChanges() => List.of(_changes);

  ProviderChange? getChangeById(String id) {
    for (final c in _changes) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<ProviderInfo> getProviders() => _providers.values.toList();

  ProviderInfo? getProvider(String label) => _providers[label];

  int providerColor(String label) =>
      _providers[label]?.color ?? providerColorFor(label);

  List<String> getUniqueProviderLabels() =>
      _providers.keys.toList()..sort();

  List<ProviderSnapshot> getProviderSnapshots() => _providers.values
      .map((p) => ProviderSnapshot(
            label: p.label,
            changeCount: p.changeCount,
            color: p.color,
            currentValue: p.currentValue,
          ))
      .toList();

  ({int totalChanges, int changesWithValueChange, int changesWithoutValueChange, int providerCount})
      getStats() {
    final total = _changes.length;
    final withChanges = _changes.where((c) => c.hasValueChange).length;
    return (
      totalChanges: total,
      changesWithValueChange: withChanges,
      changesWithoutValueChange: total - withChanges,
      providerCount: _providers.length,
    );
  }

  // ── Filtering (RN filterAtomChanges) ──────────────────────────────────────

  List<ProviderChange> filterChanges(ProviderFilter filter) {
    var filtered = List.of(_changes);
    final search = filter.searchText?.toLowerCase();
    if (search != null && search.isNotEmpty) {
      filtered = filtered
          .where((c) =>
              c.providerLabel.toLowerCase().contains(search) ||
              c.valuePreview.toLowerCase().contains(search) ||
              c.changedKeys.any((k) => k.toLowerCase().contains(search)))
          .toList();
    }
    final labels = filter.providerLabels;
    if (labels != null && labels.isNotEmpty) {
      filtered =
          filtered.where((c) => labels.contains(c.providerLabel)).toList();
    }
    if (filter.onlyWithChanges) {
      filtered = filtered.where((c) => c.hasValueChange).toList();
    }
    return filtered;
  }

  // ── Clear / enable ─────────────────────────────────────────────────────────

  void clearChanges() {
    _changes = [];
    for (final p in _providers.values) {
      p.changeCount = 0;
    }
    _notifyChanges();
    _notifyProviders();
    for (final listener in List.of(_clearListeners)) {
      listener();
    }
  }

  void setMaxChanges(int max) {
    _maxChanges = max;
    if (_changes.length > max) {
      _changes = _changes.sublist(0, max);
      _notifyChanges();
    }
  }

  // ── Subscriptions ──────────────────────────────────────────────────────────

  void Function() subscribe(void Function(List<ProviderChange>) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void Function() subscribeToProviders(
      void Function(List<ProviderInfo>) listener) {
    _providerListeners.add(listener);
    return () => _providerListeners.remove(listener);
  }

  /// Per-event hook — fires once with the single new change (used by the events
  /// source to transform each write into a `UnifiedEvent`).
  void Function() subscribeToNewChanges(void Function(ProviderChange) listener) {
    _newChangeListeners.add(listener);
    return () => _newChangeListeners.remove(listener);
  }

  void Function() onClear(void Function() listener) {
    _clearListeners.add(listener);
    return () => _clearListeners.remove(listener);
  }

  void _notifyChanges() {
    final snapshot = getChanges();
    for (final listener in List.of(_listeners)) {
      listener(snapshot);
    }
  }

  void _notifyProviders() {
    final snapshot = getProviders();
    for (final listener in List.of(_providerListeners)) {
      listener(snapshot);
    }
  }
}

/// The singleton store (RN `jotaiStateStore`).
final riverpodStateStore = RiverpodStateStore._();
