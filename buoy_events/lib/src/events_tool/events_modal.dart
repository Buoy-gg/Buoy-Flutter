/// Ports packages/events/src/components/EventsModal.tsx + hooks/useUnifiedEvents.ts.
///
/// The events tool's root surface: a [JsModal] whose header carries the Events
/// title + captured count and the copy / power / clear actions, and whose body
/// is the source-filter bar + interleaved timeline, or an event detail. The
/// on-device consumer state (enabled-source badges + capturing toggle, both
/// persisted; source subscribe/unsubscribe; buoy-internal + shared-ignored
/// filtering) folds `useUnifiedEvents` into this one State.
///
/// Deviations (logged in events.md): no Copy-Settings sub-screen (header copy
/// exports with the default settings; the full formatter is still MCP-driven),
/// no free-tier cap / upgrade banner.
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../copy_settings.dart';
import '../event_export_formatter.dart';
import '../unified_event_store.dart';
import 'source_config.dart';
import 'unified_event_detail.dart';
import 'unified_event_filters.dart';
import 'unified_event_list.dart';

/// Sources enabled by default (RN `DEFAULT_ENABLED_SOURCES` — all display
/// sources except the high-frequency "render").
const List<String> _defaultEnabledSources = [
  EventSourceIds.storageAsync,
  EventSourceIds.redux,
  EventSourceIds.network,
  EventSourceIds.reactQueryQuery,
  EventSourceIds.reactQueryMutation,
  EventSourceIds.route,
  EventSourceIds.zustand,
  EventSourceIds.jotai,
];

/// Buoy's own internal network hosts (RN `BUOY_INTERNAL_HOSTS`).
const List<String> _buoyInternalHosts = ['api.keygen.sh'];

class EventsModal extends StatefulWidget {
  const EventsModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<EventsModal> createState() => _EventsModalState();
}

class _EventsModalState extends State<EventsModal> {
  final _keys = devToolsStorageKeys.events;

  List<UnifiedEvent> _events = const [];
  Set<String> _discovered = {};
  Set<String> _enabledSources = _defaultEnabledSources.toSet();
  bool _isCapturing = true;
  bool _restored = false;

  /// Wall-clock windows during which capture was OFF (RN `pausedWindowsRef`).
  /// Releasing this consumer's source refs is not enough to keep the list
  /// still: a watching dashboard legitimately keeps capturing into the
  /// SHARED store while the device is paused. So events stamped inside a
  /// paused window stay hidden — and stay hidden AFTER resume too: the user
  /// was told the tool wasn't listening, and a resume that surfaces a backlog
  /// of "unheard" events reads as capture-while-off (pause → clear → tap
  /// around → resume must come back BLANK). The open window's start is
  /// persisted beside the capturing flag, so a relaunch while paused keeps
  /// hiding from the ORIGINAL pause press, not from the reopen.
  int? _pausedAt;
  final List<(int, int)> _pausedWindows = [];

  bool _isInPausedWindow(UnifiedEvent e) {
    final t = e.timestamp;
    final open = _pausedAt;
    if (open != null && t >= open) return true;
    for (final (start, end) in _pausedWindows) {
      if (t >= start && t <= end) return true;
    }
    return false;
  }

  /// Declare this consumer's desired sources to the store's ledger — the
  /// ONE place refs are acquired or released for the on-device modal.
  void _declareSources() {
    unifiedEventStore.setLocalEnabledSources(
      _isCapturing ? _enabledSources : const <String>[],
    );
  }

  UnifiedEvent? _selectedEvent;

  bool _isSearchActive = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  void Function()? _storeUnsub;
  void Function()? _registryUnsub;

  @override
  void initState() {
    super.initState();
    MinuteTicker.instance.retain();

    _discovered = unifiedEventStore.getAvailableEventSources();
    _storeUnsub = unifiedEventStore.subscribe((events) {
      if (!mounted) return;
      setState(() {
        _events = events;
        _discovered = unifiedEventStore.getAvailableEventSources();
      });
    });
    _registryUnsub = eventSourceRegistry.onChange(() {
      if (mounted) {
        setState(
            () => _discovered = unifiedEventStore.getAvailableEventSources());
      }
    });
    IgnoredPatternsStore.instance.addListener(_onExternalChange);
    subscriberCountNotifier.subscribe(_onSubscriberCountChange);

    _searchFocus.addListener(() {
      // Stay open while the query still filters the list — collapsing it would
      // hide why events are missing.
      if (!_searchFocus.hasFocus &&
          _isSearchActive &&
          _searchController.text.isEmpty) {
        setState(() => _isSearchActive = false);
      }
    });
    // Re-filter from the controller, not TextField.onChanged — with a connected
    // hardware keyboard the iOS input path can update the editing value without
    // the user-edit callback firing (seen live in the network tool).
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });

    _restoreState();
  }

  @override
  void dispose() {
    _storeUnsub?.call();
    _registryUnsub?.call();
    IgnoredPatternsStore.instance.removeListener(_onExternalChange);
    // Release this consumer's source subscriptions (ref-counted — a watching
    // dashboard keeps its own). Through the ledger, so exactly what this
    // consumer holds is released — no more, no less.
    unifiedEventStore.setLocalEnabledSources(const <String>[]);
    _searchController.dispose();
    _searchFocus.dispose();
    MinuteTicker.instance.release();
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) setState(() {});
  }

  void _onSubscriberCountChange(String _) {
    if (mounted) setState(() {});
  }

  // ── Persistence (RN events keys) ──────────────────────────────────────────

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    Set<String>? savedSources;
    final raw = prefs.getString(_keys.enabledSources());
    if (raw != null && raw.isNotEmpty) {
      try {
        savedSources = (jsonDecode(raw) as List).cast<String>().toSet();
      } catch (_) {}
    }

    final available = _availableDisplaySources;
    final defaultEnabled = available
        .where(_defaultEnabledSources.contains)
        .toSet();

    Set<String> toEnable;
    if (savedSources != null && savedSources.isNotEmpty) {
      final valid = savedSources.where(available.contains).toSet();
      toEnable = valid.isNotEmpty ? valid : defaultEnabled;
    } else {
      toEnable = defaultEnabled;
    }

    final capturingRaw = prefs.getString(_keys.isCapturing());
    final shouldCapture = capturingRaw == null ? true : capturingRaw == 'true';
    // Still paused from a previous session: keep hiding from that press.
    final pausedRaw = prefs.getString(_keys.pausedAt());
    final pausedAt = !shouldCapture && pausedRaw != null
        ? int.tryParse(pausedRaw)
        : null;

    setState(() {
      _enabledSources = toEnable;
      _isCapturing = shouldCapture;
      _pausedAt = pausedAt;
      _restored = true;
    });
    _declareSources();
  }

  Future<void> _savePausedAt(int? pausedAt) async {
    final prefs = await SharedPreferences.getInstance();
    if (pausedAt == null) {
      await prefs.remove(_keys.pausedAt());
    } else {
      await prefs.setString(_keys.pausedAt(), pausedAt.toString());
    }
  }

  Future<void> _save(String key, String value) async {
    (await SharedPreferences.getInstance()).setString(key, value);
  }

  // ── Derived ───────────────────────────────────────────────────────────────

  /// Display sources whose event sources are actually discovered.
  List<String> get _availableDisplaySources {
    return kAllDisplaySources.where((display) {
      final sources = kSourceToEventSources[display] ?? [display];
      return sources.any(_discovered.contains);
    }).toList();
  }

  Set<String> get _allowedEventSources {
    final allowed = <String>{};
    for (final display in _enabledSources) {
      final sources = kSourceToEventSources[display];
      if (sources != null) allowed.addAll(sources);
    }
    return allowed;
  }

  bool _isBuoyInternal(UnifiedEvent e) {
    if (e.source == EventSourceIds.storageAsync ||
        e.source == EventSourceIds.storageMmkv) {
      final inner = e.data['data'];
      final key = (inner is Map ? inner['key'] : null) ?? e.data['key'];
      if (key is String && isDevToolsStorageKey(key)) return true;
    }
    if (e.source == EventSourceIds.network) {
      final host = '${e.data['host'] ?? ''}';
      final url = '${e.data['url'] ?? ''}';
      for (final internal in _buoyInternalHosts) {
        if (host.contains(internal) || url.contains(internal)) return true;
      }
    }
    return false;
  }

  bool _isNetworkIgnored(UnifiedEvent e) {
    if (e.source != EventSourceIds.network) return false;
    final patterns = IgnoredPatternsStore.instance.patterns;
    if (patterns.isEmpty) return false;
    final url = '${e.data['url'] ?? ''}';
    return patterns.any((p) => urlMatchesIgnoredPattern(url, p));
  }

  /// Header search (RN `matchesSearch`): the two fields the row renders, plus a
  /// network event's full URL — the title only carries the path, so a query for
  /// the host or a query-string value would otherwise miss. [query] must already
  /// be lowercased and trimmed.
  bool _matchesSearch(UnifiedEvent e, String query) {
    if (e.title.toLowerCase().contains(query)) return true;
    if (e.subtitle.toLowerCase().contains(query)) return true;
    final url = e.data['url'];
    return url is String && url.toLowerCase().contains(query);
  }

  List<UnifiedEvent> get _filteredEvents {
    final allowed = _allowedEventSources;
    if (allowed.isEmpty) return const [];
    final query = _searchController.text.trim().toLowerCase();
    return _events
        .where((e) =>
            allowed.contains(e.source) &&
            !_isBuoyInternal(e) &&
            !_isNetworkIgnored(e) &&
            !_isInPausedWindow(e) &&
            (query.isEmpty || _matchesSearch(e, query)))
        .toList();
  }

  List<SourceInfo> get _availableSources {
    final counts = unifiedEventStore.getSourceCounts();
    final list = <SourceInfo>[];
    for (final display in _availableDisplaySources) {
      final sources = kSourceToEventSources[display] ?? [display];
      final count =
          sources.fold<int>(0, (sum, s) => sum + (counts[s] ?? 0));
      final config = sourceConfigFor(display);
      final storeId = kDisplaySourceToStoreId[display];
      final adapter =
          storeId != null ? eventSourceRegistry.byId(storeId) : null;
      final subCount = adapter?.subscriberCount?.call();
      list.add(SourceInfo(
        source: display,
        label: config.label,
        color: config.color,
        count: count,
        enabled: _enabledSources.contains(display),
        subscriberCount: subCount,
      ));
    }
    // Enabled first (stable).
    list.sort((a, b) {
      if (a.enabled && !b.enabled) return -1;
      if (!a.enabled && b.enabled) return 1;
      return 0;
    });
    return list;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _toggleSource(String source) {
    setState(() {
      if (_enabledSources.contains(source)) {
        _enabledSources = {..._enabledSources}..remove(source);
      } else {
        _enabledSources = {..._enabledSources, source};
      }
    });
    _declareSources();
    if (_restored) {
      _save(_keys.enabledSources(), jsonEncode(_enabledSources.toList()));
    }
  }

  void _toggleCapturing() {
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      if (_isCapturing) {
        _isCapturing = false;
        _pausedAt = now;
      } else {
        final open = _pausedAt;
        if (open != null) _pausedWindows.add((open, now));
        _pausedAt = null;
        _isCapturing = true;
      }
    });
    _declareSources();
    if (_restored) {
      _save(_keys.isCapturing(), _isCapturing.toString());
      _savePausedAt(_pausedAt);
    }
  }

  String _exportAll() => generateExport(_filteredEvents, kDefaultCopySettings);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: '${_keys.root()}_modal',
      wrapChildInScrollView: false,
      headerContent: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _header(),
      ),
      child: SizedBox.expand(child: _content()),
    );
  }

  Widget _content() {
    if (_selectedEvent != null) {
      return UnifiedEventDetail(event: _selectedEvent!);
    }
    return ColoredBox(
      color: BuoyColors.base,
      child: Column(
        children: [
          UnifiedEventFilters(
            availableSources: _availableSources,
            onToggleSource: _toggleSource,
            totalCount: unifiedEventStore.getEventCount(),
            filteredCount: _filteredEvents.length,
          ),
          Expanded(
            child: UnifiedEventList(
              events: _filteredEvents,
              isCapturing: _isCapturing,
              searchText: _searchController.text,
              onEventPress: (event) => setState(() => _selectedEvent = event),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    if (_selectedEvent != null) {
      final event = _selectedEvent!;
      return ModalHeader(
        children: [
          ModalHeaderBack(onBack: () => setState(() => _selectedEvent = null)),
          ModalHeaderContent(title: event.title),
          ModalHeaderActions(
            children: [
              CopyButton(
                value: {
                  'source': event.source,
                  'title': event.title,
                  'subtitle': event.subtitle,
                  'status': event.status.name,
                  'timestamp': DateTime.fromMillisecondsSinceEpoch(
                    event.timestamp,
                  ).toUtc().toIso8601String(),
                  'data': event.data,
                },
                size: 14,
                decoration: _iconDecoration(),
                width: 32,
                height: 32,
              ),
            ],
          ),
        ],
      );
    }

    final total = unifiedEventStore.getEventCount();
    final hasQuery = _searchController.text.isNotEmpty;
    return ModalHeader(
      children: [
        ModalHeaderContent(
          noMargin: true,
          child: _isSearchActive ? _searchField() : _titleBlock(total),
        ),
        ModalHeaderActions(
          children: [
            if (!_isSearchActive)
              HeaderActionButton(
                icon: BuoyIcons.search,
                color: hasQuery
                    ? BuoyColors.primary
                    : BuoyColors.textSecondary,
                active: hasQuery,
                onTap: () {
                  setState(() => _isSearchActive = true);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _searchFocus.requestFocus(),
                  );
                },
              ),
            CopyButton(
              value: _exportAll,
              size: 14,
              idleColor:
                  total == 0 ? BuoyColors.textMuted : BuoyColors.textSecondary,
              enabled: total > 0,
              decoration: _iconDecoration(),
              width: 32,
              height: 32,
            ),
            PowerToggleButton(
              isEnabled: _isCapturing,
              onToggle: _toggleCapturing,
            ),
            HeaderActionButton(
              icon: BuoyIcons.trash2,
              color: total == 0 ? BuoyColors.textMuted : BuoyColors.error,
              disabled: total == 0,
              onTap: () {
                unifiedEventStore.clearEvents();
                setState(() => _selectedEvent = null);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _titleBlock(int total) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const Text(
          'Events',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: BuoyColors.text,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$total captured',
          style: const TextStyle(
            fontSize: 12,
            color: BuoyColors.textMuted,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: BuoyColors.input,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BuoyColors.border),
      ),
      child: Row(
        children: [
          const BuoyGlyph(
            BuoyIcons.search,
            size: 14,
            color: BuoyColors.textMuted,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autocorrect: false,
                onSubmitted: (_) => _searchFocus.unfocus(),
                style: const TextStyle(
                  fontSize: 13,
                  color: BuoyColors.text,
                  fontFamily: 'monospace',
                ),
                cursorColor: BuoyColors.primary,
                decoration: const InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search events...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: BuoyColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          TouchableOpacity(
            activeOpacity: 0.2,
            onTap: () {
              _searchController.clear();
              _searchFocus.unfocus();
              setState(() => _isSearchActive = false);
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Padding(
                padding: EdgeInsets.all(4),
                child: BuoyGlyph(
                  BuoyIcons.x,
                  size: 14,
                  color: BuoyColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _iconDecoration() => BoxDecoration(
        color: BuoyColors.input,
        borderRadius: BorderRadius.circular(6),
      );
}
