/// Ports packages/storage/src/storage/components/GameUIStorageBrowser.tsx +
/// StorageBrowserMode + StorageKeySection + hooks/useAsyncStorageKeys.ts.
///
/// The Storage tab: reads every shared_preferences key/value directly (RN's
/// useAsyncStorageKeys), plus any registered MMKV / SecureStore backend (RN's
/// useMMKVKeys / useSecureStoreKeys), renders the [StorageFilterCards] stats
/// header, then the filtered/pinned list of [StorageKeyRow]s. Refreshes on a 1s
/// timer so writes made through any path surface even without the monitor (RN
/// parity: the browser reads live, independent of the Events monitor toggle).
/// SecureStore rides a slower 3s re-read (every read hits the keychain), which
/// is the only way to see a secure write: the keychain has no change feed.
///
/// Editing lives here too (RN `handleSaveValue` / `handleToggleKey`): the row
/// offers one Edit button, the write it eventually performs needs the backend
/// registries this screen already holds, and the editor covers the browser
/// rather than replacing it — so closing returns you to the same scroll
/// position in the same expanded card, which matters when the key you were
/// editing was forty rows down.
///
/// Dropped vs RN (deviations, see storage.md): MMKV instance navbar, select-mode
/// bulk actions, Pro locked-key banner. Pin/hide remain in the row body.
library;

import 'dart:async';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_capture.dart';
import 'key_editor.dart';
import 'set_storage_value.dart';
import 'storage_alert.dart';
import 'storage_filter_cards.dart';
import 'storage_key_detail_screen.dart';
import 'storage_key_row.dart';
import 'storage_models.dart';

class StorageBrowserScreen extends StatefulWidget {
  const StorageBrowserScreen({
    super.key,
    required this.searchQuery,
    required this.ignoredPatterns,
    required this.enabledStorageTypes,
    required this.pinnedKeys,
    required this.eventCountByKey,
    required this.onTogglePin,
    required this.onAddPattern,
    required this.onViewHistory,
    required this.onKeysLoaded,
    this.applySafeAreaInset = false,
  });

  final String searchQuery;
  final Set<String> ignoredPatterns;
  final Set<String> enabledStorageTypes;
  final Set<String> pinnedKeys;
  final Map<String, int> eventCountByKey;
  final ValueChanged<String> onTogglePin;
  final ValueChanged<String> onAddPattern;
  final ValueChanged<String> onViewHistory;
  final ValueChanged<List<StorageKeyInfo>> onKeysLoaded;

  /// Pad the editor's docked controls past the home indicator — only while the
  /// modal is a bottom sheet, whose bottom edge IS the screen's.
  final bool applySafeAreaInset;

  @override
  State<StorageBrowserScreen> createState() => _StorageBrowserScreenState();
}

class _StorageBrowserScreenState extends State<StorageBrowserScreen> {
  List<StorageKeyInfo> _all = [];
  List<StorageKeyInfo> _secure = const [];
  bool _loaded = false;
  Timer? _timer;
  String? _expandedKey;

  /// Keychain reads are the expensive ones, so SecureStore re-reads every
  /// [_secureEveryTicks] ticks of the 1s refresh instead of every tick.
  static const int _secureEveryTicks = 3;
  int _tick = 0;
  bool _secureInFlight = false;
  String? _secureSignature;

  StorageFilterType _filter = StorageFilterType.all;
  StorageTypeFilter _typeFilter = StorageTypeFilter.all;

  /// The key whose editor is open, or null. Held here rather than in the row
  /// because the editor covers the WHOLE browser, and because the write it
  /// eventually performs is [_saveValue] — which needs the backend registries
  /// and the refresh fan-out that live at this level (RN `editingKey`).
  StorageKeyInfo? _editingKey;

  /// Why each key can't be edited, memoized per refresh: the reasons come from
  /// the secure backend's descriptors, which are a method call away, and the
  /// browser rebuilds every second.
  Map<String, String?> _editBlocked = const {};

  /// A failed toggle, shown as an alert (RN's `Alert.alert("Couldn't save")`).
  String? _saveFailure;

  @override
  void initState() {
    super.initState();
    _loadSecure();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick++;
      if (_tick % _secureEveryTicks == 0) _loadSecure();
      _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList()..sort();
    final list = [
      for (final key in keys)
        // Buoy's own keys are never app data (RN GameUIStorageBrowser splits
        // them off with isDevToolsStorageKey). Matching it keeps the browser
        // honest: the Events monitor ignores these keys, so listing one shows a
        // key that can never produce an event.
        if (!isDevToolsStorageKey(key))
          StorageKeyInfo(
            key: key,
            value: parseValue(prefs.get(key)),
            // The editor needs the slot's native type, which `parseValue`
            // erases — see StorageKeyInfo.rawValue.
            rawValue: prefs.get(key),
          ),
      ..._mmkvKeys(),
      // Re-read on the slower secure cadence (see _loadSecure), carried
      // across the ticks in between.
      ..._secure,
    ];
    if (!mounted) return;
    setState(() {
      _all = list;
      _loaded = true;
    });
    widget.onKeysLoaded(list);
    unawaited(_refreshEditBlocked(list));
  }

  /// Recompute the per-key "why not" only for the backends that can have one —
  /// every shared_preferences key is editable, so asking would be pure work.
  Future<void> _refreshEditBlocked(List<StorageKeyInfo> keys) async {
    final blocked = <String, String?>{};
    for (final info in keys) {
      if (info.storageType == 'async') continue;
      blocked[_rowId(info)] = await storageEditBlockedReason(info);
    }
    if (!mounted || mapEquals(blocked, _editBlocked)) return;
    setState(() => _editBlocked = blocked);
  }

  /// The freshest row for [editing] — the browser re-reads every second and
  /// the live editor's round-trip logic keys off the CURRENT prop value.
  StorageKeyInfo _currentInfoFor(StorageKeyInfo editing) {
    final id = _rowId(editing);
    for (final k in _all) {
      if (_rowId(k) == id) return k;
    }
    return editing;
  }

  /// The single write, for both the editor and the card's boolean toggle.
  ///
  /// Refreshes on success so the row shows what the device now holds rather
  /// than what the editor sent — those differ whenever a backend coerces.
  Future<void> _saveValue(StorageKeyInfo storageKey, String raw) async {
    await setStorageValue(storageKey, raw);
    await _refresh();
  }

  /// Flip a boolean key straight from its card.
  ///
  /// Goes through [_saveValue] like every other write, so the type preservation
  /// is the same one the editor uses — this is only a shortcut past the UI, not
  /// past the rules.
  void _toggleKey(StorageKeyInfo storageKey) {
    _saveValue(storageKey, jsonEncodeValue(storageKey.value != true)).catchError(
      (Object e) {
        if (!mounted) return;
        setState(() => _saveFailure = messageOfStorageError(e));
      },
    );
  }

  /// Registered MMKV instances, flattened into rows (RN's useMMKVKeys). Cheap
  /// and enumerable, so it rides the same 1s refresh as shared_preferences.
  List<StorageKeyInfo> _mmkvKeys() {
    final entries = readBuoyMmkvEntries().values.toList()
      ..sort((a, b) {
        final byInstance = a.instanceId.compareTo(b.instanceId);
        return byInstance != 0 ? byInstance : a.key.compareTo(b.key);
      });
    return [
      for (final e in entries)
        StorageKeyInfo(
          key: e.key,
          value: parseValue(e.value),
          rawValue: e.value,
          storageType: 'mmkv',
          instanceId: e.instanceId,
          // The MMKV native type decides what a write puts back, and `buffer`
          // is why some rows can't be edited at all.
          valueType: e.valueType,
        ),
    ];
  }

  /// Registered SecureStore keys (RN's useSecureStoreKeys). Biometric keys are
  /// listed without a read. Re-read on the slower cadence rather than once on
  /// mount: nothing notifies on a keychain write, so a value the app changes
  /// while the tool is open would otherwise stay stale until the tool reopens.
  Future<void> _loadSecure() async {
    if (_secureInFlight) return;
    _secureInFlight = true;
    final List<SecureEntry> entries;
    try {
      entries = await readBuoySecureEntries();
    } finally {
      _secureInFlight = false;
    }
    if (entries.isEmpty || !mounted) return;
    final signature = entries.map((e) => '${e.key}=${e.value}').join(' ');
    if (signature == _secureSignature) return;
    _secureSignature = signature;
    _secure = [
      for (final e in entries)
        StorageKeyInfo(
          key: e.key,
          value: e.value == null ? null : parseValue(e.value),
          rawValue: e.value,
          storageType: 'secure',
          status: e.value == null ? 'required_missing' : 'optional_present',
          category: e.value == null ? 'required' : 'optional',
          instanceId: e.keychainService,
        ),
    ];
    // Only rebuild when the keychain actually moved — an unchanged poll costs
    // nothing, and the 1s _refresh folds _secure back into the list either way.
    _refresh();
  }

  List<StorageKeyInfo> get _filtered {
    var keys = _all;
    // Enabled storage types (async-only in the Flutter default).
    keys = keys
        .where((k) => widget.enabledStorageTypes.contains(k.storageType))
        .toList();
    // Ignored patterns.
    keys = keys
        .where((k) => !widget.ignoredPatterns.any(k.key.contains))
        .toList();
    // Search.
    if (widget.searchQuery.isNotEmpty) {
      final q = widget.searchQuery.toLowerCase();
      keys = keys.where((k) => k.key.toLowerCase().contains(q)).toList();
    }
    // Status filter (all shared_preferences keys are optional_present → 'all').
    keys = switch (_filter) {
      StorageFilterType.all => keys
          .where((k) =>
              k.status == 'required_present' || k.status == 'optional_present')
          .toList(),
      StorageFilterType.missing =>
        keys.where((k) => k.status == 'required_missing').toList(),
      StorageFilterType.issues => keys
          .where((k) =>
              k.status == 'required_wrong_type' ||
              k.status == 'required_wrong_value')
          .toList(),
    };
    // Storage-type filter.
    if (_typeFilter != StorageTypeFilter.all) {
      keys = keys.where((k) => k.storageType == _typeFilter.name).toList();
    }
    // Pinned to top (stable).
    if (widget.pinnedKeys.isNotEmpty) {
      final pinned = keys.where((k) => widget.pinnedKeys.contains(k.key));
      final rest = keys.where((k) => !widget.pinnedKeys.contains(k.key));
      keys = [...pinned, ...rest];
    }
    return keys;
  }

  int _count(bool Function(StorageKeyInfo) test) => _all
      .where((k) => widget.enabledStorageTypes.contains(k.storageType))
      .where((k) => !widget.ignoredPatterns.any(k.key.contains))
      .where(test)
      .length;

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const _CenterMessage(
        icon: BuoyIcons.database,
        title: 'Loading storage keys...',
      );
    }

    final filtered = _filtered;
    final valid = _count((k) =>
        k.status == 'required_present' || k.status == 'optional_present');
    final missing = _count((k) => k.status == 'required_missing');
    final issues = _count((k) =>
        k.status == 'required_wrong_type' || k.status == 'required_wrong_value');
    final asyncCount = _count((k) => k.storageType == 'async');
    final mmkvCount = _count((k) => k.storageType == 'mmkv');
    final secureCount = _count((k) => k.storageType == 'secure');

    return Stack(
      children: [
        _list(filtered, valid, missing, issues, asyncCount, mmkvCount,
            secureCount),

        // The editor covers the browser rather than replacing it — see the
        // library docstring.
        // RN (Aug 2026) replaced the draft-and-Save editor with the LIVE
        // detail screen: edits write through as you make them. The editor
        // still covers the browser rather than replacing it; the host header
        // isn't ours to change, so the screen carries its own back row.
        if (_editingKey case final editing?)
          Positioned.fill(
            child: _DetailHost(
              key: ValueKey(_rowId(editing)),
              storageKey: _currentInfoFor(editing),
              editBlockedReason: _editBlocked[_rowId(editing)],
              eventCount: widget.eventCountByKey[editing.key],
              isPinned: widget.pinnedKeys.contains(editing.key),
              onTogglePin: widget.onTogglePin,
              onViewHistory: () => widget.onViewHistory(editing.key),
              onHideKey: (k) {
                widget.onAddPattern(k.key);
                setState(() => _editingKey = null);
              },
              onSave: (raw) => _saveValue(editing, raw),
              onClose: () => setState(() => _editingKey = null),
              applySafeAreaInset: widget.applySafeAreaInset,
            ),
          ),

        if (_saveFailure case final failure?)
          StorageAlert(
            title: 'Couldn\'t save',
            message: failure,
            cancelLabel: 'OK',
            onCancel: () => setState(() => _saveFailure = null),
            actions: const [],
          ),
      ],
    );
  }

  Widget _list(
    List<StorageKeyInfo> filtered,
    int valid,
    int missing,
    int issues,
    int asyncCount,
    int mmkvCount,
    int secureCount,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        StorageFilterCards(
          validCount: valid,
          missingCount: missing,
          issuesCount: issues,
          totalCount: asyncCount + mmkvCount + secureCount,
          asyncCount: asyncCount,
          mmkvCount: mmkvCount,
          secureCount: secureCount,
          activeFilter: _filter,
          onFilterChange: (f) => setState(() => _filter = f),
          activeStorageType: _typeFilter,
          onStorageTypeChange: (t) => setState(() => _typeFilter = t),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          _CenterMessage(
            icon: BuoyIcons.database,
            title: widget.searchQuery.isNotEmpty
                ? 'No results found'
                : 'No keys found',
            subtitle: widget.searchQuery.isNotEmpty
                ? 'No keys matching "${widget.searchQuery}"'
                : 'Storage keys will appear here',
          )
        else
          _KeysSection(
            keys: filtered,
            expandedKey: _expandedKey,
            eventCountByKey: widget.eventCountByKey,
            pinnedKeys: widget.pinnedKeys,
            onToggle: (key) => setState(
              () => _expandedKey = _expandedKey == key ? null : key,
            ),
            onTogglePin: widget.onTogglePin,
            onHideKey: (info) => widget.onAddPattern(info.key),
            onViewHistory: widget.onViewHistory,
            onEditKey: (info) => setState(() => _editingKey = info),
            onToggleKey: _toggleKey,
            editBlocked: _editBlocked,
          ),
        const SizedBox(height: 20),
        const Text(
          'SHARED PREFERENCES | SECURE | MMKV BACKENDS',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 8,
            color: MacOSColors.textMuted,
            fontFamily: 'monospace',
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

String _rowId(StorageKeyInfo info) =>
    '${info.storageType}-${info.instanceId ?? ''}-${info.key}';

class _KeysSection extends StatelessWidget {
  const _KeysSection({
    required this.keys,
    required this.expandedKey,
    required this.eventCountByKey,
    required this.pinnedKeys,
    required this.onToggle,
    required this.onTogglePin,
    required this.onHideKey,
    required this.onViewHistory,
    required this.onEditKey,
    required this.onToggleKey,
    required this.editBlocked,
  });

  final List<StorageKeyInfo> keys;
  final String? expandedKey;
  final Map<String, int> eventCountByKey;
  final Set<String> pinnedKeys;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onTogglePin;
  final ValueChanged<StorageKeyInfo> onHideKey;
  final ValueChanged<String> onViewHistory;
  final ValueChanged<StorageKeyInfo> onEditKey;
  final ValueChanged<StorageKeyInfo> onToggleKey;

  /// Row id → why that key can't be edited (absent means it can).
  final Map<String, String?> editBlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MacOSColors.backgroundBase,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              children: [
                const Text(
                  'KEYS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MacOSColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: MacOSColors.backgroundCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: MacOSColors.borderDefault),
                  ),
                  child: Text(
                    '${keys.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: MacOSColors.textPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final info in keys)
            StorageKeyRow(
              key: ValueKey(_rowId(info)),
              info: info,
              // Row identity is type+key: the same key name can exist in more
              // than one backend, and only the tapped row should expand.
              isExpanded: expandedKey == _rowId(info),
              onToggle: () => onToggle(_rowId(info)),
              eventCount: eventCountByKey[info.key],
              isPinned: pinnedKeys.contains(info.key),
              onTogglePin: onTogglePin,
              onHideKey: onHideKey,
              onViewHistory: () => onViewHistory(info.key),
              onEditKey: onEditKey,
              onToggleKey: onToggleKey,
              editBlockedReason: editBlocked[_rowId(info)],
            ),
        ],
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({required this.icon, required this.title, this.subtitle});

  final LucideIcon icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          BuoyGlyph(icon, size: 32, color: MacOSColors.textMuted),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: MacOSColors.textPrimary,
              ),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: MacOSColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}


/// The detail screen plus the back row the host header would carry on RN.
class _DetailHost extends StatelessWidget {
  const _DetailHost({
    super.key,
    required this.storageKey,
    required this.onSave,
    required this.onClose,
    this.editBlockedReason,
    this.eventCount,
    this.onViewHistory,
    this.onHideKey,
    this.isPinned = false,
    this.onTogglePin,
    this.applySafeAreaInset = false,
  });

  final StorageKeyInfo storageKey;
  final Future<void> Function(String raw) onSave;
  final VoidCallback onClose;
  final String? editBlockedReason;
  final int? eventCount;
  final VoidCallback? onViewHistory;
  final ValueChanged<StorageKeyInfo>? onHideKey;
  final bool isPinned;
  final ValueChanged<String>? onTogglePin;
  final bool applySafeAreaInset;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: NightColor.bg,
      child: Column(
        children: [
          ModalHeader(
            children: [
              ModalHeaderBack(onBack: onClose),
              ModalHeaderContent(title: storageKey.key),
            ],
          ),
          Expanded(
            child: StorageKeyDetailScreen(
              storageKey: storageKey,
              onSave: onSave,
              editBlockedReason: editBlockedReason,
              eventCount: eventCount,
              onViewHistory: onViewHistory,
              onHideKey: onHideKey,
              isPinned: isPinned,
              onTogglePin: onTogglePin,
              applySafeAreaInset: applySafeAreaInset,
            ),
          ),
        ],
      ),
    );
  }
}
