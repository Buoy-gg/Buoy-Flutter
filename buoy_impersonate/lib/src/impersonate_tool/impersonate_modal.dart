/// Ports packages/impersonate/src/impersonate/components/ImpersonateModal.tsx
/// (+ the search half of hooks/useImpersonate.ts).
///
/// The impersonate tool's root surface: a JsModal (RN persistence key
/// `@react_buoy_impersonate_modal`) with a header that swaps between a tab
/// selector (Search / History / Settings) and a search field, over three tab
/// bodies. Subscribes to [BuoyImpersonate] for live state. Each screen owns its
/// scrolling, so JsModal's scroll wrapper is disabled.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../impersonate_store.dart';
import '../impersonate_types.dart';
import '../register.dart' show ImpersonateToolConfig;
import 'data_nuke_settings.dart';
import 'history_list.dart';
import 'user_search_view.dart';

/// RN `ImpersonateModal`.
class ImpersonateModal extends StatefulWidget {
  const ImpersonateModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<ImpersonateModal> createState() => _ImpersonateModalState();
}

class _ImpersonateModalState extends State<ImpersonateModal> {
  String _activeTab = 'search';
  bool _isSearchActive = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  String _searchQuery = '';
  List<ImpersonateUser> _searchResults = const [];
  bool _isSearching = false;
  String? _searchError;

  final _store = BuoyImpersonate.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChange);
    _searchFocus.addListener(() {
      // RN: blurring the search input closes it.
      if (!_searchFocus.hasFocus && _isSearchActive) {
        setState(() => _isSearchActive = false);
      }
    });
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChange);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  ImpersonateToolConfig get _config => ImpersonateToolConfig.instance;

  Future<void> _searchUsers(String query) async {
    setState(() {
      _searchQuery = query;
      _searchError = null;
    });
    if (query.trim().isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    final handler = _config.onSearchUsers;
    if (handler == null) {
      setState(() {
        _searchError = 'Search not configured';
        _searchResults = const [];
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await handler(query);
      if (!mounted) return;
      setState(() => _searchResults = results);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e is Error ? e.toString() : 'Search failed';
        _searchResults = const [];
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _submitSearch() {
    final text = _searchController.text.trim();
    if (text.isNotEmpty) _searchUsers(text);
    setState(() => _isSearchActive = false);
  }

  void _selectUser(ImpersonateUser user) => _store.startImpersonation(user);

  void _saveSettings(String headerKey, DataNukeSettings settings, bool showBanner) {
    _store.updateSettings(
      headerKey: headerKey,
      dataNukeSettings: settings,
      showBanner: showBanner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showSettingsTab = _config.showSettingsTab;
    // Reset to search if the settings tab is hidden while active (RN effect).
    if (!showSettingsTab && _activeTab == 'settings') _activeTab = 'search';

    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: '@react_buoy_impersonate_modal',
      wrapChildInScrollView: false,
      headerContent: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _headerContent(showSettingsTab),
      ),
      child: SizedBox.expand(
        child: ColoredBox(color: BuoyColors.base, child: _screen()),
      ),
    );
  }

  Widget _screen() {
    final state = _store.state;
    switch (_activeTab) {
      case 'history':
        return ImpersonateHistoryList(
          history: state.history,
          currentUserId: state.currentUser?.id,
          onSelectUser: _selectUser,
          onStopImpersonation: _store.stopImpersonation,
          onRemoveFromHistory: _store.removeFromHistory,
          onClearHistory: _store.clearHistory,
        );
      case 'settings':
        return DataNukeSettingsView(
          headerKey: state.headerKey,
          settings: state.dataNukeSettings,
          showBanner: state.showBanner,
          onSave: _saveSettings,
          onShowBannerChange: (v) => _store.updateSettings(showBanner: v),
          detectionStatus: (
            reactQuery: _config.reactQueryConfigured,
            redux: _config.reduxConfigured,
            asyncStorage: _config.asyncStorageConfigured,
            mmkv: _config.mmkvConfigured,
          ),
        );
      case 'search':
      default:
        return UserSearchView(
          currentUser: state.currentUser,
          searchQuery: _searchQuery,
          searchResults: _searchResults,
          isSearching: _isSearching,
          searchError: _searchError,
          onSelectUser: _selectUser,
          onStopImpersonation: _store.stopImpersonation,
          searchAvailable: _config.searchAvailable,
        );
    }
  }

  Widget _headerContent(bool showSettingsTab) {
    final tabs = <({String key, String label})>[
      (key: 'search', label: 'Search'),
      (key: 'history', label: 'History'),
      if (showSettingsTab) (key: 'settings', label: 'Settings'),
    ];

    return ModalHeader(
      children: [
        ModalHeaderContent(
          child: _isSearchActive
              ? _searchField()
              : TabSelector(
                  tabs: tabs,
                  activeTab: _activeTab,
                  onTabChange: (tab) => setState(() {
                    _activeTab = tab;
                    _isSearchActive = false;
                  }),
                ),
        ),
        ModalHeaderActions(
          children: [
            if (_activeTab == 'search' && !_isSearchActive)
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
        borderRadius: BorderRadius.circular(6),
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
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                style: const TextStyle(
                  fontSize: 13,
                  color: MacOSColors.textPrimary,
                ),
                cursorColor: MacOSColors.info,
                decoration: const InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search by email, name, or ID...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: MacOSColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          TouchableOpacity(
            activeOpacity: 0.2,
            onTap: () {
              _searchController.clear();
              setState(() => _isSearchActive = false);
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Padding(
                padding: EdgeInsets.all(4),
                child: BuoyGlyph(BuoyIcons.x, size: 14, color: MacOSColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
