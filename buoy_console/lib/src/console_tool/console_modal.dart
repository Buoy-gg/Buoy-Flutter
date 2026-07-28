/// Ports packages/console/src/components/ConsoleModal.tsx +
/// devtools/useConsoleController.ts + ConsoleHeader.tsx + ConsoleBody.tsx.
///
/// The console tool's root surface: a [JsModal] whose header carries the
/// Timeline/Grouped [TabSelector] (or the search field), plus search / filter /
/// clear actions, and whose body is the log list or the back-navigable Filters
/// sub-view (log levels + settings). All view state lives in this one State —
/// folding RN's controller + header + body into a single widget, matching the
/// storage_modal.dart precedent. `wrapChildInScrollView: false` — the log list
/// owns scrolling.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../console_log_store.dart';
import '../devtools/console_filter.dart';
import '../devtools/console_message_row.dart';
import '../devtools/console_messages.dart';
import '../devtools/console_origin.dart';
import '../devtools/console_theme.dart';

/// RN JsModal persistence key (`@react_buoy_<tool>_modal` convention).
const String _consoleModalKey = '@react_buoy_console_modal';

enum _ConsoleView { list, filters }

class ConsoleModal extends StatefulWidget {
  const ConsoleModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<ConsoleModal> createState() => _ConsoleModalState();
}

class _ConsoleModalState extends State<ConsoleModal> {
  // View state (RN useConsoleController).
  String _query = '';
  bool _searchActive = false;
  LevelsMask _levelsMask = defaultLevels;
  bool _showTimestamps = false;
  LayoutMode _layoutMode = LayoutMode.chrono;
  _ConsoleView _view = _ConsoleView.list;
  final Map<int, bool> _collapsedOverrides = {};
  final Map<String, bool> _clusterExpanded = {};

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  void Function()? _unsubscribe;
  void Function()? _unsubscribePreserve;

  // The log-list scroll + stick-to-bottom (RN ConsoleList).
  final _scrollController = ScrollController();
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _unsubscribe = ConsoleLogStore.instance.subscribe(() {
      if (mounted) setState(() {});
    });
    _unsubscribePreserve = ConsoleLogStore.instance.subscribePreserveLog(() {
      if (mounted) setState(() {});
    });
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text != _query) setState(() => _query = text);
    });
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      _stickToBottom = (pos.maxScrollExtent - pos.pixels) < 40;
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _unsubscribePreserve?.call();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ConsoleMessagesResult get _messages => buildDisplayRows(
        ConsoleLogStore.instance.entries,
        BuildOptions(
          levelsMask: _levelsMask,
          query: _query,
          showTimestamps: _showTimestamps,
          collapsedOverrides: _collapsedOverrides,
          groupDimension: GroupDimension.function,
          layoutMode: _layoutMode,
          clusterExpanded: _clusterExpanded,
        ),
      );

  bool get _isLevelCustom {
    final summary = levelMenuSummary(_levelsMask);
    return summary != 'All levels' && summary != 'Default levels';
  }

  void _clear() {
    ConsoleLogStore.instance.clearEntries();
    setState(_collapsedOverrides.clear);
  }

  @override
  Widget build(BuildContext context) {
    final result = _messages;
    // Stick to bottom after the frame if we were near the bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stickToBottom && _scrollController.hasClients) {
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: _consoleModalKey,
      wrapChildInScrollView: false,
      headerContent: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _header(result),
      ),
      child: SizedBox.expand(
        child: ColoredBox(
          color: ConsoleTheme.baseContainer,
          child: _view == _ConsoleView.filters
              ? _filtersView()
              : _list(result),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _header(ConsoleMessagesResult result) {
    if (_view == _ConsoleView.filters) {
      return ModalHeader(
        children: [
          ModalHeaderBack(onBack: () => setState(() => _view = _ConsoleView.list)),
          const ModalHeaderContent(title: 'Filters'),
        ],
      );
    }

    final hasRows = result.rows.isNotEmpty;
    return ModalHeader(
      children: [
        ModalHeaderContent(
          noMargin: true,
          child: _searchActive ? _searchField() : _layoutTabs(),
        ),
        ModalHeaderActions(
          children: [
            HeaderActionButton(
              icon: BuoyIcons.search,
              color: _searchActive
                  ? MacOSColors.info
                  : MacOSColors.textSecondary,
              active: _searchActive,
              onTap: () {
                setState(() => _searchActive = !_searchActive);
                if (_searchActive) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _searchFocus.requestFocus());
                }
              },
            ),
            HeaderActionButton(
              icon: BuoyIcons.filter,
              color:
                  _isLevelCustom ? MacOSColors.info : MacOSColors.textMuted,
              active: _isLevelCustom,
              onTap: () => setState(() => _view = _ConsoleView.filters),
            ),
            HeaderActionButton(
              icon: BuoyIcons.trash2,
              color:
                  hasRows ? MacOSColors.textMuted : MacOSColors.textDisabled,
              disabled: !hasRows,
              onTap: _clear,
            ),
          ],
        ),
      ],
    );
  }

  Widget _layoutTabs() {
    return TabSelector(
      tabs: const [
        (key: 'chrono', label: 'Timeline'),
        (key: 'cluster', label: 'Grouped'),
      ],
      activeTab: _layoutMode == LayoutMode.cluster ? 'cluster' : 'chrono',
      onTabChange: (key) => setState(() {
        _layoutMode =
            key == 'cluster' ? LayoutMode.cluster : LayoutMode.chrono;
      }),
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
                enableSuggestions: false,
                onSubmitted: (_) => setState(() => _searchActive = false),
                style: const TextStyle(
                  fontSize: 13,
                  color: MacOSColors.textPrimary,
                ),
                cursorColor: MacOSColors.info,
                decoration: const InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Filter logs…  /regex/  -exclude',
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
                setState(() => _query = '');
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

  // ── Body: log list ────────────────────────────────────────────────────────

  Widget _list(ConsoleMessagesResult result) {
    final rows = result.rows;
    return ListView.builder(
      controller: _scrollController,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return ConsoleMessageRow(
          key: ValueKey(row.key),
          row: row,
          showTimestamps: _showTimestamps,
          onToggleGroup: (groupId, currentlyCollapsed) => setState(() {
            _collapsedOverrides[groupId] = !currentlyCollapsed;
          }),
          onToggleCluster: (key) => setState(() {
            _clusterExpanded[key] = !(_clusterExpanded[key] ?? false);
          }),
        );
      },
    );
  }

  // ── Body: filters sub-view ─────────────────────────────────────────────────

  Widget _filtersView() {
    final preserveLog = ConsoleLogStore.instance.preserveLog;
    return ColoredBox(
      color: MacOSColors.backgroundBase,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionLabel('Log levels'),
          _presetRow('Default (hide verbose)',
              () => setState(() => _levelsMask = defaultLevels)),
          _presetRow('All levels',
              () => setState(() => _levelsMask = allLevels)),
          for (final level in levelOrder)
            _checkRow(
              on: _levelsMask[level],
              label: levelLabel[level]!,
              onTap: () =>
                  setState(() => _levelsMask = _levelsMask.toggled(level)),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 0.5, color: MacOSColors.borderDefault),
          ),
          _sectionLabel('Settings'),
          _checkRow(
            on: _showTimestamps,
            label: 'Show timestamps',
            onTap: () => setState(() => _showTimestamps = !_showTimestamps),
          ),
          _checkRow(
            on: preserveLog,
            label: 'Preserve log',
            subtext: 'Do not clear log on reload',
            onTap: () =>
                ConsoleLogStore.instance.setPreserveLog(!preserveLog),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: MacOSColors.textMuted,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _presetRow(String text, VoidCallback onTap) => TouchableOpacity(
        activeOpacity: 0.7,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(
            text,
            style: const TextStyle(
              color: MacOSColors.info,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  Widget _checkRow({
    required bool on,
    required String label,
    String? subtext,
    required VoidCallback onTap,
  }) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? MacOSColors.info : null,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: on ? MacOSColors.info : MacOSColors.borderDefault,
                ),
              ),
              child: on
                  ? const BuoyGlyph(BuoyIcons.check,
                      size: 12, color: MacOSColors.backgroundBase)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: MacOSColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  if (subtext != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtext,
                        style: const TextStyle(
                          color: MacOSColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
