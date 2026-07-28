/// Ports packages/jotai/src/jotai/components/JotaiModal.tsx — the Riverpod tool's
/// root surface. A [JsModal] with Providers/Events tabs; the header carries
/// search, a filter toggle, copy, and (Events) the capture power toggle + clear.
/// Screens: provider browser, change stream, a provider's history, a change
/// detail (CHANGE/VALUE/DIFF), and the ignore-pattern Filters overlay.
///
/// Deviations from the Jotai original (briefing precedent): no free-tier gate /
/// "changes locked" upgrade banner / ProUpgradeModal. Capture-enabled and
/// ignored-patterns are in-memory (Jotai parity — not persisted).
library;

import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../riverpod_state_store.dart';
import '../riverpod_types.dart';
import 'provider_browser.dart';
import 'provider_change_detail.dart';
import 'provider_change_item.dart';
import 'provider_filter_view.dart';

class RiverpodModal extends StatefulWidget {
  const RiverpodModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<RiverpodModal> createState() => _RiverpodModalState();
}

class _RiverpodModalState extends State<RiverpodModal> {
  String _activeTab = 'providers';
  bool _showFilters = false;
  String? _selectedHistoryProvider;
  String? _selectedChangeId;
  final Set<String> _ignoredPatterns = {};

  List<ProviderChange> _changes = [];
  List<ProviderInfo> _providers = [];
  bool _isEnabled = riverpodStateStore.isEnabled;

  bool _isSearchActive = false;
  String _searchText = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  void Function()? _unsubChanges;
  void Function()? _unsubProviders;

  @override
  void initState() {
    super.initState();
    MinuteTicker.instance.retain();
    _changes = riverpodStateStore.getChanges();
    _providers = riverpodStateStore.getProviders();
    _unsubChanges = riverpodStateStore.subscribe((c) {
      if (mounted) setState(() => _changes = c);
    });
    _unsubProviders = riverpodStateStore.subscribeToProviders((p) {
      if (mounted) setState(() => _providers = p);
    });
    _searchController.addListener(() {
      if (_searchController.text != _searchText) {
        setState(() => _searchText = _searchController.text);
      }
    });
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus && _isSearchActive) {
        setState(() => _isSearchActive = false);
      }
    });
  }

  @override
  void dispose() {
    _unsubChanges?.call();
    _unsubProviders?.call();
    MinuteTicker.instance.release();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Derived ────────────────────────────────────────────────────────────────

  bool _matchesIgnored(String label) => _ignoredPatterns
      .any((p) => label.toLowerCase().contains(p.toLowerCase()));

  List<ProviderChange> get _displayedChanges {
    var list = _changes;
    if (_searchText.isNotEmpty) {
      final s = _searchText.toLowerCase();
      list = list
          .where((c) =>
              c.providerLabel.toLowerCase().contains(s) ||
              c.valuePreview.toLowerCase().contains(s) ||
              c.changedKeys.any((k) => k.toLowerCase().contains(s)))
          .toList();
    }
    if (_ignoredPatterns.isNotEmpty) {
      list = list.where((c) => !_matchesIgnored(c.providerLabel)).toList();
    }
    return list;
  }

  List<ProviderInfo> get _displayedProviders {
    if (_ignoredPatterns.isEmpty) return _providers;
    return _providers.where((p) => !_matchesIgnored(p.label)).toList();
  }

  List<ProviderChange> get _activeChanges {
    final history = _selectedHistoryProvider;
    if (history != null) {
      return _displayedChanges
          .where((c) => c.providerLabel == history)
          .toList();
    }
    return _displayedChanges;
  }

  ProviderChange? get _selectedChange {
    final id = _selectedChangeId;
    if (id == null) return null;
    for (final c in _activeChanges) {
      if (c.id == id) return c;
    }
    return null;
  }

  int get _selectedChangeIndex {
    final id = _selectedChangeId;
    if (id == null) return -1;
    return _activeChanges.indexWhere((c) => c.id == id);
  }

  bool get _hasActiveFilters => _ignoredPatterns.isNotEmpty;

  // ── Actions ────────────────────────────────────────────────────────────────

  void _toggleCapture() {
    setState(() {
      _isEnabled = !_isEnabled;
      riverpodStateStore.isEnabled = _isEnabled;
    });
  }

  void _togglePattern(String pattern) {
    setState(() {
      if (!_ignoredPatterns.remove(pattern)) _ignoredPatterns.add(pattern);
    });
  }

  void _setTab(String tab) {
    setState(() {
      _activeTab = tab;
      _selectedHistoryProvider = null;
      _selectedChangeId = null;
      _showFilters = false;
      if (_searchText.isNotEmpty) {
        _searchController.clear();
        _searchText = '';
      }
      _isSearchActive = false;
    });
  }

  Object _providersSnapshot() => {
        for (final p in _displayedProviders)
          p.label: truncatePayload(p.currentValue),
      };

  Object _changesSnapshot() => [
        for (final c in _displayedChanges) c.toJson(),
      ];

  Object _historySnapshot() => [
        for (final c in _activeChanges) c.toJson(),
      ];

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: 'buoy-riverpod-modal',
      wrapChildInScrollView: false,
      headerContent: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _header(),
      ),
      child: SizedBox.expand(
        child: ColoredBox(
          color: MacOSColors.backgroundBase,
          child: _screen(),
        ),
      ),
    );
  }

  // ── Screens ────────────────────────────────────────────────────────────────

  Widget _screen() {
    if (_showFilters) {
      return ProviderFilterView(
        ignoredPatterns: _ignoredPatterns,
        onTogglePattern: _togglePattern,
        onAddPattern: (p) => setState(() => _ignoredPatterns.add(p)),
        providers: _providers,
      );
    }

    final change = _selectedChange;
    final index = _selectedChangeIndex;
    if (change != null && index >= 0) {
      return ProviderChangeDetail(
        change: change,
        changes: _activeChanges,
        selectedIndex: index,
        onIndexChange: (i) {
          final next = _activeChanges;
          if (i >= 0 && i < next.length) {
            setState(() => _selectedChangeId = next[i].id);
          }
        },
      );
    }

    if (_selectedHistoryProvider != null) {
      final list = _activeChanges;
      if (list.isEmpty) {
        return _emptyState(
          BuoyIcons.box,
          'No history yet',
          'Changes for $_selectedHistoryProvider will appear here.',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        itemCount: list.length,
        itemBuilder: (context, i) => ProviderChangeItem(
          key: ValueKey(list[i].id),
          change: list[i],
          onPress: () => setState(() => _selectedChangeId = list[i].id),
        ),
      );
    }

    if (_activeTab == 'providers') {
      return ProviderBrowser(
        providers: _displayedProviders,
        searchQuery: _searchText,
        onViewHistory: (label) => setState(() {
          _selectedHistoryProvider = label;
          _selectedChangeId = null;
        }),
      );
    }

    // Events tab.
    final changes = _displayedChanges;
    return Column(
      children: [
        if (!_isEnabled)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MacOSColors.warningBackground,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: MacOSColors.warning.hexAlpha(0x20)),
            ),
            child: Row(
              children: const [
                BuoyGlyph(BuoyIcons.power,
                    size: 14, color: MacOSColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Provider capture is disabled',
                      style: TextStyle(
                          color: MacOSColors.warning, fontSize: 11)),
                ),
              ],
            ),
          ),
        Expanded(
          child: changes.isEmpty
              ? _emptyState(
                  BuoyIcons.box,
                  'No provider changes',
                  _isEnabled
                      ? 'Provider changes will appear here as values update.'
                      : 'Enable capture to start recording provider changes',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  itemCount: changes.length,
                  itemBuilder: (context, i) => ProviderChangeItem(
                    key: ValueKey(changes[i].id),
                    change: changes[i],
                    onPress: () =>
                        setState(() => _selectedChangeId = changes[i].id),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyState(LucideIcon icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BuoyGlyph(icon, size: 32, color: MacOSColors.textMuted),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(title,
                  style: const TextStyle(
                      color: MacOSColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: MacOSColors.textMuted,
                    fontSize: 12,
                    height: 18 / 12)),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _header() {
    if (_showFilters) {
      return ModalHeader(children: [
        ModalHeaderBack(onBack: () => setState(() => _showFilters = false)),
        const ModalHeaderContent(title: 'Filters', centered: true),
      ]);
    }

    final change = _selectedChange;
    if (change != null) {
      return ModalHeader(children: [
        ModalHeaderBack(onBack: () => setState(() => _selectedChangeId = null)),
        ModalHeaderContent(
          title:
              '${change.providerLabel}/${providerCategoryName(change.category)}',
          centered: true,
        ),
      ]);
    }

    final history = _selectedHistoryProvider;
    if (history != null) {
      return ModalHeader(children: [
        ModalHeaderBack(
          onBack: () => setState(() {
            _selectedHistoryProvider = null;
            _selectedChangeId = null;
          }),
        ),
        ModalHeaderContent(title: '$history History', centered: true),
        ModalHeaderActions(children: [
          CopyButton(
            value: _historySnapshot,
            size: 14,
            enabled: _activeChanges.isNotEmpty,
            idleColor: _activeChanges.isEmpty
                ? MacOSColors.textDisabled
                : MacOSColors.textSecondary,
            decoration: headerActionButtonDecoration(),
            width: 32,
            height: 32,
          ),
        ]),
      ]);
    }

    return ModalHeader(children: [
      ModalHeaderContent(child: _isSearchActive ? _searchField() : _tabs()),
      ModalHeaderActions(children: _actions()),
    ]);
  }

  Widget _tabs() {
    final providerCount = _displayedProviders.length;
    final changeCount = _displayedChanges.length;
    return TabSelector(
      tabs: [
        (
          key: 'providers',
          label:
              providerCount > 0 ? 'Providers ($providerCount)' : 'Providers'
        ),
        (key: 'events', label: changeCount > 0 ? 'Events ($changeCount)' : 'Events'),
      ],
      activeTab: _activeTab,
      onTabChange: _setTab,
    );
  }

  List<Widget> _actions() {
    return [
      HeaderActionButton(
        icon: BuoyIcons.search,
        color: MacOSColors.textSecondary,
        onTap: () {
          setState(() => _isSearchActive = true);
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _searchFocus.requestFocus());
        },
      ),
      HeaderActionButton(
        icon: BuoyIcons.filter,
        color:
            _hasActiveFilters ? MacOSColors.debug : MacOSColors.textSecondary,
        active: _hasActiveFilters,
        onTap: () => setState(() => _showFilters = true),
      ),
      if (_activeTab == 'providers')
        CopyButton(
          value: _providersSnapshot,
          size: 14,
          enabled: _displayedProviders.isNotEmpty,
          idleColor: _displayedProviders.isEmpty
              ? MacOSColors.textDisabled
              : MacOSColors.textSecondary,
          decoration: headerActionButtonDecoration(),
          width: 32,
          height: 32,
        ),
      if (_activeTab == 'events') ...[
        CopyButton(
          value: _changesSnapshot,
          size: 14,
          enabled: _displayedChanges.isNotEmpty,
          idleColor: _displayedChanges.isEmpty
              ? MacOSColors.textDisabled
              : MacOSColors.textSecondary,
          decoration: headerActionButtonDecoration(),
          width: 32,
          height: 32,
        ),
        PowerToggleButton(isEnabled: _isEnabled, onToggle: _toggleCapture),
        HeaderActionButton(
          icon: BuoyIcons.trash2,
          color: _displayedChanges.isEmpty
              ? MacOSColors.textDisabled
              : MacOSColors.textMuted,
          disabled: _displayedChanges.isEmpty,
          onTap: () {
            riverpodStateStore.clearChanges();
            setState(() => _selectedChangeId = null);
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
                    fontSize: 13, color: MacOSColors.textPrimary),
                cursorColor: MacOSColors.info,
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: _activeTab == 'providers'
                      ? 'Search providers...'
                      : 'Search events...',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: MacOSColors.textMuted),
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
                  _searchText = '';
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
