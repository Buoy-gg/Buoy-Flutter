/// Ports packages/shared/src/dataViewer/nestedPath.ts — the write kernel the
/// live explorer edits through (RN hoisted it from react-query, where the RQ
/// Data Editor had run on it in production; the network response editor
/// ports the same two functions).
///
/// Path-addressed edits on a decoded JSON value. Both return a NEW root and
/// never mutate the input, so the caller can diff, undo or discard freely.
///
/// A path is a `List<String>`; list indices are their decimal string, matching
/// how the explorer emits them. `[]` addresses the root. Dart has no Map/Set
/// distinction to preserve here — a decoded JSON body is only ever
/// `Map<String, dynamic>`, `List`, or a scalar.
library;

/// Replace the value at [updatePath]. An empty path replaces the whole
/// document.
Object? updateNestedDataByPath(
  Object? oldData,
  List<String> updatePath,
  Object? value,
) {
  if (updatePath.isEmpty) return value;

  final head = updatePath.first;
  final tail = updatePath.sublist(1);

  if (oldData is List) {
    final index = int.tryParse(head);
    if (index == null || index < 0 || index >= oldData.length) return oldData;
    final next = List<Object?>.of(oldData);
    next[index] = tail.isEmpty
        ? value
        : updateNestedDataByPath(next[index], tail, value);
    return next;
  }

  if (oldData is Map) {
    final next = <String, Object?>{
      for (final entry in oldData.entries) entry.key.toString(): entry.value,
    };
    next[head] = tail.isEmpty
        ? value
        : updateNestedDataByPath(next[head], tail, value);
    return next;
  }

  // A scalar can't be descended into; RN returns oldData unchanged here too.
  return oldData;
}

/// Remove the entry at [deletePath] (a list item or a map key).
Object? deleteNestedDataByPath(Object? oldData, List<String> deletePath) {
  if (deletePath.isEmpty) return oldData;

  final head = deletePath.first;
  final tail = deletePath.sublist(1);

  if (oldData is List) {
    if (tail.isEmpty) {
      // Filtered by INDEX-as-string, matching RN — which keeps the remaining
      // items' order and lets the tree re-label them from their new positions.
      final next = <Object?>[];
      for (var i = 0; i < oldData.length; i++) {
        if (i.toString() != head) next.add(oldData[i]);
      }
      return next;
    }
    final index = int.tryParse(head);
    if (index == null || index < 0 || index >= oldData.length) return oldData;
    final next = List<Object?>.of(oldData);
    next[index] = deleteNestedDataByPath(next[index], tail);
    return next;
  }

  if (oldData is Map) {
    final next = <String, Object?>{
      for (final entry in oldData.entries) entry.key.toString(): entry.value,
    };
    if (tail.isEmpty) {
      next.remove(head);
      return next;
    }
    next[head] = deleteNestedDataByPath(next[head], tail);
    return next;
  }

  return oldData;
}
