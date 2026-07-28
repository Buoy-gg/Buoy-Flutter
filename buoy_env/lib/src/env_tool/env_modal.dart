/// Ports packages/env-tools/src/env/components/EnvVarsModal.tsx — the env tool's
/// root surface: a [JsModal] whose header carries the title / inline search, and
/// whose scrolling body is the health header ([EnvStatsOverview]) + the filtered
/// variable list ([EnvVarSection]) or a search empty state. All view state
/// (active filter, search) lives in this one State. Reads the env source from
/// [BuoyEnv] (the Flutter analog of RN's `useDynamicEnv`).
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../env_store.dart';
import '../env_types.dart';
import '../env_validation.dart';
import 'env_stats_overview.dart';
import 'env_var_section.dart';

/// RN JsModal persistence key. RN's preset enables shared modal dimensions
/// (`@react_buoy_modal`); the Flutter ports each persist their own geometry, so
/// env uses `@react_buoy_env_modal` (DevToolsStorageKeys.env.modal()).
const String _envModalKey = '@react_buoy_env_modal';

/// Combined-list priority (EnvVarsModal.allVars sort): issues first.
const Map<EnvVarStatus, int> _priority = {
  EnvVarStatus.requiredMissing: 1,
  EnvVarStatus.requiredWrongType: 2,
  EnvVarStatus.requiredWrongValue: 3,
  EnvVarStatus.requiredPresent: 4,
  EnvVarStatus.optionalPresent: 5,
};

class EnvVarsModal extends StatefulWidget {
  const EnvVarsModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<EnvVarsModal> createState() => _EnvVarsModalState();
}

class _EnvVarsModalState extends State<EnvVarsModal> {
  EnvFilterType _activeFilter = EnvFilterType.all;
  bool _searchActive = false;
  String _query = '';

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    // Re-render if the app reconfigures the env source at runtime.
    _unsubscribe = BuoyEnv.instance.subscribe(() {
      if (mounted) setState(() {});
    });
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text != _query) setState(() => _query = text);
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collected = BuoyEnv.instance.vars;
    final required = BuoyEnv.instance.requiredEnvVars;
    final processed = processEnvVars(collected, required);
    final stats =
        calculateStats(processed.requiredVars, processed.optionalVars, collected);

    final pct = healthPercentage(stats);
    final status = healthStatusLabel(pct);
    final healthColor = pct == 100
        ? BuoyColors.success
        : (pct >= 75 ? BuoyColors.warning : BuoyColors.error);

    // Combined list, issues first (EnvVarsModal.allVars).
    final allVars = [...processed.requiredVars, ...processed.optionalVars]
      ..sort((a, b) =>
          (_priority[a.status] ?? 999) - (_priority[b.status] ?? 999));

    // Filter by active tab.
    var vars = switch (_activeFilter) {
      EnvFilterType.all => allVars,
      EnvFilterType.missing => allVars
          .where((v) => v.status == EnvVarStatus.requiredMissing)
          .toList(),
      EnvFilterType.issues => allVars
          .where((v) =>
              v.status == EnvVarStatus.requiredWrongType ||
              v.status == EnvVarStatus.requiredWrongValue)
          .toList(),
    };

    // Search filter (key / description / value).
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      vars = vars.where((v) {
        return v.key.toLowerCase().contains(q) ||
            (v.description?.toLowerCase().contains(q) ?? false) ||
            (v.value?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: _envModalKey,
      headerContent: _header(),
      child: ColoredBox(
        color: BuoyColors.base,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              EnvStatsOverview(
                stats: stats,
                healthPercentage: pct,
                healthStatus: status,
                healthColor: healthColor,
                activeFilter: _activeFilter,
                onFilterChange: (f) => setState(() {
                  _activeFilter = f;
                  _query = '';
                  _searchController.clear();
                  _searchActive = false;
                }),
              ),
              if (vars.isNotEmpty)
                _varsSection(vars)
              else
                _emptyState(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _header() {
    return ModalHeader(
      children: [
        ModalHeaderContent(
          noMargin: _searchActive,
          title: _searchActive ? '' : 'Environment Variables',
          child: _searchActive ? _searchField() : null,
        ),
        if (!_searchActive)
          ModalHeaderActions(
            children: [
              HeaderActionButton(
                icon: BuoyIcons.search,
                color: MacOSColors.textSecondary,
                onTap: () {
                  setState(() => _searchActive = true);
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _searchFocus.requestFocus());
                },
              ),
            ],
          ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: BuoyColors.input,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BuoyColors.border),
      ),
      child: Row(
        children: [
          const BuoyGlyph(BuoyIcons.search, size: 12, color: BuoyColors.textSecondary),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(
                  fontSize: 13,
                  color: BuoyColors.text,
                ),
                cursorColor: BuoyColors.primary,
                decoration: const InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search env keys...',
                  hintStyle:
                      TextStyle(fontSize: 13, color: BuoyColors.textMuted),
                ),
              ),
            ),
          ),
          TouchableOpacity(
            activeOpacity: 0.2,
            onTap: () {
              setState(() {
                _searchActive = false;
                _query = '';
              });
              _searchController.clear();
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: BuoyGlyph(BuoyIcons.x,
                  size: 12, color: BuoyColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ────────────────────────────────────────────────────────────────

  Widget _varsSection(List<EnvVarInfo> vars) {
    final title = switch (_activeFilter) {
      EnvFilterType.all => 'ALL VARIABLES',
      EnvFilterType.missing => 'MISSING VARIABLES',
      EnvFilterType.issues => 'ISSUES TO FIX',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: BuoyColors.textMuted,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: BuoyColors.primary.hexAlpha(0x15),
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(color: BuoyColors.primary.hexAlpha(0x40)),
                  ),
                  child: Text(
                    '${vars.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: BuoyColors.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          EnvVarSection(vars: vars),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final filterWord =
        _activeFilter == EnvFilterType.all ? '' : _activeFilter.name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BuoyGlyph(BuoyIcons.search, size: 32, color: BuoyColors.textMuted),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              _query.isNotEmpty ? 'No results found' : 'No variables',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BuoyColors.text,
              ),
            ),
          ),
          Text(
            _query.isNotEmpty
                ? 'No variables matching "$_query"'
                : 'No ${filterWord.isEmpty ? '' : '$filterWord '}variables found',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: BuoyColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
