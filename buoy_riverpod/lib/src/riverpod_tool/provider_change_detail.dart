/// Ports packages/jotai/src/jotai/components/JotaiAtomDetailContent.tsx — the
/// per-change detail with a CHANGE / VALUE / DIFF toggle. DIFF drives the Part A
/// diff stack: [DiffModeTabs] (TREE/SPLIT) + [CompareBar] + [TreeDiffViewer] /
/// [SplitDiffViewer]. Stepping through the change list uses [EventStepperFooter].
library;

import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../riverpod_state_store.dart';
import '../riverpod_types.dart';

enum _DetailView { change, value, diff }

class ProviderChangeDetail extends StatefulWidget {
  const ProviderChangeDetail({
    super.key,
    required this.change,
    required this.changes,
    required this.selectedIndex,
    required this.onIndexChange,
    this.disableInternalFooter = false,
  });

  final ProviderChange change;
  final List<ProviderChange> changes;
  final int selectedIndex;
  final ValueChanged<int> onIndexChange;
  final bool disableInternalFooter;

  @override
  State<ProviderChangeDetail> createState() => _ProviderChangeDetailState();
}

class _ProviderChangeDetailState extends State<ProviderChangeDetail> {
  _DetailView _activeView = _DetailView.change;
  String _diffMode = 'tree';

  static String _formatTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(d.hour)}:${p(d.minute)}:${p(d.second)}.${p(d.millisecond, 3)}';
  }

  static String _formatTimestamp(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
  }

  static String _valueType(Object? value) {
    if (value == null) return 'null';
    if (value is List) return 'array';
    if (value is Map) return 'object';
    if (value is String) return 'string';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    return 'object';
  }

  @override
  Widget build(BuildContext context) {
    final change = widget.change;
    final total = widget.changes.length;
    final diffDisabled = total <= 1;
    final chronological = total - widget.selectedIndex;

    return Column(
      children: [
        _toggle(diffDisabled),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
                bottom: widget.disableInternalFooter ? 0 : 96),
            child: switch (_activeView) {
              _DetailView.change => _ChangeInfoView(change: change),
              _DetailView.value => _valueView(change),
              _DetailView.diff => _diffView(change, chronological),
            },
          ),
        ),
        if (!widget.disableInternalFooter && total > 1)
          EventStepperFooter(
            currentIndex: chronological - 1,
            totalItems: total,
            onPrevious: () => widget.onIndexChange(
                (widget.selectedIndex + 1).clamp(0, total - 1)),
            onNext: () => widget.onIndexChange(
                (widget.selectedIndex - 1).clamp(0, total - 1)),
            itemLabel: 'Change',
            subtitle: formatRelativeTime(change.timestamp),
          ),
      ],
    );
  }

  // ── CHANGE / VALUE / DIFF toggle ──────────────────────────────────────────

  Widget _toggle(bool diffDisabled) {
    final configs = [
      (_DetailView.change, 'CHANGE', BuoyIcons.fileText,
          MacOSColors.warning),
      (_DetailView.value, 'VALUE', BuoyIcons.database, MacOSColors.info),
      (_DetailView.diff, 'DIFF', BuoyIcons.gitBranch,
          MacOSColors.success),
    ];
    return Container(
      color: MacOSColors.backgroundBase,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          for (var i = 0; i < configs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _toggleCard(configs[i], diffDisabled)),
          ],
        ],
      ),
    );
  }

  Widget _toggleCard(
      (_DetailView, String, LucideIcon, Color) config, bool diffDisabled) {
    final (view, label, icon, activeColor) = config;
    final isActive = _activeView == view;
    final isDisabled = view == _DetailView.diff && diffDisabled;
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0x0D00B8E6)
            : MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          width: isActive ? 1.5 : 1,
          color: isActive ? activeColor : MacOSColors.borderDefault,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BuoyGlyph(icon,
              size: 14,
              color: isActive
                  ? activeColor
                  : isDisabled
                      ? MacOSColors.textMuted
                      : MacOSColors.textSecondary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isActive
                      ? activeColor
                      : isDisabled
                          ? MacOSColors.textMuted
                          : MacOSColors.textSecondary)),
        ],
      ),
    );
    if (isDisabled) return Opacity(opacity: 0.5, child: content);
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: () => setState(() => _activeView = view),
      child: content,
    );
  }

  // ── VALUE ───────────────────────────────────────────────────────────────

  Widget _valueView(ProviderChange change) {
    final color = Color(riverpodStateStore.providerColor(change.providerLabel));
    final label = providerCategoryBadge(change.category);
    final type = _valueType(change.nextValue).toUpperCase();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text('VALUE AFTER CHANGE',
                      style: TextStyle(
                          fontSize: 10,
                          color: MacOSColors.textSecondary,
                          fontFamily: 'monospace',
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w600)),
                ),
                Row(
                  children: [
                    _miniBadge(label, color, color.withValues(alpha: 0.12)),
                    const SizedBox(width: 6),
                    _miniBadge(type, MacOSColors.textMuted,
                        MacOSColors.backgroundInput),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: MacOSColors.backgroundBase,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: MacOSColors.borderDefault),
              ),
              clipBehavior: Clip.hardEdge,
              child: (change.nextValue is Map || change.nextValue is List)
                  ? DataViewer(
                      data: change.nextValue,
                      showTypeFilter: true,
                      initialExpanded: true)
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('${change.nextValue ?? "null"}',
                          style: const TextStyle(
                              color: MacOSColors.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBadge(String text, Color color, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 0.3,
                color: color)),
      );

  // ── DIFF ──────────────────────────────────────────────────────────────────

  Widget _diffView(ProviderChange change, int chronological) {
    final total = widget.changes.length;
    final prevIndex =
        widget.selectedIndex < total - 1 ? widget.selectedIndex + 1 : null;
    final prevChange = prevIndex != null ? widget.changes[prevIndex] : null;
    final prevChronological = chronological - 1;
    final atomColor =
        Color(riverpodStateStore.providerColor(change.providerLabel));

    final leftEvent = EventDisplayInfo(
      index: prevIndex ?? 0,
      label: prevChronological > 0 ? '#$prevChronological' : 'Initial',
      timestamp: prevChange != null ? _formatTimestamp(prevChange.timestamp) : '',
      relativeTime:
          prevChange != null ? formatRelativeTime(prevChange.timestamp) : 'value',
      badge: prevChange != null
          ? _diffBadge(
              providerCategoryBadge(prevChange.category),
              Color(riverpodStateStore.providerColor(prevChange.providerLabel)))
          : null,
    );
    final rightEvent = EventDisplayInfo(
      index: widget.selectedIndex,
      label: '#$chronological',
      timestamp: _formatTimestamp(change.timestamp),
      relativeTime: formatRelativeTime(change.timestamp),
      badge: _diffBadge(providerCategoryBadge(change.category), atomColor),
    );

    // The whole diff view scrolls (like the CHANGE/VALUE views) so it never
    // over-constrains its fixed header (DiffModeTabs + CompareBar) when the
    // modal sheet is short — the tree/split viewer gets a bounded height and
    // owns its own inner scroll.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: [
            DiffModeTabs(
              tabs: const [
                DiffModeTab(key: 'tree', label: 'TREE VIEW'),
                DiffModeTab(key: 'split', label: 'SPLIT VIEW'),
              ],
              activeTab: _diffMode,
              onTabChange: (m) => setState(() => _diffMode = m),
            ),
            CompareBar(leftEvent: leftEvent, rightEvent: rightEvent),
            SizedBox(
              height: 360,
              child: _diffMode == 'split'
                  ? SplitDiffViewer(
                      oldValue: change.prevValue,
                      newValue: change.nextValue,
                      theme: devToolsDefaultTheme,
                      options: const SplitDiffViewerOptions(),
                      height: 360,
                    )
                  : TreeDiffViewer(
                      oldValue: change.prevValue,
                      newValue: change.nextValue,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diffBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.125),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: color)),
      );
}

/// The CHANGE tab card (RN `JotaiAtomInfoView`).
class _ChangeInfoView extends StatelessWidget {
  const _ChangeInfoView({required this.change});

  final ProviderChange change;

  @override
  Widget build(BuildContext context) {
    final color = Color(riverpodStateStore.providerColor(change.providerLabel));
    final catLabel = providerCategoryBadge(change.category);
    final catColor = change.category == ProviderChangeCategory.initial
        ? BuoyColors.textMuted
        : change.category == ProviderChangeCategory.error
            ? BuoyColors.error
            : BuoyColors.success;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            icon: BuoyIcons.info,
            title: 'CHANGE INFO',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('Provider', change.providerLabel, valueColor: color),
                const SizedBox(height: 10),
                _infoRow('Time',
                    _ProviderChangeDetailState._formatTime(change.timestamp)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: catColor.hexAlpha(0x26),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(catLabel,
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: catColor)),
                    ),
                    if (change.hasValueChange)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: BuoyColors.success.hexAlpha(0x26),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const BuoyGlyph(BuoyIcons.zap,
                                size: 10, color: BuoyColors.success),
                            const SizedBox(width: 4),
                            Text(
                                change.diffSummary.isEmpty
                                    ? 'changed'
                                    : change.diffSummary,
                                style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: BuoyColors.success)),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: BuoyColors.input,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('no change',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: BuoyColors.textMuted)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (change.changedKeys.isNotEmpty) ...[
            const SizedBox(height: 16),
            _card(
              icon: BuoyIcons.zap,
              title: 'CHANGED KEYS',
              badge: '${change.changedKeys.length}',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final key in change.changedKeys)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BuoyColors.primary.hexAlpha(0x20),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: BuoyColors.primary.hexAlpha(0x40)),
                      ),
                      child: Text(key,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: BuoyColors.primary,
                              fontFamily: 'monospace')),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              CopyButton(
                value: () => change.nextValue,
                size: 14,
                idleColor: BuoyColors.primary,
              ),
              const SizedBox(width: 6),
              const Text('COPY VALUE',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      letterSpacing: 0.3,
                      color: BuoyColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card({
    required LucideIcon icon,
    required String title,
    String? badge,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: BuoyColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BuoyColors.primary.hexAlpha(0x4D)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: BuoyColors.primary.hexAlpha(0x15),
              border: Border(
                bottom:
                    BorderSide(color: BuoyColors.primary.hexAlpha(0x33)),
              ),
            ),
            child: Row(
              children: [
                BuoyGlyph(icon, size: 14, color: BuoyColors.primary),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: BuoyColors.primary,
                        fontFamily: 'monospace')),
                if (badge != null) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: BuoyColors.primary.hexAlpha(0x26),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: BuoyColors.primary,
                            fontFamily: 'monospace')),
                  ),
                ],
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: BuoyColors.textMuted,
                fontWeight: FontWeight.w500)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                  color: valueColor ?? BuoyColors.text)),
        ),
      ],
    );
  }
}
