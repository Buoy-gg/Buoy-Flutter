/// Ports packages/perf-monitor/src/perf-monitor/utils/caseSets.ts.
///
/// Named, reusable sets of automation cases persisted under
/// `@react_buoy/perf-monitor/case-sets`. Separate from
/// [AutomationConfigStore] (which holds the single last-edited config) — this
/// is a small library of case lists keyed by name, most-recent first.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'automation_settings.dart';
import 'perf_types.dart';

const String caseSetsKey = '@react_buoy/perf-monitor/case-sets';

class SavedCaseSet {
  const SavedCaseSet({
    required this.id,
    required this.name,
    required this.cases,
    required this.savedAt,
  });

  /// Stable id for list keys + delete targeting.
  final String id;

  /// User-facing label (unique, case-insensitive).
  final String name;
  final List<AutomationCase> cases;

  /// Epoch ms of the last save — drives "most recent first" ordering.
  final int savedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'cases': [for (final c in cases) c.toJson()],
        'savedAt': savedAt,
      };
}

int _nextLocalId = 1;
String _makeSetId() =>
    'set-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${(_nextLocalId++).toRadixString(36)}';

SavedCaseSet? _sanitizeSet(Object? raw) {
  if (raw is! Map) return null;
  final r = raw.cast<String, Object?>();
  final rawName = r['name'];
  if (rawName is! String || rawName.trim().isEmpty) return null;
  final cases = sanitizeAutomationCases(r['cases']);
  // A set with no usable cases is dead weight — drop it on load.
  if (cases.isEmpty) return null;
  final id = r['id'];
  final savedAt = r['savedAt'];
  return SavedCaseSet(
    id: id is String && id.isNotEmpty ? id : _makeSetId(),
    name: rawName.trim(),
    cases: cases,
    savedAt: savedAt is num && savedAt.isFinite
        ? savedAt.round()
        : DateTime.now().millisecondsSinceEpoch,
  );
}

List<SavedCaseSet> sanitizeCaseSetList(Object? value) {
  if (value is! List) return [];
  final out = [
    for (final raw in value)
      ?_sanitizeSet(raw),
  ];
  out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
  return out;
}

class CaseSetsStore {
  CaseSetsStore._();
  static final CaseSetsStore instance = CaseSetsStore._();

  List<SavedCaseSet> _current = const [];
  bool _loaded = false;
  Future<void>? _loadFuture;
  final Set<void Function(List<SavedCaseSet>)> _subscribers = {};

  List<SavedCaseSet> get current => _current;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(caseSetsKey);
        if (raw != null) _current = sanitizeCaseSetList(jsonDecode(raw));
      } catch (_) {
        // keep empty
      } finally {
        _loaded = true;
        _notify();
      }
    }();
  }

  void Function() subscribe(void Function(List<SavedCaseSet>) fn) {
    _subscribers.add(fn);
    fn(_current);
    return () => _subscribers.remove(fn);
  }

  /// Save (or overwrite) a named set. Matching is case-insensitive on the
  /// trimmed name, so re-saving "Test All" replaces "test all" in place and
  /// bumps it to the top. Returns null when the name is blank or nothing is
  /// worth saving.
  Future<SavedCaseSet?> save(String name, List<AutomationCase> cases) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final sanitized =
        sanitizeAutomationCases([for (final c in cases) c.toJson()]);
    if (sanitized.isEmpty) return null;

    final lower = trimmed.toLowerCase();
    SavedCaseSet? existing;
    for (final s in _current) {
      if (s.name.toLowerCase() == lower) {
        existing = s;
        break;
      }
    }
    final set = SavedCaseSet(
      id: existing?.id ?? _makeSetId(),
      name: trimmed,
      cases: sanitized,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _current = [set, ..._current.where((s) => s.id != set.id)];
    _notify();
    await _persist();
    return set;
  }

  Future<void> delete(String id) async {
    final next = [..._current.where((s) => s.id != id)];
    if (next.length == _current.length) return;
    _current = next;
    _notify();
    await _persist();
  }

  /// True when a set with this (trimmed, case-insensitive) name exists.
  bool nameExists(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return _current.any((s) => s.name.toLowerCase() == lower);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        caseSetsKey,
        jsonEncode([for (final s in _current) s.toJson()]),
      );
    } catch (_) {
      // best-effort
    }
  }

  void _notify() {
    for (final fn in [..._subscribers]) {
      try {
        fn(_current);
      } catch (_) {
        // swallow
      }
    }
  }
}
