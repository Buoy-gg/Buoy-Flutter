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

  UnifiedEvent? _selectedEvent;

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

    _restoreState();
  }

  @override
  void dispose() {
    _storeUnsub?.call();
    _registryUnsub?.call();
    IgnoredPatternsStore.instance.removeListener(_onExternalChange);
    // Release this consumer's source subscriptions (ref-counted — a watching
    // dashboard keeps its own).
    if (_isCapturing) {
      for (final s in _enabledSources) {
        final id = eventSourceToDiscoveryId[s];
        if (id != null) unifiedEventStore.unsubscribeFromSource(id);
      }
    }
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

    setState(() {
      _enabledSources = toEnable;
      _isCapturing = shouldCapture;
      _restored = true;
    });

    if (shouldCapture) {
      for (final s in toEnable) {
        final id = eventSourceToDiscoveryId[s];
        if (id != null) unifiedEventStore.subscribeToSource(id);
      }
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

  List<UnifiedEvent> get _filteredEvents {
    final allowed = _allowedEventSources;
    if (allowed.isEmpty) return const [];
    return _events
        .where((e) =>
            allowed.contains(e.source) &&
            !_isBuoyInternal(e) &&
            !_isNetworkIgnored(e))
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
      final id = eventSourceToDiscoveryId[source];
      if (_enabledSources.contains(source)) {
        _enabledSources = {..._enabledSources}..remove(source);
        if (id != null) unifiedEventStore.unsubscribeFromSource(id);
      } else {
        _enabledSources = {..._enabledSources, source};
        if (_isCapturing && id != null) {
          unifiedEventStore.subscribeToSource(id);
        }
      }
    });
    if (_restored) {
      _save(_keys.enabledSources(), jsonEncode(_enabledSources.toList()));
    }
  }

  void _toggleCapturing() {
    setState(() {
      if (_isCapturing) {
        for (final s in _enabledSources) {
          final id = eventSourceToDiscoveryId[s];
          if (id != null) unifiedEventStore.unsubscribeFromSource(id);
        }
        _isCapturing = false;
      } else {
        for (final s in _enabledSources) {
          final id = eventSourceToDiscoveryId[s];
          if (id != null) unifiedEventStore.subscribeToSource(id);
        }
        _isCapturing = true;
      }
    });
    if (_restored) _save(_keys.isCapturing(), _isCapturing.toString());
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
    return ModalHeader(
      children: [
        ModalHeaderContent(
          noMargin: true,
          child: Row(
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
          ),
        ),
        ModalHeaderActions(
          children: [
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

  BoxDecoration _iconDecoration() => BoxDecoration(
        color: BuoyColors.input,
        borderRadius: BorderRadius.circular(6),
      );
}
