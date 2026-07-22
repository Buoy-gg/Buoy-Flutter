import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Port of shared-ui's `ignoredPatternsStore` — the shared exclude-pattern
/// store the Network (and future Events) tool read. Same persisted key and
/// JSON shape as RN (`@react_buoy_network_ignored_domains`,
/// `[{"value": "...", "mode": "contains"|"exact"}]`) so state carries across
/// frameworks.

enum IgnoredPatternMatchMode { contains, exact }

@immutable
class IgnoredPattern {
  const IgnoredPattern(this.value, this.mode);
  final String value;
  final IgnoredPatternMatchMode mode;

  Map<String, Object?> toJson() => {
    'value': value,
    'mode': mode == IgnoredPatternMatchMode.exact ? 'exact' : 'contains',
  };
}

/// Patterns hidden by default — Buoy's own license API traffic.
const _defaultPatterns = [
  IgnoredPattern('api.keygen.sh', IgnoredPatternMatchMode.contains),
];

const _storageKey = '@react_buoy_network_ignored_domains';

/// `contains` → case-insensitive substring on the full URL.
/// `exact`    → smart equality: `/path` compares pathname, full URLs compare
/// origin+pathname, bare values compare host. Literal equality if parsing
/// fails (RN parity).
bool urlMatchesIgnoredPattern(String url, IgnoredPattern pattern) {
  final lowerUrl = url.toLowerCase();
  final lowerValue = pattern.value.toLowerCase();
  if (pattern.mode == IgnoredPatternMatchMode.contains) {
    return lowerUrl.contains(lowerValue);
  }
  final parsed = Uri.tryParse(url);
  if (parsed == null || !parsed.hasScheme) return lowerUrl == lowerValue;
  if (lowerValue.startsWith('/')) {
    return parsed.path.toLowerCase() == lowerValue;
  }
  // URL.host in JS includes the port when non-default.
  final host = parsed.hasPort ? '${parsed.host}:${parsed.port}' : parsed.host;
  if (lowerValue.startsWith('http://') || lowerValue.startsWith('https://')) {
    // Manual origin (Uri.origin throws for non-http schemes like ws://).
    return '${parsed.scheme}://$host${parsed.path}'.toLowerCase() == lowerValue;
  }
  return host.toLowerCase() == lowerValue;
}

/// Singleton store; notifies on every mutation, hydrates lazily on first
/// listener (RN parity: a slow load never clobbers a user mutation).
class IgnoredPatternsStore extends ChangeNotifier {
  IgnoredPatternsStore._();
  static final IgnoredPatternsStore instance = IgnoredPatternsStore._();

  List<IgnoredPattern> _patterns = List.of(_defaultPatterns);
  bool _loaded = false;
  bool _loading = false;
  bool _dirty = false;

  List<IgnoredPattern> get patterns => List.unmodifiable(_patterns);

  Set<String> get values => {for (final p in _patterns) p.value};

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _ensureLoaded();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && !_dirty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _patterns = _ensureDefaults(_migrate(decoded));
        }
      }
    } catch (_) {
      // Fall back to defaults.
    } finally {
      _loaded = true;
      _loading = false;
      notifyListeners();
    }
  }

  /// Tolerates the legacy `string[]` persisted format (RN migratePatterns).
  static List<IgnoredPattern> _migrate(List<Object?> raw) {
    final migrated = <IgnoredPattern>[];
    for (final entry in raw) {
      if (entry is String && entry.trim().isNotEmpty) {
        migrated.add(IgnoredPattern(entry, IgnoredPatternMatchMode.contains));
      } else if (entry is Map && entry['value'] is String) {
        migrated.add(
          IgnoredPattern(
            entry['value'] as String,
            entry['mode'] == 'exact'
                ? IgnoredPatternMatchMode.exact
                : IgnoredPatternMatchMode.contains,
          ),
        );
      }
    }
    return migrated;
  }

  static List<IgnoredPattern> _ensureDefaults(List<IgnoredPattern> patterns) {
    final result = List.of(patterns);
    for (final def in _defaultPatterns) {
      if (!result.any((p) => p.value == def.value)) result.add(def);
    }
    return result;
  }

  void _commit(List<IgnoredPattern> next) {
    _dirty = true;
    _patterns = next;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode([for (final p in _patterns) p.toJson()]),
      );
    } catch (_) {
      // Patterns remain in memory.
    }
  }

  void add(IgnoredPattern pattern) {
    final value = pattern.value.trim();
    if (value.isEmpty) return;
    if (_patterns.any((p) => p.value == value)) return;
    _commit([..._patterns, IgnoredPattern(value, pattern.mode)]);
  }

  void remove(String value) {
    if (!_patterns.any((p) => p.value == value)) return;
    _commit([..._patterns.where((p) => p.value != value)]);
  }

  /// Add as `contains` if absent, otherwise remove (detail-view chips).
  void toggle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _commit(
      _patterns.any((p) => p.value == trimmed)
          ? [..._patterns.where((p) => p.value != trimmed)]
          : [
              ..._patterns,
              IgnoredPattern(trimmed, IgnoredPatternMatchMode.contains),
            ],
    );
  }

  void toggleMode(String value) {
    if (!_patterns.any((p) => p.value == value)) return;
    _commit([
      for (final p in _patterns)
        p.value == value
            ? IgnoredPattern(
                p.value,
                p.mode == IgnoredPatternMatchMode.contains
                    ? IgnoredPatternMatchMode.exact
                    : IgnoredPatternMatchMode.contains,
              )
            : p,
    ]);
  }
}
