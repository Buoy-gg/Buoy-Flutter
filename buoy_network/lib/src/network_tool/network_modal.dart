import 'package:flutter/material.dart';

import '../network_capture.dart';
import 'package:buoy_core/buoy_core.dart';
import 'copy_settings.dart';
import 'ignored_patterns.dart';
import 'macos_colors.dart';
import 'minute_ticker.dart';
import 'network_copy_view.dart';
import 'network_detail_view.dart';
import 'network_filter.dart';
import 'network_filter_view.dart';
import 'network_list_screen.dart';
import 'widgets/copy_button.dart';
import 'widgets/modal_header.dart';
import 'widgets/power_toggle_button.dart';
import 'widgets/tab_selector.dart';

/// Port of NetworkModal — the network tool's root surface. Opens in JsModal
/// with the RN persistence key (`@react_buoy_network_modal`), a compact
/// action header (status chips / search / filter / copy / power / clear),
/// and four screens: list, request detail, Filters tab, Copy tab.
///
/// Every screen owns its scrolling, so JsModal's scroll wrapper is disabled
/// (RN's disableScrollWrapper contract for the virtualized list).
class NetworkModal extends StatefulWidget {
  const NetworkModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<NetworkModal> createState() => _NetworkModalState();
}

class _NetworkModalState extends State<NetworkModal> {
  /// Capture pause (the power toggle's freeze-stream semantic).
  bool _paused = false;
  NetworkFilter _filter = const NetworkFilter();
  NetworkCaptureEvent? _selectedEvent;
  bool _showFilterView = false;
  String _activeTab = 'filters';
  bool _isSearchActive = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  CopySettings _copySettings = const CopySettings();
  bool _copySettingsLoaded = false;

  @override
  void initState() {
    super.initState();
    MinuteTicker.instance.retain();
    loadCopySettings().then((stored) {
      if (!mounted) return;
      setState(() {
        if (stored != null) _copySettings = stored;
        _copySettingsLoaded = true;
      });
    });
    _searchFocus.addListener(() {
      // RN: blurring the search input closes it.
      if (!_searchFocus.hasFocus && _isSearchActive) {
        setState(() => _isSearchActive = false);
      }
    });
    // Drive the filter from the controller, not TextField.onChanged — with a
    // connected hardware keyboard the iOS input path can update the editing
    // value without the user-edit callback firing (seen live on-device).
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text != (_filter.searchText ?? '')) _handleSearch(text);
    });
  }

  @override
  void dispose() {
    MinuteTicker.instance.release();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _handleSearch(String text) {
    setState(() {
      _filter = _filter.copyWith(searchText: text.isEmpty ? null : text);
    });
  }

  void _toggleStatusFilter(NetworkStatusFilter status) {
    setState(() {
      _filter = _filter.copyWith(
        status: _filter.status == status ? null : status,
      );
    });
  }

  void _updateCopySettings(CopySettings settings) {
    setState(() => _copySettings = settings);
    if (_copySettingsLoaded) saveCopySettings(settings);
  }

  @override
  Widget build(BuildContext context) {
    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: '@react_buoy_network_modal',
      headerContent: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _headerContent(),
      ),
      wrapChildInScrollView: false,
      // SizedBox.expand: JsModal's content column gives loose width — the
      // empty state (and any non-ListView screen) must still fill the modal.
      child: SizedBox.expand(
        child: ColoredBox(
          color: MacOSColors.backgroundBase,
          child: _screen(),
        ),
      ),
    );
  }

  Widget _screen() {
    final selectedEvent = _selectedEvent;
    if (selectedEvent != null) {
      return NetworkDetailView(event: selectedEvent);
    }
    if (_showFilterView) {
      return _FilteredEventsBuilder(
        paused: _paused,
        filter: _filter,
        builder: (context, events) => _activeTab == 'filters'
            ? NetworkFilterView(
                events: events,
                filter: _filter,
                onFilterChange: (filter) => setState(() => _filter = filter),
              )
            : NetworkCopyView(
                events: events,
                settings: _copySettings,
                onSettingsChange: _updateCopySettings,
              ),
      );
    }
    return NetworkListScreen(
      paused: _paused,
      filter: _filter,
      onEventPress: (event) => setState(() => _selectedEvent = event),
    );
  }

  // ── Header states ─────────────────────────────────────────────────────

  Widget _headerContent() {
    if (_showFilterView && _selectedEvent == null) {
      return ModalHeader(
        children: [
          ModalHeaderBack(
            onBack: () => setState(() => _showFilterView = false),
          ),
          ModalHeaderContent(
            noMargin: true,
            child: TabSelector(
              tabs: const [
                (key: 'filters', label: 'Filters'),
                (key: 'copy', label: 'Copy'),
              ],
              activeTab: _activeTab,
              onTabChange: (tab) => setState(() => _activeTab = tab),
            ),
          ),
        ],
      );
    }

    if (_selectedEvent != null) {
      return ModalHeader(
        children: [
          ModalHeaderBack(onBack: () => setState(() => _selectedEvent = null)),
          const ModalHeaderContent(title: 'Request Details', centered: true),
        ],
      );
    }

    return ModalHeader(
      children: [
        ModalHeaderContent(
          child: _isSearchActive ? _searchField() : _headerBadges(),
        ),
        ModalHeaderActions(
          children: [
            HeaderActionButton(
              icon: Icons.search,
              color: MacOSColors.textSecondary,
              onTap: () {
                setState(() => _isSearchActive = true);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _searchFocus.requestFocus(),
                );
              },
            ),
            HeaderActionButton(
              icon: Icons.filter_alt_outlined,
              color: _filter.hasActiveFacets
                  ? MacOSColors.info
                  : MacOSColors.textMuted,
              active: _filter.hasActiveFacets,
              onTap: () => setState(() => _showFilterView = true),
            ),
            _HeaderCopyButton(
              paused: _paused,
              filter: _filter,
              copySettings: _copySettings,
            ),
            PowerToggleButton(
              isEnabled: !_paused,
              onToggle: () => setState(() => _paused = !_paused),
            ),
            _HeaderClearButton(paused: _paused),
          ],
        ),
      ],
    );
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
          const Icon(Icons.search, size: 14, color: MacOSColors.textSecondary),
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
                  hintText: 'Search URL, method, operation, error...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: MacOSColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            TouchableOpacity(
              activeOpacity: 0.2,
              onTap: () {
                _searchController.clear();
                _handleSearch('');
                setState(() => _isSearchActive = false);
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: MacOSColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerBadges() {
    return _NetworkHeaderBadges(
      paused: _paused,
      activeStatus: _filter.status,
      onToggleStatus: _toggleStatusFilter,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Live header leaves (NetworkHeaderLive.tsx) — each is its own narrow
// store subscriber so per-event updates never rebuild the modal shell.
// ══════════════════════════════════════════════════════════════════════

/// Success / error / pending count chips — tap toggles the status filter.
class _NetworkHeaderBadges extends StatefulWidget {
  const _NetworkHeaderBadges({
    required this.paused,
    required this.activeStatus,
    required this.onToggleStatus,
  });

  final bool paused;
  final NetworkStatusFilter? activeStatus;
  final ValueChanged<NetworkStatusFilter> onToggleStatus;

  @override
  State<_NetworkHeaderBadges> createState() => _NetworkHeaderBadgesState();
}

class _NetworkHeaderBadgesState extends State<_NetworkHeaderBadges> {
  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _unsubscribe = NetworkEventStore.instance.subscribe(_onChange);
    IgnoredPatternsStore.instance.addListener(_onChange);
  }

  void _onChange() {
    if (!mounted) return;
    if (widget.paused && NetworkEventStore.instance.events.isNotEmpty) return;
    setState(() {});
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    IgnoredPatternsStore.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = applyIgnoredPatterns(
      NetworkEventStore.instance.events,
      IgnoredPatternsStore.instance.patterns,
    );
    var success = 0, failed = 0, pending = 0;
    for (final event in events) {
      if (isSuccessEvent(event)) {
        success++;
      } else if (isErrorEvent(event)) {
        failed++;
      } else if (isPendingEvent(event)) {
        pending++;
      }
    }
    return Row(
      spacing: 8,
      children: [
        _chip(
          NetworkStatusFilter.success,
          Icons.check_circle_outline,
          MacOSColors.success,
          success,
        ),
        _chip(
          NetworkStatusFilter.error,
          Icons.highlight_off,
          MacOSColors.error,
          failed,
        ),
        _chip(
          NetworkStatusFilter.pending,
          Icons.schedule,
          MacOSColors.warning,
          pending,
        ),
      ],
    );
  }

  Widget _chip(
    NetworkStatusFilter status,
    IconData icon,
    Color color,
    int count,
  ) {
    final active = widget.activeStatus == status;
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: () => widget.onToggleStatus(status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? MacOSColors.infoBackground
              : MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? MacOSColors.info.hexAlpha(0x50)
                : MacOSColors.borderDefault,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Icon(icon, size: 12, color: color),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trash button — enabled while the store has events; clears the store.
class _HeaderClearButton extends StatefulWidget {
  const _HeaderClearButton({required this.paused});

  final bool paused;

  @override
  State<_HeaderClearButton> createState() => _HeaderClearButtonState();
}

class _HeaderClearButtonState extends State<_HeaderClearButton> {
  void Function()? _unsubscribe;
  late bool _hasEvents = NetworkEventStore.instance.events.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _unsubscribe = NetworkEventStore.instance.subscribe(_onChange);
  }

  void _onChange() {
    if (!mounted) return;
    final hasEvents = NetworkEventStore.instance.events.isNotEmpty;
    // Flip-guarded: renders on empty↔non-empty only (RN useNetworkHasEvents).
    if (hasEvents != _hasEvents) setState(() => _hasEvents = hasEvents);
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HeaderActionButton(
      icon: Icons.delete_outline,
      color: _hasEvents ? MacOSColors.textMuted : MacOSColors.textDisabled,
      disabled: !_hasEvents,
      onTap: NetworkEventStore.instance.clear,
    );
  }
}

/// Copy-all button — copy text is resolved lazily at press time from a live
/// store read (RN's latest-ref pattern), so no string is built per event.
class _HeaderCopyButton extends StatefulWidget {
  const _HeaderCopyButton({
    required this.paused,
    required this.filter,
    required this.copySettings,
  });

  final bool paused;
  final NetworkFilter filter;
  final CopySettings copySettings;

  @override
  State<_HeaderCopyButton> createState() => _HeaderCopyButtonState();
}

class _HeaderCopyButtonState extends State<_HeaderCopyButton> {
  void Function()? _unsubscribe;
  bool _hasMatches = false;

  @override
  void initState() {
    super.initState();
    _hasMatches = _computeHasMatches();
    _unsubscribe = NetworkEventStore.instance.subscribe(_onChange);
    IgnoredPatternsStore.instance.addListener(_onChange);
  }

  bool _computeHasMatches() {
    return filterNetworkEvents(
      applyIgnoredPatterns(
        NetworkEventStore.instance.events,
        IgnoredPatternsStore.instance.patterns,
      ),
      widget.filter,
    ).isNotEmpty;
  }

  void _onChange() {
    if (!mounted) return;
    final hasMatches = _computeHasMatches();
    if (hasMatches != _hasMatches) setState(() => _hasMatches = hasMatches);
  }

  @override
  void didUpdateWidget(_HeaderCopyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) _onChange();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    IgnoredPatternsStore.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CopyButton(
      value: () => generateNetworkCopyText(
        filterNetworkEvents(
          applyIgnoredPatterns(
            NetworkEventStore.instance.events,
            IgnoredPatternsStore.instance.patterns,
          ),
          widget.filter,
        ),
        widget.copySettings,
      ),
      size: 14,
      idleColor: _hasMatches
          ? MacOSColors.textSecondary
          : MacOSColors.textDisabled,
      enabled: _hasMatches,
      decoration: headerActionButtonDecoration(),
      width: 32,
      height: 32,
    );
  }
}

/// Shared "filtered live list" builder for the Filters/Copy screens (RN's
/// useNetworkEventList in each screen): subscribes to the store + ignored
/// patterns, honors pause (clears still propagate), hands the filtered list
/// to [builder].
class _FilteredEventsBuilder extends StatefulWidget {
  const _FilteredEventsBuilder({
    required this.paused,
    required this.filter,
    required this.builder,
  });

  final bool paused;
  final NetworkFilter filter;
  final Widget Function(BuildContext, List<NetworkCaptureEvent>) builder;

  @override
  State<_FilteredEventsBuilder> createState() => _FilteredEventsBuilderState();
}

class _FilteredEventsBuilderState extends State<_FilteredEventsBuilder> {
  void Function()? _unsubscribe;
  late List<NetworkCaptureEvent> _events = NetworkEventStore.instance.events;

  @override
  void initState() {
    super.initState();
    _unsubscribe = NetworkEventStore.instance.subscribe(_onChange);
    IgnoredPatternsStore.instance.addListener(_onPatternsChange);
  }

  void _onChange() {
    if (!mounted) return;
    if (widget.paused && NetworkEventStore.instance.events.isNotEmpty) return;
    setState(() => _events = NetworkEventStore.instance.events);
  }

  void _onPatternsChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_FilteredEventsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused && !widget.paused) {
      _events = NetworkEventStore.instance.events;
    }
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    IgnoredPatternsStore.instance.removeListener(_onPatternsChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      filterNetworkEvents(
        applyIgnoredPatterns(
          _events,
          IgnoredPatternsStore.instance.patterns,
        ),
        widget.filter,
      ),
    );
  }
}
