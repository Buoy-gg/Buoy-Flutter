/// Ports packages/route-events/src/components/RouteEventsModalWithTabs.tsx (+
/// RouteFilterViewV2.tsx, folded in).
///
/// The route inspector's root surface: a [JsModal] whose header carries the
/// Routes/Events/Stack [TabSelector] and per-tab actions (copy, filter, power
/// toggle, clear), and whose body is the sitemap, the events timeline, the
/// navigation stack, an event detail, or the Filters sub-view. All view state
/// lives in this one State (folds RN's modal + filter view). Persistence uses
/// the RN route-events storage keys. `wrapChildInScrollView: false` — each
/// screen owns its scrolling.
///
/// Deviation (logged): no Pro gating / free-tier event limit / locked-events
/// banner (briefing precedent — all features available).
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes_capture.dart';
import '../routes_controller.dart';
import 'navigation_stack.dart';
import 'route_event_detail.dart';
import 'route_event_row.dart';
import 'routes_sitemap.dart';

/// RN initial ignoredPatterns.
const _defaultIgnored = {'/_sitemap', '/api', '/__dev'};

class RoutesModal extends StatefulWidget {
  const RoutesModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<RoutesModal> createState() => _RoutesModalState();
}

class _RoutesModalState extends State<RoutesModal> {
  String _activeTab = 'events'; // RN defaults to Events.
  bool _showFilters = false;
  RouteChangeEvent? _selectedEvent;
  int _selectedVisitNumber = 1;

  String _searchQuery = '';
  bool _monitoringEnabled = true;
  Set<String> _ignoredPatterns = {..._defaultIgnored};
  String _stackCopyValue = '';

  void Function()? _unsubscribe;
  List<RouteChangeEvent> _events = const [];

  final _keys = devToolsStorageKeys.routeEvents;

  @override
  void initState() {
    super.initState();
    MinuteTicker.instance.retain();
    _loadPersisted();
    _subscribeIfEnabled();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    MinuteTicker.instance.release();
    super.dispose();
  }

  // ── Persistence (RN route-events keys, byte-identical) ─────────────────────

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final tab = prefs.getString(_keys.activeTab());
      if (tab == 'routes' || tab == 'events' || tab == 'stack') _activeTab = tab!;

      final monitoring = prefs.getString(_keys.isMonitoring());
      if (monitoring != null) _monitoringEnabled = monitoring == 'true';

      final filters = prefs.getString(_keys.eventFilters());
      if (filters != null) {
        try {
          _ignoredPatterns =
              (jsonDecode(filters) as List).cast<String>().toSet();
        } catch (_) {}
      }
    });
    _subscribeIfEnabled();
  }

  Future<void> _save(String key, String value) async {
    (await SharedPreferences.getInstance()).setString(key, value);
  }

  // ── Event subscription (power toggle gates it) ─────────────────────────────

  void _subscribeIfEnabled() {
    if (_monitoringEnabled && _unsubscribe == null) {
      _unsubscribe = RouteEventStore.instance.subscribeToEvents((events) {
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

  // ── Filters ────────────────────────────────────────────────────────────────

  void _addPattern(String pattern) {
    if (pattern.isEmpty) return;
    setState(() => _ignoredPatterns = {..._ignoredPatterns, pattern});
    _save(_keys.eventFilters(), jsonEncode(_ignoredPatterns.toList()));
  }

  void _removePattern(String pattern) {
    setState(() => _ignoredPatterns = {..._ignoredPatterns}..remove(pattern));
    _save(_keys.eventFilters(), jsonEncode(_ignoredPatterns.toList()));
  }

  void _setTab(String tab) {
    setState(() {
      _activeTab = tab;
      _selectedEvent = null;
    });
    _save(_keys.activeTab(), tab);
  }

  // ── Derived ────────────────────────────────────────────────────────────────

  List<RouteChangeEvent> get _filteredEvents {
    return _events.where((event) {
      if (event.pathname.isEmpty) return false;
      final ignored =
          _ignoredPatterns.any((p) => event.pathname.contains(p));
      if (ignored) return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final pathMatch = event.pathname.toLowerCase().contains(q);
        final paramMatch = event.params.entries.any((e) {
          final v = e.value is List
              ? (e.value as List).join(' ')
              : '${e.value}';
          return e.key.toLowerCase().contains(q) ||
              v.toLowerCase().contains(q);
        });
        return pathMatch || paramMatch;
      }
      return true;
    }).toList();
  }

  /// RN visitCounts: iterate oldest→newest (events are newest-first) assigning
  /// each event index its visit number for its pathname.
  Map<int, int> get _visitCounts {
    final counts = <String, int>{};
    final result = <int, int>{};
    for (var i = _events.length - 1; i >= 0; i--) {
      final path = _events[i].pathname;
      final n = (counts[path] ?? 0) + 1;
      counts[path] = n;
      result[i] = n;
    }
    return result;
  }

  List<String> get _allEventPathnames {
    final set = <String>{
      for (final e in _events)
        if (e.pathname.isNotEmpty) e.pathname,
    };
    return set.toList()..sort();
  }

  Object _copyAllEvents() {
    final filtered = _filteredEvents;
    return {
      'summary': {
        'total': _events.length,
        'filtered': filtered.length,
        'listening': _monitoringEnabled,
        'ignoredPatterns': _ignoredPatterns.toList(),
        'timestamp': DateTime.now().toIso8601String(),
      },
      'events': [
        for (var i = 0; i < filtered.length; i++)
          {
            'index': i,
            'pathname': filtered[i].pathname,
            'timestamp': filtered[i].timestamp,
            'params': filtered[i].params,
            'segments': filtered[i].segments,
            'previousPathname': filtered[i].previousPathname,
            'timeSincePrevious': filtered[i].timeSincePrevious,
          },
      ],
    };
  }

  void _handleNavigate(String pathname) {
    try {
      BuoyRoutesController.instance.navigate(pathname);
    } catch (_) {}
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: _keys.modal(),
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
      return RouteEventDetail(
        event: _selectedEvent!,
        visitNumber: _selectedVisitNumber,
        onNavigate: _handleNavigate,
      );
    }
    if (_activeTab == 'routes') return const RoutesSitemap();
    if (_activeTab == 'stack') {
      return NavigationStackView(
        onCopyValueChange: (value) {
          if (value != _stackCopyValue) {
            setState(() => _stackCopyValue = value);
          }
        },
      );
    }
    // Events tab.
    if (_showFilters) return _filtersView();
    return _eventsView();
  }

  Widget _eventsView() {
    final filtered = _filteredEvents;
    final showSearch = _events.isNotEmpty;

    if (filtered.isEmpty) {
      return ColoredBox(
        color: BuoyColors.base,
        child: Column(
          children: [
            if (showSearch) _searchBar(),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const BuoyGlyph(BuoyIcons.navigation,
                          size: 48, color: BuoyColors.textMuted),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.trim().isNotEmpty
                            ? 'No matching events'
                            : _monitoringEnabled
                                ? 'No route events yet'
                                : 'Event listener is paused',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: BuoyColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.trim().isNotEmpty
                            ? 'Try a different search term'
                            : _monitoringEnabled
                                ? 'Navigation events will appear here'
                                : 'Press play to start monitoring',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: BuoyColors.textSecondary,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: BuoyColors.base,
      child: Column(
        children: [
          _searchBar(),
          Expanded(
            child: RouteEventsTimeline(
              events: filtered,
              visitCounts: _visitCounts,
              onNavigate: _handleNavigate,
              onSelectEvent: (event, visitNumber) => setState(() {
                _selectedEvent = event;
                _selectedVisitNumber = visitNumber;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: BuoyColors.base,
      child: BuoySearchBar(
        value: _searchQuery,
        onChange: (value) => setState(() => _searchQuery = value),
        placeholder: 'Search pathname or params...',
      ),
    );
  }

  Widget _filtersView() {
    return DynamicFilterView(
      addFilterEnabled: true,
      addFilterTitle: 'ACTIVE FILTERS',
      addFilterPlaceholder: 'Enter pattern (e.g., /_sitemap)',
      activePatterns: _ignoredPatterns.toList(),
      onPatternAdd: _addPattern,
      onPatternRemove: _removePattern,
      availableItemsEnabled: true,
      availableItemsTitle: 'AVAILABLE ROUTES FROM EVENTS',
      availableItemsEmptyMessage:
          'No routes available. Routes from navigation events will appear here.',
      availableItems: _allEventPathnames,
      howItWorksEnabled: true,
      howItWorksTitle: 'HOW FILTERS WORK',
      howItWorksDescription:
          'Filtered routes will not appear in the route events list. Patterns '
          'match if the route contains the specified text.',
      howItWorksExamples: const [
        '• /_sitemap → filters /_sitemap routes',
        '• /api → filters /api/users, /api/posts',
        '• [id] → filters all routes with [id] param',
      ],
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _header() {
    if (_selectedEvent != null) {
      final event = _selectedEvent!;
      return ModalHeader(
        children: [
          ModalHeaderBack(onBack: () => setState(() => _selectedEvent = null)),
          ModalHeaderContent(title: event.pathname),
          ModalHeaderActions(
            children: [
              CopyButton(
                value: {
                  'pathname': event.pathname,
                  'previousPathname': event.previousPathname,
                  'params': event.params,
                  'segments': event.segments,
                  'timestamp': event.timestamp,
                  'timeSincePrevious': event.timeSincePrevious,
                  'visitNumber': _selectedVisitNumber,
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

    if (_showFilters) {
      return ModalHeader(
        children: [
          ModalHeaderBack(onBack: () => setState(() => _showFilters = false)),
          const ModalHeaderContent(title: 'Filters'),
        ],
      );
    }

    return ModalHeader(
      children: [
        ModalHeaderContent(noMargin: true, child: _tabs()),
        ModalHeaderActions(children: _actions()),
      ],
    );
  }

  Widget _tabs() {
    final count = _events.length;
    return TabSelector(
      tabs: [
        const (key: 'routes', label: 'Routes'),
        (
          key: 'events',
          label: count > 0 && _activeTab != 'events'
              ? 'Events ($count)'
              : 'Events',
        ),
        const (key: 'stack', label: 'Stack'),
      ],
      activeTab: _activeTab,
      onTabChange: _setTab,
    );
  }

  List<Widget> _actions() {
    if (_activeTab == 'stack') {
      return [
        CopyButton(
          value: _stackCopyValue,
          size: 14,
          idleColor: _stackCopyValue.isEmpty
              ? BuoyColors.textMuted
              : BuoyColors.textSecondary,
          enabled: _stackCopyValue.isNotEmpty,
          decoration: _iconDecoration(),
          width: 32,
          height: 32,
        ),
      ];
    }
    if (_activeTab == 'events') {
      final filtered = _filteredEvents;
      return [
        CopyButton(
          value: _copyAllEvents,
          size: 14,
          idleColor: filtered.isEmpty
              ? BuoyColors.textMuted
              : BuoyColors.textSecondary,
          enabled: filtered.isNotEmpty,
          decoration: _iconDecoration(),
          width: 32,
          height: 32,
        ),
        HeaderActionButton(
          icon: BuoyIcons.filter,
          color: _ignoredPatterns.isNotEmpty
              ? BuoyColors.primary
              : BuoyColors.textSecondary,
          active: _ignoredPatterns.isNotEmpty,
          onTap: () => setState(() => _showFilters = true),
        ),
        PowerToggleButton(
          isEnabled: _monitoringEnabled,
          onToggle: _toggleMonitoring,
        ),
        HeaderActionButton(
          icon: BuoyIcons.trash2,
          color: _events.isEmpty ? BuoyColors.textMuted : BuoyColors.error,
          disabled: _events.isEmpty,
          onTap: () {
            RouteEventStore.instance.clearEvents();
            setState(() => _selectedEvent = null);
          },
        ),
      ];
    }
    return const [];
  }

  BoxDecoration _iconDecoration() => BoxDecoration(
        color: BuoyColors.input,
        borderRadius: BorderRadius.circular(6),
      );
}
