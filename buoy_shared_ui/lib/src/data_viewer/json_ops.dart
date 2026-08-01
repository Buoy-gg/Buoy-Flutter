/// Ports packages/shared/src/dataViewer/jsonOps.ts.
///
/// Structural edits to a JSON value, addressed by path.
///
/// Why an op vocabulary instead of "here's the new value": editing a container
/// as text is fine for a three-item list and miserable for a fifty-item one.
/// Every real JSON editor converges on the same primitives because JSON Patch
/// (RFC 6902) already standardized them — add / remove / replace / move / copy,
/// addressed by a pointer into the document.
///
/// This is that set, named for humans and specialized for a UI:
///   - list-shaped ops carry the intent ("append", "insert at 3") rather than
///     making the caller compute the resulting list
///   - [JsonRenameKeyOp] preserves key ORDER, which a naive delete-then-add
///     loses and which readers notice immediately
///
/// Ops are pure and immutable: [applyJsonOp] returns a new root and never
/// mutates the input, so callers can diff, undo, or discard freely.
///
/// A path is the same `List<String>` the data explorer already flattens rows
/// with (a JSON Pointer in disguise). `[]` addresses the root. List indices are
/// their decimal string, matching how the explorer emits them.
///
/// Scope: `List` and `Map<String, dynamic>`-shaped maps. Anything else at a
/// path is returned untouched — those can't round-trip through JSON anyway, and
/// silently rebuilding one as a plain map would lose more than it fixed.
library;

/// A structural edit. `path` addresses the node the verb reads naturally
/// against.
sealed class JsonOp {
  const JsonOp(this.path);

  final List<String> path;
}

/// Replace the value AT [path]. An empty path replaces the whole document.
class JsonReplaceOp extends JsonOp {
  const JsonReplaceOp(super.path, this.value);
  final Object? value;
}

/// Remove the entry AT [path] (a list item or a map key).
class JsonRemoveOp extends JsonOp {
  const JsonRemoveOp(super.path);
}

/// Append to the list AT [path].
class JsonAppendOp extends JsonOp {
  const JsonAppendOp(super.path, this.value);
  final Object? value;
}

/// Insert into the list AT [path], before [index].
class JsonInsertOp extends JsonOp {
  const JsonInsertOp(super.path, this.index, this.value);
  final int index;
  final Object? value;
}

/// Move the list item AT [path] to [toIndex] within its parent list.
class JsonMoveOp extends JsonOp {
  const JsonMoveOp(super.path, this.toIndex);
  final int toIndex;
}

/// Copy the entry AT [path] in beside itself (lists: after; maps: "key copy").
class JsonDuplicateOp extends JsonOp {
  const JsonDuplicateOp(super.path);
}

/// Empty the list or map AT [path], keeping the container itself.
class JsonClearOp extends JsonOp {
  const JsonClearOp(super.path);
}

/// Add [key] to the map AT [path].
class JsonAddKeyOp extends JsonOp {
  const JsonAddKeyOp(super.path, this.key, this.value);
  final String key;
  final Object? value;
}

/// Rename the map entry AT [path] to [key], keeping its position.
class JsonRenameKeyOp extends JsonOp {
  const JsonRenameKeyOp(super.path, this.key);
  final String key;
}

/// Maps this module is willing to REBUILD.
///
/// The RN original checks the prototype so a class instance is refused: a
/// spread would silently drop its prototype and hand back something that no
/// longer behaves like the original. Dart's analog is "is it a Map at all" —
/// anything that isn't gets returned untouched by every op below.
bool isRebuildableObject(Object? value) => value is Map;

/// True when a path addresses a container this module can edit.
bool isEditableContainer(Object? value) =>
    value is List || isRebuildableObject(value);

/// Where the selection should sit after [op] is applied.
///
/// An op reshapes the document, so the path the user had selected may now name
/// a DIFFERENT node — move item 3 to slot 2 and path `3` is whatever got
/// displaced, not the thing you just moved. Following the edit is what makes
/// the highlight mean "the node I acted on" rather than "the slot I acted
/// from".
///
/// Returns [SelectionUnchanged] to leave the selection alone, or a result whose
/// [SelectionAfterOp.path] is null to clear it. (The RN original distinguishes
/// `undefined` from `null`; Dart has one null, so the distinction is a type.)
SelectionAfterOp selectionPathAfterOp(JsonOp op) {
  switch (op) {
    // Follow the node to its new slot.
    case JsonMoveOp(:final path, :final toIndex):
      return SelectionAfterOp([...path.sublist(0, path.length - 1), '$toIndex']);
    // The copy lands directly after the original, and is the thing you meant.
    case JsonDuplicateOp(:final path):
      if (path.isEmpty) return const SelectionUnchanged();
      final index = int.tryParse(path.last);
      return index == null
          ? const SelectionUnchanged()
          : SelectionAfterOp(
              [...path.sublist(0, path.length - 1), '${index + 1}'],
            );
    // The selected node no longer exists.
    case JsonRemoveOp():
      return const SelectionAfterOp(null);
    default:
      return const SelectionUnchanged();
  }
}

/// Result of [selectionPathAfterOp] — a path, or null to clear the selection.
class SelectionAfterOp {
  const SelectionAfterOp(this.path);
  final List<String>? path;
}

/// "Leave the selection where it is" — the RN `undefined` return.
class SelectionUnchanged extends SelectionAfterOp {
  const SelectionUnchanged() : super(null);
}

/// Read the value at [path], or null if the path doesn't resolve.
Object? getAtPath(Object? root, List<String> path) {
  Object? node = root;
  for (final segment in path) {
    if (node is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= node.length) return null;
      node = node[index];
    } else if (node is Map) {
      node = node[segment];
    } else {
      return null;
    }
  }
  return node;
}

/// Rebuild [root] with the container at [path] replaced by [updater]'s result.
///
/// Everything else is expressed through this: an op on an entry is an op on its
/// PARENT container, which is also why removal and rename are possible at all —
/// they change the shape of the parent, not the value of the child.
Object? _updateContainer(
  Object? root,
  List<String> path,
  Object? Function(Object? container) updater,
) {
  if (path.isEmpty) return updater(root);

  final head = path.first;
  final rest = path.sublist(1);

  if (root is List) {
    final index = int.tryParse(head);
    if (index == null || index < 0 || index >= root.length) return root;
    final next = [...root];
    next[index] = _updateContainer(next[index], rest, updater);
    return next;
  }

  if (root is Map) {
    if (!root.containsKey(head)) return root;
    final next = _mapOf(root);
    next[head] = _updateContainer(root[head], rest, updater);
    return next;
  }

  // Path runs past something we don't edit — leave the document alone.
  return root;
}

/// A modifiable string-keyed copy, preserving insertion order.
Map<String, Object?> _mapOf(Map source) => {
  for (final entry in source.entries) '${entry.key}': entry.value,
};

/// Apply [op] to [root], returning a new value.
///
/// Never throws and never mutates: an op that doesn't apply (bad path, wrong
/// container type, index out of range) returns [root] unchanged, so a stale tap
/// from a tree that rebuilt underneath the user is a no-op rather than a
/// corrupted document.
Object? applyJsonOp(Object? root, JsonOp op) {
  switch (op) {
    case JsonReplaceOp(:final path, :final value):
      return _updateContainer(root, path, (_) => value);

    case JsonClearOp(:final path):
      return _updateContainer(root, path, (container) {
        if (container is List) return <Object?>[];
        if (container is Map) return <String, Object?>{};
        return container;
      });

    case JsonAppendOp(:final path, :final value):
      return _updateContainer(
        root,
        path,
        (container) => container is List ? [...container, value] : container,
      );

    case JsonInsertOp(:final path, :final index, :final value):
      return _updateContainer(root, path, (container) {
        if (container is! List) return container;
        final at = _clamp(index, 0, container.length);
        return [...container.sublist(0, at), value, ...container.sublist(at)];
      });

    case JsonAddKeyOp(:final path, :final key, :final value):
      return _updateContainer(root, path, (container) {
        if (container is! Map) return container;
        // Refuse to clobber: an "add" that silently overwrote an existing key
        // would lose data the user never saw.
        if (container.containsKey(key)) return container;
        return _mapOf(container)..[key] = value;
      });

    case JsonRemoveOp(:final path):
      final split = _splitPath(path);
      if (split == null) return root; // Removing the root is meaningless.
      return _updateContainer(
        root,
        split.parent,
        (container) => _removeEntry(container, split.last),
      );

    case JsonDuplicateOp(:final path):
      final split = _splitPath(path);
      if (split == null) return root;
      return _updateContainer(
        root,
        split.parent,
        (container) => _duplicateEntry(container, split.last),
      );

    case JsonMoveOp(:final path, :final toIndex):
      final split = _splitPath(path);
      if (split == null) return root;
      return _updateContainer(root, split.parent, (container) {
        if (container is! List) return container;
        final from = int.tryParse(split.last);
        if (from == null || from < 0 || from >= container.length) {
          return container;
        }
        final to = _clamp(toIndex, 0, container.length - 1);
        if (to == from) return container;
        final next = [...container];
        final item = next.removeAt(from);
        next.insert(to, item);
        return next;
      });

    case JsonRenameKeyOp(:final path, :final key):
      final split = _splitPath(path);
      if (split == null) return root;
      return _updateContainer(
        root,
        split.parent,
        (container) => _renameEntry(container, split.last, key),
      );
  }
}

({List<String> parent, String last})? _splitPath(List<String> path) {
  if (path.isEmpty) return null;
  return (parent: path.sublist(0, path.length - 1), last: path.last);
}

Object? _removeEntry(Object? container, String segment) {
  if (container is List) {
    final index = int.tryParse(segment);
    if (index == null || index < 0 || index >= container.length) {
      return container;
    }
    return [
      for (var i = 0; i < container.length; i++)
        if (i != index) container[i],
    ];
  }
  if (container is Map) {
    if (!container.containsKey(segment)) return container;
    return {
      for (final entry in container.entries)
        if ('${entry.key}' != segment) '${entry.key}': entry.value,
    };
  }
  return container;
}

Object? _duplicateEntry(Object? container, String segment) {
  if (container is List) {
    final index = int.tryParse(segment);
    if (index == null || index < 0 || index >= container.length) {
      return container;
    }
    return [
      ...container.sublist(0, index + 1),
      _clone(container[index]),
      ...container.sublist(index + 1),
    ];
  }
  if (container is Map) {
    if (!container.containsKey(segment)) return container;
    // Maps have no "next to" — mint a non-colliding key and keep position.
    final copyKey = _uniqueKey(container, '$segment copy');
    final next = <String, Object?>{};
    for (final entry in container.entries) {
      final key = '${entry.key}';
      next[key] = entry.value;
      if (key == segment) next[copyKey] = _clone(entry.value);
    }
    return next;
  }
  return container;
}

/// Rename in place. Rebuilt key-by-key rather than delete-then-assign so the
/// entry keeps its position — a map whose keys reshuffle on every rename reads
/// as though the edit did something it didn't.
Object? _renameEntry(Object? container, String segment, String nextKey) {
  if (container is! Map) return container;
  if (!container.containsKey(segment)) return container;
  if (nextKey == segment) return container;
  if (container.containsKey(nextKey)) return container; // Would clobber.

  final next = <String, Object?>{};
  for (final entry in container.entries) {
    final key = '${entry.key}';
    if (key == segment) {
      next[nextKey] = entry.value;
    } else {
      next[key] = entry.value;
    }
  }
  return next;
}

/// `base`, `base 2`, `base 3`… until it doesn't collide.
String _uniqueKey(Map container, String base) {
  if (!container.containsKey(base)) return base;
  var n = 2;
  while (container.containsKey('$base $n')) {
    n++;
  }
  return '$base $n';
}

/// Structural copy, so a duplicated container isn't shared with its original.
Object? _clone(Object? value) {
  if (value is List) return [for (final item in value) _clone(item)];
  if (value is Map) {
    return {
      for (final entry in value.entries) '${entry.key}': _clone(entry.value),
    };
  }
  return value;
}

int _clamp(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

/// A sensible starting value when adding an entry, matching the container's
/// existing items so "append" to a list of numbers doesn't hand back a string.
Object? suggestedNewValue(Object? container) {
  final samples = container is List
      ? container
      : (container is Map ? container.values.toList() : const []);
  final last = samples.isEmpty ? null : samples.last;
  if (last is num) return 0;
  if (last is bool) return false;
  if (last is List) return <Object?>[];
  if (last is Map) return <String, Object?>{};
  return '';
}
