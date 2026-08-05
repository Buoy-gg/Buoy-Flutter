import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../network_capture.dart';
import 'copy_settings.dart';
import 'network_copy_view.dart';
import 'network_detail_view.dart';
import 'network_filter.dart';
import 'network_filter_view.dart';
import 'network_header_menu.dart';
import 'network_list_screen.dart';
import 'overrides/network_override_header_button.dart';
import 'saved/network_saved_buttons.dart';
import 'saved/network_saved_store.dart';
import 'saved/pinned_split.dart';
import 'saved/network_saved_screen.dart';
import 'overrides/network_overrides_button.dart';
import 'overrides/network_overrides_screen.dart';
import '../overrides/override_rule.dart';

/// Port of NetworkModal — the network tool's root surface. Opens in JsModal
/// with the RN persistence key (`@react_buoy_network_modal`), a compact
/// action header (status chips / search / overrides / power / clear / ⋮),
/// and five screens: list, request detail, Filters tab, Copy tab, Overrides.
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
  bool _showOverridesView = false;
  bool _showSavedView = false;
  String _savedSearch = '';
  bool _showHeaderMenu = false;
  OverrideRule? _pendingOverrideDraft;
  final _overridesKey = GlobalKey<NetworkOverridesScreenState>();
  /// JsModal owns the mode; the only thing this modal needs it for is the
  /// detail footer's bottom inset — a bottom sheet sits on the home indicator,
  /// a floating window does not (same call StorageModal makes).
  JsModalMode _modalMode = JsModalMode.bottomSheet;
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
      onModeChange: (mode) => setState(() => _modalMode = mode),
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
          child: Stack(
            children: [
              Positioned.fill(child: _screen()),
              // The dropdown lives over the BODY, not in the header: the header
              // is a fixed-height row that clips anything overflowing it, and
              // the body's top-right is exactly where a menu from ⋮ belongs.
              if (_showHeaderMenu)
                NetworkHeaderMenu(
                  onClose: () => setState(() => _showHeaderMenu = false),
                  children: [
                    NetworkHeaderMenuItem(
                      icon: BuoyIcons.filter,
                      label: 'Filters',
                      iconColor: _filter.hasActiveFacets
                          ? MacOSColors.info
                          : MacOSColors.textSecondary,
                      onTap: () => setState(() {
                        _showHeaderMenu = false;
                        _activeTab = 'filters';
                        _showFilterView = true;
                      }),
                    ),
                    NetworkHeaderMenuItem(
                      icon: BuoyIcons.bookmark,
                      label: 'Saved requests',
                      onTap: () => setState(() {
                        _showHeaderMenu = false;
                        _showSavedView = true;
                      }),
                    ),
                    NetworkHeaderMenuItem(
                      icon: BuoyIcons.copy,
                      label: 'Copy requests',
                      onTap: () => setState(() {
                        _showHeaderMenu = false;
                        _activeTab = 'copy';
                        _showFilterView = true;
                      }),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Screen order is a STACK, not a list of independent flags.
  ///
  /// Overrides is entered FROM the detail view (which keeps its selection), so
  /// it has to win over detail. Detail in turn has to win over Saved, or
  /// tapping a saved row sets the selection and nothing visibly happens —
  /// exactly the bug this ordering was written to fix. Backing out of each one
  /// falls through to the screen it was opened from.
  Widget _screen() {
    if (_showOverridesView) {
      return NetworkOverridesScreen(
        key: _overridesKey,
        applySafeAreaInset: _modalMode == JsModalMode.bottomSheet,
        pendingDraft: _pendingOverrideDraft,
        onPendingConsumed: () =>
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _pendingOverrideDraft = null),
            ),
      );
    }
    final selectedEvent = _selectedEvent;
    if (selectedEvent != null) {
      return Column(
        children: [
          Expanded(child: NetworkDetailView(event: selectedEvent)),
          _DetailStepper(
            event: selectedEvent,
            paused: _paused,
            filter: _filter,
            // Opened from the Saved screen? Step through THAT list. Walking
            // the live list from a saved request means "Next" leaves the set
            // you were reading and the counter describes a different list than
            // the one you came from.
            events: _showSavedView
                ? selectSavedEvents(
                    NetworkSavedStore.instance.state.savedRecords,
                    _savedSearch,
                  )
                : null,
            applySafeAreaInset: _modalMode == JsModalMode.bottomSheet,
            onSelect: (event) => setState(() => _selectedEvent = event),
          ),
        ],
      );
    }
    if (_showSavedView) {
      return NetworkSavedScreen(
        search: _savedSearch,
        onSearchChange: (value) => setState(() => _savedSearch = value),
        onEventPress: (event) => setState(() => _selectedEvent = event),
      );
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

    if (_showOverridesView) {
      return ModalHeader(
        children: [
          ModalHeaderBack(
            onBack: () {
              // Back leaves the editor first, then the screen — otherwise a
              // half-written rule vanishes with one tap and no way back.
              final screen = _overridesKey.currentState;
              if (screen != null && screen.isEditing) {
                screen.closeEditor();
                return;
              }
              setState(() => _showOverridesView = false);
            },
          ),
          const ModalHeaderContent(
            title: 'Response Overrides',
            centered: true,
          ),
        ],
      );
    }

    if (_selectedEvent != null) {
      return ModalHeader(
        children: [
          // Clears only the selection, so backing out of a request opened from
          // the Saved screen returns THERE rather than to the live list.
          ModalHeaderBack(onBack: () => setState(() => _selectedEvent = null)),
          const ModalHeaderContent(title: 'Request Details', centered: true),
          ModalHeaderActions(
            children: [
              NetworkOverrideHeaderButton(
                event: _selectedEvent!,
                onOpen: (draft) => setState(() {
                  _pendingOverrideDraft = draft;
                  _showOverridesView = true;
                }),
              ),
              const SizedBox(width: 6),
              NetworkDetailPinActions(eventId: _selectedEvent!.id),
            ],
          ),
        ],
      );
    }

    if (_showSavedView) {
      return ModalHeader(
        children: [
          ModalHeaderBack(onBack: () => setState(() => _showSavedView = false)),
          const ModalHeaderContent(title: 'Saved Requests', centered: true),
        ],
      );
    }

    // WHAT STAYS IN THE BAR, and why: anything that communicates STATE. The
    // badges (what happened), the overrides flask (is the app being lied to),
    // the power toggle (are we capturing), and Clear — the reproduce loop is
    // clear → repro → read, so burying the first step doubles every cycle.
    // Search stays because it's the only way through 500 rows. Filters and Copy
    // are destinations, so they moved into ⋮.
    return ModalHeader(
      children: [
        ModalHeaderContent(
          child: _isSearchActive ? _searchField() : _headerBadges(),
        ),
        ModalHeaderActions(
          children: [
            HeaderActionButton(
              icon: BuoyIcons.search,
              color: MacOSColors.textSecondary,
              onTap: () {
                setState(() => _isSearchActive = true);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _searchFocus.requestFocus(),
                );
              },
            ),
            NetworkOverridesButton(
              onTap: () => setState(() => _showOverridesView = true),
            ),
            PowerToggleButton(
              isEnabled: !_paused,
              onToggle: () => setState(() => _paused = !_paused),
            ),
            _HeaderClearButton(paused: _paused),
            NetworkHeaderMenuButton(
              isOpen: _showHeaderMenu,
              hasIndicator: _filter.hasActiveFacets,
              // Toggles rather than opens: the dropdown renders in the body, so
              // it never covers the header and a second tap lands back here.
              // Opening again on that tap would look like nothing happened.
              onTap: () =>
                  setState(() => _showHeaderMenu = !_showHeaderMenu),
            ),
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
                  child: BuoyGlyph(
                    BuoyIcons.x,
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
          BuoyIcons.checkCircle,
          MacOSColors.success,
          success,
        ),
        _chip(
          NetworkStatusFilter.error,
          BuoyIcons.xCircle,
          MacOSColors.error,
          failed,
        ),
        _chip(
          NetworkStatusFilter.pending,
          BuoyIcons.clock,
          MacOSColors.warning,
          pending,
        ),
      ],
    );
  }

  Widget _chip(
    NetworkStatusFilter status,
    LucideIcon icon,
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
            BuoyGlyph(icon, size: 12, color: color),
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
      icon: BuoyIcons.trash2,
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

/// Previous / Next footer for the request detail screen — step through
/// requests without bouncing back to the list.
///
/// It wraps only ITSELF in [_FilteredEventsBuilder], never the detail body:
/// the event stream then rebuilds this one row instead of the whole inspector
/// (header cards, DataViewer trees, collapsible sections) every time a request
/// lands. Stepping walks the exact list the list screen renders, so the search
/// box and the status chips re-scope it in place — the counter always reads
/// "request N of what the list is showing", never "N of everything captured".
class _DetailStepper extends StatelessWidget {
  const _DetailStepper({
    required this.event,
    required this.paused,
    required this.filter,
    required this.applySafeAreaInset,
    required this.onSelect,
    this.events,
  });

  final NetworkCaptureEvent event;
  final bool paused;
  final NetworkFilter filter;

  /// The list to step through, when it isn't the live one.
  final List<NetworkCaptureEvent>? events;

  /// Only a bottom sheet sits on the home indicator — see [_NetworkModalState].
  final bool applySafeAreaInset;
  final ValueChanged<NetworkCaptureEvent> onSelect;

  @override
  Widget build(BuildContext context) {
    final supplied = events;
    if (supplied != null) return _footer(supplied);
    return _FilteredEventsBuilder(
      paused: paused,
      filter: filter,
      builder: (context, events) => _footer(events),
    );
  }

  Widget _footer(List<NetworkCaptureEvent> events) {
    final index = events.indexWhere((e) => e.id == event.id);
    // Not in the list: the filter changed under it while it was open, or it
    // aged past the store cap. Nothing coherent to step through, so no footer
    // rather than a counter that lies.
    if (index < 0) return const SizedBox.shrink();
    // The list is newest-first, so "Previous" walks toward the NEWER request —
    // the same direction as scrolling up.
    return EventStepperFooter(
      currentIndex: index,
      totalItems: events.length,
      itemLabel: 'Request',
      applySafeAreaInset: applySafeAreaInset,
      onPrevious: () {
        if (index > 0) onSelect(events[index - 1]);
      },
      onNext: () {
        if (index < events.length - 1) onSelect(events[index + 1]);
      },
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
