/// Ports packages/shared/src/dataViewer/DataTreeActionDock.tsx.
///
/// The phone's edit controls — a fixed grid of six thumb-sized tiles, docked
/// under a full-screen tree.
///
/// The dashboard renders the same six actions as a row of small chips, which is
/// right beside a cursor and wrong under a thumb. Both read their list from
/// [treeActionsFor], so what's legal can't drift between them — only the shape
/// does.
///
/// Two tiles per row of three, always in the same slots, disabled rather than
/// hidden. See [treeActionsFor] for why the list is fixed-length.
///
/// RN numerics preserved: tile flexBasis 31% / minHeight 54 / radius 10, dock
/// padH 10 / padTop 8 / padBottom 10, gaps 8, icon 16 (18 for the chevrons).
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';

import '../data_viewer/json_ops.dart';
import '../data_viewer/tree_actions.dart';
import '../macos_colors.dart';

const _icon = 16.0;

/// Icons live with the renderer, not the action list — see [treeActionsFor].
LucideIcon _iconFor(TreeActionId id) => switch (id) {
  TreeActionId.editValue => BuoyIcons.edit3,
  TreeActionId.add => BuoyIcons.plus,
  TreeActionId.duplicate => BuoyIcons.copy,
  TreeActionId.moveUp => BuoyIcons.chevronUp,
  TreeActionId.moveDown => BuoyIcons.chevronDown,
  TreeActionId.remove => BuoyIcons.minus,
};

double _iconSizeFor(TreeActionId id) =>
    id == TreeActionId.moveUp || id == TreeActionId.moveDown
    ? _icon + 2
    : _icon;

class DataTreeActionDock extends StatelessWidget {
  const DataTreeActionDock({
    super.key,
    required this.root,
    required this.selection,
    required this.onEdit,
    required this.onSelectPath,
    required this.onEditValue,
    this.containersEditable = true,
  });

  /// The whole document, so the dock can see the selection's PARENT.
  final Object? root;

  /// Null dims every tile and shows the discoverability hint.
  final DataTreeSelection? selection;

  /// Apply one structural edit.
  final ValueChanged<JsonOp> onEdit;

  /// Move the highlight, for the ops that create or relocate a node.
  final ValueChanged<List<String>> onSelectPath;

  /// Open the host's value editor for the current selection.
  final VoidCallback onEditValue;

  /// Whether the host's value editor handles lists and maps (a raw-JSON mode).
  /// The phone's does.
  final bool containersEditable;

  void _run(TreeAction action) {
    // No op means the host has to ask the user something — today that's only
    // "edit this value". A boolean arrives here WITH an op and so just flips.
    final op = action.op;
    if (op == null) {
      onEditValue();
      return;
    }
    onEdit(op);
    // Ops that CREATE a node say where it landed; the ones that move or delete
    // one are handled by `selectionPathAfterOp` inside the host's draft.
    final after = action.selectAfter;
    if (after != null) onSelectPath(after);
  }

  @override
  Widget build(BuildContext context) {
    final actions = treeActionsFor(
      root,
      selection,
      containersEditable: containersEditable,
    );
    final current = selection;

    return Container(
      decoration: const BoxDecoration(
        color: MacOSColors.backgroundCard,
        border: Border(top: BorderSide(color: MacOSColors.borderDefault)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current != null
                        ? breadcrumb(current.path)
                        : 'Tap a row to select it',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: current != null
                          ? MacOSColors.textPrimary
                          : MacOSColors.textMuted,
                      fontSize: 12,
                      fontWeight: current != null
                          ? FontWeight.w600
                          : FontWeight.w400,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: MacOSColors.backgroundHover,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    current != null ? typeLabel(current.value) : '—',
                    style: const TextStyle(
                      color: MacOSColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Three per row, sized off the gaps rather than a fixed width so the
          // grid survives a narrow phone and a tablet split view alike.
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: tileWidth,
                      child: _Tile(action: action, onTap: () => _run(action)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.action, required this.onTap});

  final TreeAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = action.enabled;
    final isDanger = action.danger && enabled;
    final color = isDanger ? MacOSColors.error : MacOSColors.textSecondary;

    final tile = Opacity(
      // Dimmed, not removed — see [treeActionsFor].
      opacity: enabled ? 1 : 0.35,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDanger
                ? MacOSColors.error.hexAlpha(0x55)
                : MacOSColors.borderDefault,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            BuoyGlyph(
              _iconFor(action.id),
              size: _iconSizeFor(action.id),
              color: color,
            ),
            const SizedBox(height: 3),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDanger ? MacOSColors.error : MacOSColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    if (!enabled) return Semantics(label: action.label, enabled: false, child: tile);
    return Semantics(
      label: action.label,
      button: true,
      child: TouchableOpacity(activeOpacity: 0.6, onTap: onTap, child: tile),
    );
  }
}
