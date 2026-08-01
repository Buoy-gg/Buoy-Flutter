/// Ports packages/storage/src/storage/components/StorageModalWithTabs.tsx —
/// the storage tool's root surface.
///
/// Opens in a [JsModal] with the RN persistence key (`@react_buoy_storage_modal`)
/// and a Storage/Events [TabSelector]. The header carries a filter toggle,
/// search (Storage tab), a copy button, and — on the Events tab — the power
/// (monitor) toggle + clear. Screens: browser, the browser's per-key history
/// flow ("view history" → event list → event detail, RN `selectedHistoryKey` /
/// `selectedHistoryEventIndex`), events stream, a key's event detail
/// (`selectedConversationKey` + `selectedEventIndex`), and the shared Filters
/// overlay.
///
/// Monitoring lifecycle mirrors RN: the Events subscription (gated by the power
/// toggle) starts/stops the [StorageEventStore] capture, i.e. the poll/diff +
/// initial scan. Persisted state uses the RN storage keys byte-for-byte.
library;

import 'dart:async';
import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_capture.dart';
import 'storage_browser_screen.dart';
import 'storage_event_card.dart';
import 'storage_event_detail.dart';
import 'storage_filter_view.dart';
import 'storage_models.dart';

const _defaultIgnored = {
  '@react_buoy',
  '@RNAsyncStorage',
  'redux-persist',
  'persist:',
};
const _allStorageTypes = {'async', 'mmkv', 'secure'};

class StorageModal extends StatefulWidget {
  const StorageModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<StorageModal> createState() => _StorageModalState();
}

class _StorageModalState extends State<StorageModal> {
  String _activeTab = 'browser';
  String _searchQuery = '';
  bool _isSearchActive = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  bool _monitoringEnabled = true;
  void Function()? _unsubscribe;
  List<StorageEvent> _events = const [];

  Set<String> _ignoredPatterns = {..._defaultIgnored};
  final Set<String> _enabledStorageTypes = {..._allStorageTypes};
  Set<String> _pinnedKeys = {};

  bool _showFilters = false;
  String? _selectedConversationKey;
  int _selectedEventIndex = 0;
  String? _selectedHistoryKey;
  int? _selectedHistoryEventIndex;
  List<StorageKeyInfo> _browserKeys = const [];

  // Track the modal's presentation mode so the stepper footer only reserves
  // safe-area bottom padding while docked as a bottom sheet. In floating mode
  // the footer isn't pinned to the screen edge, so that inset is dead space.
  JsModalMode _modalMode = JsModalMode.bottomSheet;

  final _keys = devToolsStorageKeys.storage;

  @override
  void initState() {
    super.initState();
    MinuteTicker.instance.retain();
    _loadPersisted();
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text != _searchQuery) setState(() => _searchQuery = text);
    });
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus && _isSearchActive) {
        setState(() => _isSearchActive = false);
      }
    });
    _subscribeIfEnabled();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    MinuteTicker.instance.release();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Persistence (RN storage keys, byte-identical) ──────────────────────

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final tab = prefs.getString(_keys.activeTab());
      if (tab == 'browser' || tab == 'events') _activeTab = tab!;

      final monitoring = prefs.getString(_keys.isMonitoring());
      if (monitoring != null) _monitoringEnabled = monitoring == 'true';

      final filters = prefs.getString(_keys.eventFilters());
      if (filters != null) {
        try {
          final list = (jsonDecode(filters) as List).cast<String>().toSet();
          list.add('@react_buoy'); // always hide dev-tool keys (RN parity)
          _ignoredPatterns = list;
        } catch (_) {}
      }

      final pins = prefs.getString(_keys.pinnedKeys());
      if (pins != null) {
        try {
          _pinnedKeys = (jsonDecode(pins) as List).cast<String>().toSet();
        } catch (_) {}
      }
    });
    _subscribeIfEnabled();
  }

  Future<void> _save(String key, String value) async {
    (await SharedPreferences.getInstance()).setString(key, value);
  }

  // ── Monitoring subscription ────────────────────────────────────────────

  void _subscribeIfEnabled() {
    if (_monitoringEnabled && _unsubscribe == null) {
      _unsubscribe = StorageEventStore.instance.subscribeToEvents((events) {
        if (mounted) setState(() => _events = events);
      });
    } else if (!_monitoringEnabled && _unsubscribe != null) {
      _unsubscribe!();
      _unsubscribe = null;
    }
  }

  void _toggleMonitoring() {
    setState(() => _monitoringEnabled = !_monitoringEnabled);
    _subscribeIfEnabled();
    _save(_keys.isMonitoring(), _monitoringEnabled.toString());
  }

  // ── Filters / pins ─────────────────────────────────────────────────────

  void _addPattern(String pattern) {
    if (pattern.isEmpty) return;
    setState(() => _ignoredPatterns = {..._ignoredPatterns, pattern});
    _save(_keys.eventFilters(), jsonEncode(_ignoredPatterns.toList()));
  }

  void _removePattern(String pattern) {
    setState(() => _ignoredPatterns = {..._ignoredPatterns}..remove(pattern));
    _save(_keys.eventFilters(), jsonEncode(_ignoredPatterns.toList()));
  }

  void _toggleStorageType(String type) {
    setState(() {
      if (_enabledStorageTypes.contains(type)) {
        _enabledStorageTypes.remove(type);
      } else {
        _enabledStorageTypes.add(type);
      }
    });
  }

  void _togglePin(String key) {
    setState(() {
      if (_pinnedKeys.contains(key)) {
        _pinnedKeys = {..._pinnedKeys}..remove(key);
      } else {
        _pinnedKeys = {..._pinnedKeys, key};
      }
    });
    _save(_keys.pinnedKeys(), jsonEncode(_pinnedKeys.toList()));
  }

  void _setTab(String tab) {
    setState(() {
      _activeTab = tab;
      _selectedConversationKey = null;
      _selectedEventIndex = 0;
      _selectedHistoryKey = null;
      _selectedHistoryEventIndex = null;
    });
    _save(_keys.activeTab(), tab);
  }

  /// RN `handleRawEventPress`: open the tapped event's conversation at the
  /// matching chronological index.
  void _openEventDetail(StorageEvent event) {
    StorageConversation? conversation;
    for (final c in _conversations) {
      if (c.key == event.key) conversation = c;
    }
    if (conversation == null) return;
    final asc = [...conversation.events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final index = asc.indexWhere((e) => e.id == event.id);
    setState(() {
      _selectedConversationKey = event.key;
      _selectedEventIndex = index >= 0 ? index : 0;
    });
  }

  // ── Derived ────────────────────────────────────────────────────────────

  List<StorageConversation> get _conversations => buildConversations(
    _events,
    ignoredPatterns: _ignoredPatterns,
    enabledStorageTypes: _enabledStorageTypes,
  );

  List<StorageEvent> get _filteredEvents => filterStorageEvents(
    _events,
    ignoredPatterns: _ignoredPatterns,
    enabledStorageTypes: _enabledStorageTypes,
  );

  Map<String, int> get _eventCountByKey => {
    for (final c in _conversations) c.key: c.totalOperations,
  };

  StorageConversation? get _selectedConversation {
    final key = _selectedConversationKey;
    if (key == null) return null;
    for (final c in _conversations) {
      if (c.key == key) return c;
    }
    return null;
  }

  StorageConversation? get _selectedHistoryConversation {
    final key = _selectedHistoryKey;
    if (key == null) return null;
    for (final c in _conversations) {
      if (c.key == key) return c;
    }
    return null;
  }

  bool get _hasActiveFilters =>
      _ignoredPatterns.length > _defaultIgnored.length ||
      _enabledStorageTypes.length < 3;

  List<String> get _availableKeys {
    final set = <String>{
      for (final k in _browserKeys) k.key,
      for (final e in _events) e.key,
    };
    return set.toList()..sort();
  }

  // ── Copy snapshots ─────────────────────────────────────────────────────

  Object _browserSnapshot() => {
    'timestamp': DateTime.now().toIso8601String(),
    'totalKeys': _browserKeys.length,
    'asyncStorage': {
      for (final k in _browserKeys)
        if (k.storageType == 'async') k.key: truncatePayload(k.value),
    },
    'mmkv': {
      for (final k in _browserKeys)
        if (k.storageType == 'mmkv')
          '${k.instanceId ?? 'default'}/${k.key}': truncatePayload(k.value),
    },
    'secure': {
      for (final k in _browserKeys)
        if (k.storageType == 'secure') k.key: truncatePayload(k.value),
    },
  };

  Object _eventsSnapshot() => [
    for (final e in _filteredEvents)
      {
        'key': e.key,
        'action': e.action,
        'value': truncatePayload(e.value),
        'storageType': e.storageType,
        'timestamp': e.timestamp.toIso8601String(),
      },
  ];

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      onModeChange: (mode) => setState(() => _modalMode = mode),
      persistenceKey: _keys.modal(),
      headerContent: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _header(),
      ),
      wrapChildInScrollView: false,
      child: SizedBox.expand(
        child: ColoredBox(
          color: MacOSColors.backgroundBase,
          child: _screen(),
        ),
      ),
    );
  }

  Widget _screen() {
    if (_showFilters) {
      return StorageFilterView(
        ignoredPatterns: _ignoredPatterns,
        onAddPattern: _addPattern,
        onRemovePattern: _removePattern,
        availableKeys: _availableKeys,
        enabledStorageTypes: _enabledStorageTypes,
        onToggleStorageType: _toggleStorageType,
      );
    }

    if (_activeTab == 'browser') {
      // History flow for a specific key ("view history" in the browser tab).
      final historyConversation = _selectedHistoryConversation;
      if (historyConversation != null) {
        final historyIndex = _selectedHistoryEventIndex;
        // Level 2: detail view for a specific event.
        if (historyIndex != null) {
          return StorageEventDetail(
            conversation: historyConversation,
            selectedEventIndex: historyIndex,
            onEventIndexChange: (index) =>
                setState(() => _selectedHistoryEventIndex = index),
            applySafeAreaInset: _modalMode == JsModalMode.bottomSheet,
          );
        }
        // Level 1: this key's event list (newest-first).
        return _HistoryList(
          conversation: historyConversation,
          onEventPress: (ascIndex) =>
              setState(() => _selectedHistoryEventIndex = ascIndex),
        );
      }

      return StorageBrowserScreen(
        searchQuery: _searchQuery,
        ignoredPatterns: _ignoredPatterns,
        enabledStorageTypes: _enabledStorageTypes,
        pinnedKeys: _pinnedKeys,
        eventCountByKey: _eventCountByKey,
        onTogglePin: _togglePin,
        onAddPattern: _addPattern,
        onViewHistory: (key) => setState(() {
          _selectedHistoryKey = key;
          _selectedHistoryEventIndex = null;
        }),
        onKeysLoaded: (keys) => _browserKeys = keys,
        applySafeAreaInset: _modalMode == JsModalMode.bottomSheet,
      );
    }

    // Events tab: a tapped event's conversation detail, else the raw stream.
    final conversation = _selectedConversation;
    if (conversation != null) {
      return StorageEventDetail(
        conversation: conversation,
        selectedEventIndex: _selectedEventIndex,
        onEventIndexChange: (index) =>
            setState(() => _selectedEventIndex = index),
        applySafeAreaInset: _modalMode == JsModalMode.bottomSheet,
      );
    }

    return _EventsList(
      events: _filteredEvents,
      conversations: _conversations,
      monitoring: _monitoringEnabled,
      onEventPress: _openEventDetail,
    );
  }

  // ── Header states ──────────────────────────────────────────────────────

  Widget _header() {
    if (_showFilters) {
      return ModalHeader(
        children: [
          ModalHeaderBack(onBack: () => setState(() => _showFilters = false)),
          const ModalHeaderContent(title: 'Filters'),
        ],
      );
    }

    // Browser history flow: "<key> History" with level-aware back (RN parity).
    if (_activeTab == 'browser' && _selectedHistoryConversation != null) {
      return ModalHeader(
        children: [
          ModalHeaderBack(
            onBack: () => setState(() {
              if (_selectedHistoryEventIndex != null) {
                _selectedHistoryEventIndex = null;
              } else {
                _selectedHistoryKey = null;
              }
            }),
          ),
          ModalHeaderContent(title: '$_selectedHistoryKey History'),
        ],
      );
    }

    final conversation = _activeTab == 'events' ? _selectedConversation : null;
    if (conversation != null) {
      return ModalHeader(
        children: [
          ModalHeaderBack(
            onBack: () => setState(() {
              _selectedConversationKey = null;
              _selectedEventIndex = 0;
            }),
          ),
          ModalHeaderContent(title: conversation.key),
        ],
      );
    }

    return ModalHeader(
      children: [
        ModalHeaderContent(
          child: _isSearchActive ? _searchField() : _tabs(),
        ),
        ModalHeaderActions(children: _actions()),
      ],
    );
  }

  Widget _tabs() {
    final eventCount = _filteredEvents.length;
    return TabSelector(
      tabs: [
        const (key: 'browser', label: 'Storage'),
        (key: 'events', label: eventCount > 0 ? 'Events ($eventCount)' : 'Events'),
      ],
      activeTab: _activeTab,
      onTabChange: _setTab,
    );
  }

  List<Widget> _actions() {
    return [
      HeaderActionButton(
        icon: BuoyIcons.filter,
        color: _hasActiveFilters ? MacOSColors.debug : MacOSColors.textSecondary,
        active: _hasActiveFilters,
        onTap: () => setState(() => _showFilters = true),
      ),
      if (_activeTab == 'browser' && !_isSearchActive) ...[
        HeaderActionButton(
          icon: BuoyIcons.search,
          color: MacOSColors.textSecondary,
          onTap: () {
            setState(() => _isSearchActive = true);
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _searchFocus.requestFocus());
          },
        ),
        CopyButton(
          value: _browserSnapshot,
          size: 14,
          idleColor: _browserKeys.isEmpty
              ? MacOSColors.textDisabled
              : MacOSColors.textSecondary,
          enabled: _browserKeys.isNotEmpty,
          decoration: headerActionButtonDecoration(),
          width: 32,
          height: 32,
        ),
      ],
      if (_activeTab == 'events') ...[
        CopyButton(
          value: _eventsSnapshot,
          size: 14,
          idleColor: _filteredEvents.isEmpty
              ? MacOSColors.textDisabled
              : MacOSColors.textSecondary,
          enabled: _filteredEvents.isNotEmpty,
          decoration: headerActionButtonDecoration(),
          width: 32,
          height: 32,
        ),
        PowerToggleButton(
          isEnabled: _monitoringEnabled,
          onToggle: _toggleMonitoring,
        ),
        HeaderActionButton(
          icon: BuoyIcons.trash2,
          color: _filteredEvents.isEmpty
              ? MacOSColors.textDisabled
              : MacOSColors.textMuted,
          disabled: _filteredEvents.isEmpty,
          onTap: () {
            StorageEventStore.instance.clearEvents();
            setState(() {
              _selectedConversationKey = null;
              _selectedEventIndex = 0;
            });
          },
        ),
      ],
    ];
  }

  Widget _searchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Row(
        children: [
          const BuoyGlyph(BuoyIcons.search, size: 14, color: MacOSColors.textSecondary),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autocorrect: false,
                onSubmitted: (_) => setState(() => _isSearchActive = false),
                style: const TextStyle(
                  fontSize: 13,
                  color: MacOSColors.textPrimary,
                ),
                cursorColor: MacOSColors.info,
                decoration: const InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search storage keys...',
                  hintStyle:
                      TextStyle(fontSize: 13, color: MacOSColors.textMuted),
                ),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            TouchableOpacity(
              activeOpacity: 0.2,
              onTap: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _isSearchActive = false;
                });
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: BuoyGlyph(BuoyIcons.x,
                    size: 14, color: MacOSColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Events tab list: raw event stream (newest-first) or an empty state (RN
/// StorageModalWithTabs Events branch).
class _EventsList extends StatelessWidget {
  const _EventsList({
    required this.events,
    required this.conversations,
    required this.monitoring,
    required this.onEventPress,
  });

  final List<StorageEvent> events;
  final List<StorageConversation> conversations;
  final bool monitoring;
  final ValueChanged<StorageEvent> onEventPress;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BuoyGlyph(BuoyIcons.database, size: 48, color: MacOSColors.textMuted),
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                monitoring ? 'No storage events yet' : 'Event listener is paused',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                  color: MacOSColors.textPrimary,
                ),
              ),
            ),
            Text(
              monitoring
                  ? 'Storage operations will appear here'
                  : 'Press play to start monitoring',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: MacOSColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final e = events[index];
        return StorageEventCard(
          key: ValueKey(e.id),
          storageKey: e.key,
          lastAction: e.action,
          lastEventTimestamp: e.timestamp,
          storageTypes: {e.storageType},
          onPress: () => onEventPress(e),
        );
      },
    );
  }
}

/// Level 1 of the browser's history flow: one key's events, newest-first (RN
/// StorageModalWithTabs history FlatList). Taps report the event's index in
/// chronological (oldest-first) order — the detail's index space.
class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.conversation, required this.onEventPress});

  final StorageConversation conversation;
  final ValueChanged<int> onEventPress;

  @override
  Widget build(BuildContext context) {
    final asc = [...conversation.events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final newestFirst = asc.reversed.toList();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: newestFirst.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final e = newestFirst[index];
        final ascIndex = asc.indexWhere((event) => event.id == e.id);
        return StorageEventCard(
          key: ValueKey(e.id),
          storageKey: e.key,
          lastAction: e.action,
          lastEventTimestamp: e.timestamp,
          storageTypes: {e.storageType},
          onPress: () => onEventPress(ascIndex >= 0 ? ascIndex : 0),
        );
      },
    );
  }
}
