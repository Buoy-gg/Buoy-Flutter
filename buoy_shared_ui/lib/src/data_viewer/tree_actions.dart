/// Ports packages/shared/src/dataViewer/treeActions.ts.
///
/// What you can do to the node a data explorer has selected — as data, not UI.
///
/// Two surfaces render this list and they look nothing alike: the dashboard's
/// footer bar is a row of small chips beside a cursor, the phone's full-screen
/// editor is a grid of thumb-sized tiles. Deriving both from one function is the
/// point — "can this item move up" is a property of the DOCUMENT, and having two
/// widgets each answer it from their own reading of `root` is how the two
/// surfaces quietly start disagreeing about what's legal.
///
/// So this module answers it once and hands back a list. The renderers decide
/// what a disabled action looks like and which icon it wears; they never decide
/// whether it applies.
library;

import 'json_ops.dart';

/// The node a data explorer currently has selected.
class DataTreeSelection {
  const DataTreeSelection({
    required this.path,
    required this.value,
    required this.label,
  });

  /// Path into the DATA (the tree's synthetic root segment already stripped).
  final List<String> path;
  final Object? value;

  /// The node's key, for labelling.
  final String label;
}

enum TreeActionId { editValue, add, duplicate, moveUp, moveDown, remove }

class TreeAction {
  const TreeAction({
    required this.id,
    required this.label,
    required this.enabled,
    required this.op,
    this.danger = false,
    this.selectAfter,
  });

  final TreeActionId id;

  /// Follows the selection — "Add key" on a map, "Append" on a list.
  final String label;
  final bool enabled;

  /// Destructive, so a renderer can colour it apart.
  final bool danger;

  /// The edit to apply, or null when the host has to ask the user something
  /// first (which is what `editValue` normally means).
  ///
  /// Renderers switch on this, not on [id]: apply the op when there is one,
  /// otherwise open the host's editor. That's what lets a boolean's "edit"
  /// become a one-tap toggle without either renderer knowing about booleans.
  final JsonOp? op;

  /// Where the selection should land once the op lands, for the ops that CREATE
  /// a node. ([selectionPathAfterOp] covers the ops that move or delete one; it
  /// can't cover these because it doesn't see the container's length.)
  final List<String>? selectAfter;
}

/// The node's type, as a badge shows it.
String typeLabel(Object? value) {
  if (value == null) return 'null';
  if (value is List) return 'array';
  if (isRebuildableObject(value)) return 'object';
  if (value is String) return 'string';
  if (value is bool) return 'boolean';
  if (value is num) return 'number';
  return 'object';
}

/// `a › b › 2` — reads as a location, which a bare index like `2` does not.
String breadcrumb(List<String> path) =>
    path.isEmpty ? 'root' : path.join(' › ');

/// Index the list by id, for renderers that lay the six out in their own order.
Map<TreeActionId, TreeAction> treeActionMap(List<TreeAction> actions) => {
  for (final action in actions) action.id: action,
};

/// A key that doesn't collide, for "add" on a map.
String _newKeyFor(Map container) {
  if (!container.containsKey('newKey')) return 'newKey';
  var n = 2;
  while (container.containsKey('newKey $n')) {
    n++;
  }
  return 'newKey $n';
}

/// The six things a selection can do, ALWAYS in this order and always all six.
///
/// Returning the inapplicable ones as `enabled: false` rather than omitting
/// them is deliberate and is why this returns a fixed-length list: a renderer
/// that drops entries reflows every time the selection moves, so stepping from
/// item 1 to item 0 would slide the remaining controls sideways under a finger
/// already on its way down. Stable position also means the same action is
/// always in the same place, which is most of what makes a grid of six
/// learnable.
///
/// [containersEditable] says whether the host's value editor can take a whole
/// list or map. The phone's editor pushes a screen with a raw-JSON mode, so it
/// can. A single-line field inside a 28px row can't — and offering "Edit value"
/// on a 40-key map there would open a field that physically cannot show it.
List<TreeAction> treeActionsFor(
  Object? root,
  DataTreeSelection? selection, {
  bool containersEditable = false,
}) {
  final path = selection?.path ?? const <String>[];
  final value = selection?.value;
  final has = selection != null;
  final isRoot = path.isEmpty;

  final parent = has && !isRoot
      ? getAtPath(root, path.sublist(0, path.length - 1))
      : null;
  final parentIsList = parent is List;
  final index = parentIsList ? (int.tryParse(path.last) ?? -1) : -1;

  final isList = value is List;
  // Spelled as an `is` test rather than `isRebuildableObject(value)` so flow
  // analysis promotes `value` for the map-shaped branches below.
  final isMap = value is Map;
  final isContainer = isEditableContainer(value);

  final canEditValue = has && (containersEditable || !isContainer);

  // One "+" slot whose meaning follows the container type, rather than two
  // mutually-exclusive buttons of which one is always dead.
  final addedKey = isMap ? _newKeyFor(value) : '';
  final add = isMap
      ? TreeAction(
          id: TreeActionId.add,
          label: 'Add key',
          enabled: true,
          op: JsonAddKeyOp(path, addedKey, suggestedNewValue(value)),
          selectAfter: [...path, addedKey],
        )
      : TreeAction(
          id: TreeActionId.add,
          label: 'Append',
          enabled: isList,
          op: isList ? JsonAppendOp(path, suggestedNewValue(value)) : null,
          selectAfter: isList ? [...path, '${value.length}'] : null,
        );

  final canMoveUp = has && parentIsList && index > 0;
  final canMoveDown =
      has && parentIsList && index > -1 && index < parent.length - 1;

  return [
    // A boolean has exactly two states, so there is nothing to ask and nothing
    // to type — an editor for it would be a screen whose only job is to offer
    // the value you didn't pick. It flips in place instead.
    if (value is bool)
      TreeAction(
        id: TreeActionId.editValue,
        label: 'Toggle',
        enabled: true,
        op: JsonReplaceOp(path, !value),
      )
    else
      TreeAction(
        id: TreeActionId.editValue,
        label: 'Edit value',
        enabled: canEditValue,
        op: null,
      ),
    add,
    TreeAction(
      // `duplicate` handles map keys too (it mints a "<key> copy" in place),
      // so this applies to any entry that has a parent.
      id: TreeActionId.duplicate,
      label: 'Duplicate',
      enabled: has && !isRoot,
      op: has && !isRoot ? JsonDuplicateOp(path) : null,
    ),
    TreeAction(
      id: TreeActionId.moveUp,
      label: 'Move up',
      enabled: canMoveUp,
      op: canMoveUp ? JsonMoveOp(path, index - 1) : null,
    ),
    TreeAction(
      id: TreeActionId.moveDown,
      label: 'Move down',
      enabled: canMoveDown,
      op: canMoveDown ? JsonMoveOp(path, index + 1) : null,
    ),
    TreeAction(
      id: TreeActionId.remove,
      label: 'Remove',
      danger: true,
      enabled: has && !isRoot,
      op: has && !isRoot ? JsonRemoveOp(path) : null,
    ),
  ];
}
