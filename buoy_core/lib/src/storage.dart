import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants.dart';
import 'core/dial_usage.dart';

/// Persisted tool-visibility preferences — the Dart mirror of the RN
/// `DevToolsSettings` blob (same JSON shape, same storage key, so a future
/// shared backend stays compatible).
class BuoyDevToolsSettings {
  BuoyDevToolsSettings({
    Map<String, bool>? dialTools,
    Map<String, bool>? floatingTools,
    this.enableSharedModalDimensions = false,
    this.expandableWindowControls = true,
  }) : dialTools = dialTools ?? {},
       floatingTools = floatingTools ?? {'environment': false};

  final Map<String, bool> dialTools;
  final Map<String, bool> floatingTools;

  /// GlobalDevToolsSettings.enableSharedModalDimensions (default false).
  bool enableSharedModalDimensions;

  /// GlobalDevToolsSettings.expandableWindowControls (default true).
  bool expandableWindowControls;

  Map<String, Object?> toJson() => {
    'dialTools': dialTools,
    'floatingTools': floatingTools,
    'globalSettings': {
      'enableSharedModalDimensions': enableSharedModalDimensions,
      'expandableWindowControls': expandableWindowControls,
    },
  };

  static BuoyDevToolsSettings fromJson(Map<String, Object?> json) {
    Map<String, bool> section(String key) {
      final raw = json[key];
      if (raw is! Map) return {};
      return {
        for (final entry in raw.entries)
          if (entry.value is bool) entry.key.toString(): entry.value as bool,
      };
    }

    final floating = section('floatingTools');
    floating.putIfAbsent('environment', () => false);
    final global = json['globalSettings'];
    return BuoyDevToolsSettings(
      dialTools: section('dialTools'),
      floatingTools: floating,
      enableSharedModalDimensions:
          global is Map && global['enableSharedModalDimensions'] == true,
      // RN defaults this ON when undefined.
      expandableWindowControls:
          global is! Map || global['expandableWindowControls'] != false,
    );
  }
}

/// Persistence for the floating menu, using the same `@react_buoy` key names
/// as the RN package. Position writes are debounced (500 ms, RN parity) so
/// drag/animation streams don't hammer the platform channel.
class BuoyStorage {
  BuoyStorage() {
    // Kick off the usage load eagerly (RN loads on module import) so
    // rankDialToolIds can usually run synchronously by the time the dial
    // opens.
    loadDialUsage();
  }

  Timer? _positionSaveTimer;

  // Dial usage — the Dart mirror of RN's `dialUsageStore.ts`: a persisted,
  // in-memory cache over the pure scoring logic in core/dial_usage.dart.
  Map<String, UsageEntry> _dialUsage = {};
  bool _dialUsageLoaded = false;
  Future<void>? _dialUsageLoad;

  /// Load persisted usage data into the in-memory cache. Safe to call
  /// multiple times — the underlying read happens only once.
  Future<void> loadDialUsage() {
    return _dialUsageLoad ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(BuoyStorageKeys.dialUsage);
        if (raw != null) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final parsed = <String, UsageEntry>{};
            for (final entry in decoded.entries) {
              final usage = UsageEntry.fromJson(entry.value);
              if (usage != null) parsed[entry.key.toString()] = usage;
            }
            _dialUsage = parsed;
          }
        }
      } catch (_) {
        // Ignore — start with an empty usage map.
      } finally {
        _dialUsageLoaded = true;
      }
    }();
  }

  /// Whether the usage cache has finished loading from storage.
  bool get isDialUsageLoaded => _dialUsageLoaded;

  /// Rank tool ids by recency-weighted usage, highest first. Synchronous —
  /// operates against the in-memory cache. Never-used tools keep their
  /// original order as a tie-breaker.
  List<String> rankDialToolIds(List<String> orderedIds) {
    return rankToolIds(
      orderedIds,
      _dialUsage,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Record a single press of a tool and persist the updated usage map.
  Future<void> recordDialToolUsage(String id) async {
    if (id.isEmpty) return;
    if (!_dialUsageLoaded) await loadDialUsage();

    final now = DateTime.now().millisecondsSinceEpoch;
    _dialUsage = pruneUsage(recordUsage(_dialUsage, id, now), now);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        BuoyStorageKeys.dialUsage,
        jsonEncode({
          for (final entry in _dialUsage.entries)
            entry.key: entry.value.toJson(),
        }),
      );
    } catch (_) {
      // Ignore persistence failure — the in-memory cache is still updated.
    }
  }

  /// Clear all usage data (in-memory and persisted).
  Future<void> resetDialUsage() async {
    _dialUsage = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(BuoyStorageKeys.dialUsage);
    } catch (_) {
      // Ignore — the in-memory cache is already cleared.
    }
  }

  Future<({double x, double y})?> loadBubblePosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(BuoyStorageKeys.bubblePositionX);
    final y = prefs.getDouble(BuoyStorageKeys.bubblePositionY);
    if (x == null || y == null) return null;
    return (x: x, y: y);
  }

  Future<void> saveBubblePosition(double x, double y) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(BuoyStorageKeys.bubblePositionX, x);
    await prefs.setDouble(BuoyStorageKeys.bubblePositionY, y);
  }

  void saveBubblePositionDebounced(double x, double y) {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(saveDebounce, () => saveBubblePosition(x, y));
  }

  Future<bool> loadDialOpen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(BuoyStorageKeys.dialIsOpen) ?? false;
  }

  Future<void> saveDialOpen(bool open) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(BuoyStorageKeys.dialIsOpen, open);
  }

  Future<bool> loadSettingsOpen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(BuoyStorageKeys.settingsModalOpen) ?? false;
  }

  Future<void> saveSettingsOpen(bool open) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(BuoyStorageKeys.settingsModalOpen, open);
  }

  Future<String?> loadSettingsActiveTab() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(BuoyStorageKeys.settingsActiveTab);
  }

  Future<void> saveSettingsActiveTab(String tab) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BuoyStorageKeys.settingsActiveTab, tab);
  }

  /// The tools that were open at last close (RN AppHost `@react_buoy_open_apps`).
  /// Stored as a JSON array of `{id, minimized}`; also tolerates RN's legacy
  /// `string[]` (bare ids, all treated as non-minimized).
  Future<List<({String id, bool minimized})>> loadOpenApps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(BuoyStorageKeys.openApps);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <({String id, bool minimized})>[];
      for (final entry in decoded) {
        if (entry is String) {
          result.add((id: entry, minimized: false));
        } else if (entry is Map) {
          final id = entry['id'];
          if (id is String) {
            result.add((id: id, minimized: entry['minimized'] == true));
          }
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveOpenApps(List<({String id, bool minimized})> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BuoyStorageKeys.openApps,
      jsonEncode([
        for (final app in apps) {'id': app.id, 'minimized': app.minimized},
      ]),
    );
  }

  /// Whether the minimized-tools stack was left expanded (RN
  /// ExpandablePopover persistState). RN stores the string "true"/"false".
  Future<bool> loadMinimizedStackExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(BuoyStorageKeys.minimizedStackExpanded) == 'true';
  }

  Future<void> saveMinimizedStackExpanded(bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BuoyStorageKeys.minimizedStackExpanded,
      expanded ? 'true' : 'false',
    );
  }

  Future<BuoyDevToolsSettings> loadDevToolsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(BuoyStorageKeys.devToolsSettings);
    if (raw == null) return BuoyDevToolsSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return BuoyDevToolsSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return BuoyDevToolsSettings.fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {
      // Corrupt blob — fall through to defaults.
    }
    return BuoyDevToolsSettings();
  }

  Future<void> saveDevToolsSettings(BuoyDevToolsSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BuoyStorageKeys.devToolsSettings,
      jsonEncode(settings.toJson()),
    );
  }

  /// Generic JSON blob storage (JsModal per-modal state etc.).
  Future<Map<String, Object?>?> loadJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {}
    return null;
  }

  Future<void> saveJson(String key, Map<String, Object?> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  /// All persisted `@react_buoy` keys (the settings modal's SAVED SETTINGS
  /// list).
  Future<List<String>> listBuoyKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs
            .getKeys()
            .where((key) => key.startsWith(BuoyStorageKeys.prefix))
            .toList()
          ..sort();
    return keys;
  }

  /// Clear every persisted `@react_buoy` key (the modal's CLEAR ALL
  /// SETTINGS action — scoped so app data is untouched).
  Future<void> clearBuoyKeys() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in await listBuoyKeys()) {
      await prefs.remove(key);
    }
  }

  void dispose() {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
  }
}
