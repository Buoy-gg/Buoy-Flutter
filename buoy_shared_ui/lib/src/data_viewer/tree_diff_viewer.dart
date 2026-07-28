/// Ports packages/shared/src/dataViewer/tree/TreeDiffViewer.tsx — a
/// hierarchical diff that shows added (+), removed (−) and changed (≈) nodes
/// with a global line-number gutter, colored markers, and expand/collapse for
/// complex values. Default (dark) theme reads [GameUIDiffColors] (RN
/// `gameUIColors.diff`).
///
/// RN numerics preserved: row minHeight 26, lineNumber gutter 32, marker 20,
/// content font 11 monospace, indent 20/depth, key 11/500, arrow " => ".
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../game_ui_colors.dart';
import 'line_diff.dart' show isAbsent;

enum _DiffType { added, removed, changed, unchanged }

class _DiffNode {
  _DiffNode({
    required this.key,
    required this.path,
    required this.type,
    this.oldValue,
    this.newValue,
    this.children,
  });

  final String key;
  final List<String> path;
  final _DiffType type;
  final Object? oldValue;
  final Object? newValue;
  final List<_DiffNode>? children;
}

bool _isObject(Object? o) => o is Map;

bool _isEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_isEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_isEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

List<_DiffNode> _computeDiff(
  Object? rawOldValue,
  Object? rawNewValue, [
  List<String> path = const [],
]) {
  final result = <_DiffNode>[];

  // A side marked absent never existed, so it contributes nothing and the other
  // side reads as purely added (or removed). Only the root can be absent.
  final oldValue = isAbsent(rawOldValue) ? null : rawOldValue;
  final newValue = isAbsent(rawNewValue) ? null : rawNewValue;

  // Primitives.
  if (!_isObject(oldValue) &&
      !_isObject(newValue) &&
      oldValue is! List &&
      newValue is! List) {
    final key = path.isNotEmpty ? path.last : 'root';
    if (!_isEqual(oldValue, newValue)) {
      result.add(_DiffNode(
        key: key,
        path: path,
        type: oldValue == null
            ? _DiffType.added
            : newValue == null
                ? _DiffType.removed
                : _DiffType.changed,
        oldValue: oldValue,
        newValue: newValue,
      ));
    } else {
      result.add(_DiffNode(
        key: key,
        path: path,
        type: _DiffType.unchanged,
        oldValue: oldValue,
        newValue: newValue,
      ));
    }
    return result;
  }

  // Arrays.
  if (oldValue is List || newValue is List) {
    final oldArr = oldValue is List ? oldValue : const [];
    final newArr = newValue is List ? newValue : const [];
    final maxLen = oldArr.length > newArr.length ? oldArr.length : newArr.length;
    for (var i = 0; i < maxLen; i++) {
      final itemPath = [...path, '[$i]'];
      final oldItem = i < oldArr.length ? oldArr[i] : null;
      final newItem = i < newArr.length ? newArr[i] : null;
      final inOld = i < oldArr.length;
      final inNew = i < newArr.length;

      if (!inOld) {
        final complex = newItem is List || _isObject(newItem);
        result.add(_DiffNode(
          key: '[$i]',
          path: itemPath,
          type: _DiffType.added,
          newValue: newItem,
          children: complex
              ? _computeDiff(newItem is List ? const [] : const {}, newItem,
                  itemPath)
              : null,
        ));
      } else if (!inNew) {
        final complex = oldItem is List || _isObject(oldItem);
        result.add(_DiffNode(
          key: '[$i]',
          path: itemPath,
          type: _DiffType.removed,
          oldValue: oldItem,
          children: complex
              ? _computeDiff(oldItem, oldItem is List ? const [] : const {},
                  itemPath)
              : null,
        ));
      } else if (!_isEqual(oldItem, newItem)) {
        final complex = _isObject(oldItem) ||
            _isObject(newItem) ||
            oldItem is List ||
            newItem is List;
        result.add(_DiffNode(
          key: '[$i]',
          path: itemPath,
          type: _DiffType.changed,
          oldValue: oldItem,
          newValue: newItem,
          children: complex ? _computeDiff(oldItem, newItem, itemPath) : null,
        ));
      } else {
        final complex = oldItem is List || _isObject(oldItem);
        result.add(_DiffNode(
          key: '[$i]',
          path: itemPath,
          type: _DiffType.unchanged,
          oldValue: oldItem,
          newValue: newItem,
          children: complex ? _computeDiff(oldItem, newItem, itemPath) : null,
        ));
      }
    }
    return result;
  }

  // Objects.
  final oldObj = _isObject(oldValue) ? oldValue as Map : const {};
  final newObj = _isObject(newValue) ? newValue as Map : const {};
  final allKeys = <Object?>{...oldObj.keys, ...newObj.keys};
  for (final key in allKeys) {
    final keyStr = '$key';
    final keyPath = [...path, keyStr];
    final oldVal = oldObj[key];
    final newVal = newObj[key];
    final inOld = oldObj.containsKey(key);
    final inNew = newObj.containsKey(key);

    if (!inOld) {
      final complex = newVal is List || _isObject(newVal);
      result.add(_DiffNode(
        key: keyStr,
        path: keyPath,
        type: _DiffType.added,
        newValue: newVal,
        children: complex
            ? _computeDiff(newVal is List ? const [] : const {}, newVal, keyPath)
            : null,
      ));
    } else if (!inNew) {
      final complex = oldVal is List || _isObject(oldVal);
      result.add(_DiffNode(
        key: keyStr,
        path: keyPath,
        type: _DiffType.removed,
        oldValue: oldVal,
        children: complex
            ? _computeDiff(oldVal, oldVal is List ? const [] : const {}, keyPath)
            : null,
      ));
    } else if (!_isEqual(oldVal, newVal)) {
      final complex =
          _isObject(oldVal) || _isObject(newVal) || oldVal is List || newVal is List;
      result.add(_DiffNode(
        key: keyStr,
        path: keyPath,
        type: _DiffType.changed,
        oldValue: oldVal,
        newValue: newVal,
        children: complex ? _computeDiff(oldVal, newVal, keyPath) : null,
      ));
    } else {
      final complex = oldVal is List || _isObject(oldVal);
      result.add(_DiffNode(
        key: keyStr,
        path: keyPath,
        type: _DiffType.unchanged,
        oldValue: oldVal,
        newValue: newVal,
        children: complex ? _computeDiff(oldVal, newVal, keyPath) : null,
      ));
    }
  }
  return result;
}

String _stringifyValue(Object? value, {bool compact = true}) {
  if (value == null) return 'null';
  if (value is String) {
    if (compact && value.length > 30) return '"${value.substring(0, 27)}..."';
    return '"$value"';
  }
  if (value is num) return value.toString();
  if (value is bool) return value.toString();
  if (value is List) {
    if (compact) {
      final count = value.length;
      return count == 0 ? '[ ]' : '[ $count item${count != 1 ? "s" : ""} ]';
    }
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  if (value is Map) {
    if (compact) {
      final keys = value.length;
      return keys == 0 ? '{ }' : '{ $keys key${keys != 1 ? "s" : ""} }';
    }
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  return '$value';
}

/// Tree diff between two values. `theme` is dark-only here (the state tools only
/// use the dark variant); a light theme is a follow-up if ever needed.
class TreeDiffViewer extends StatefulWidget {
  const TreeDiffViewer({
    super.key,
    required this.oldValue,
    required this.newValue,
    this.expandAll = false,
    this.showUnchanged = true,
  });

  final Object? oldValue;
  final Object? newValue;
  final bool expandAll;
  final bool showUnchanged;

  @override
  State<TreeDiffViewer> createState() => _TreeDiffViewerState();
}

class _TreeDiffViewerState extends State<TreeDiffViewer> {
  late Set<String> _expandedPaths;
  late List<_DiffNode> _diffTree;
  int _lineCounter = 0;

  @override
  void initState() {
    super.initState();
    _rebuild(initExpand: true);
  }

  @override
  void didUpdateWidget(TreeDiffViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = _signature();
    _diffTree = _computeDiff(widget.oldValue, widget.newValue);
    // Re-seed first-level expansion only when the structural signature changed
    // (RN keys the effect off `comparisonSignature`, not the tree identity).
    if (before != _signature()) {
      _expandedPaths = _firstLevelExpanded();
    }
  }

  void _rebuild({bool initExpand = false}) {
    _diffTree = _computeDiff(widget.oldValue, widget.newValue);
    if (initExpand) _expandedPaths = _firstLevelExpanded();
  }

  String _signature() => _diffTree
      .map((n) => '${n.path.join(".")}:${n.type}')
      .join('|');

  Set<String> _firstLevelExpanded() {
    final set = <String>{};
    for (final node in _diffTree) {
      if (node.children != null && node.children!.isNotEmpty) {
        set.add(node.path.join('.'));
      }
    }
    return set;
  }

  void _toggle(List<String> path) {
    final key = path.join('.');
    setState(() {
      if (!_expandedPaths.remove(key)) _expandedPaths.add(key);
    });
  }

  ({int added, int removed, int changed}) _countChanges(List<_DiffNode> nodes) {
    var added = 0, removed = 0, changed = 0;
    void count(List<_DiffNode> list) {
      for (final node in list) {
        if (node.type == _DiffType.added) {
          added++;
        } else if (node.type == _DiffType.removed) {
          removed++;
        } else if (node.type == _DiffType.changed) {
          changed++;
        }
        if (node.children != null) count(node.children!);
      }
    }

    count(nodes);
    return (added: added, removed: removed, changed: changed);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _countChanges(_diffTree);
    final hasChanges =
        stats.added > 0 || stats.removed > 0 || stats.changed > 0;

    _lineCounter = 0;
    final rows = <Widget>[];
    for (final node in _diffTree) {
      _renderNode(node, 0, rows);
    }

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: GameUIDiffColors.lineNumberBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: GameUIDiffColors.lineNumberBorder),
                ),
              ),
              child: Row(
                children: [
                  if (stats.added > 0)
                    _summaryItem('+', stats.added, 'new',
                        GameUIDiffColors.addedText, GameUIDiffColors.addedBackground),
                  if (stats.removed > 0) ...[
                    if (stats.added > 0) const SizedBox(width: 16),
                    _summaryItem('−', stats.removed, 'gone',
                        GameUIDiffColors.removedText, GameUIDiffColors.removedBackground),
                  ],
                  if (stats.changed > 0) ...[
                    if (stats.added > 0 || stats.removed > 0)
                      const SizedBox(width: 16),
                    _summaryItem('≈', stats.changed, 'modified',
                        GameUIDiffColors.modifiedText, GameUIDiffColors.modifiedBackground),
                  ],
                ],
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              child: _diffTree.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        children: [
                          Text('≡',
                              style: TextStyle(
                                  fontSize: 48,
                                  fontFamily: 'monospace',
                                  color: GameUIDiffColors.unchangedText
                                      .withValues(alpha: 0.2))),
                          const Padding(
                            padding: EdgeInsets.only(top: 12, bottom: 4),
                            child: Text('No changes detected',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    color: GameUIDiffColors.unchangedText)),
                          ),
                          Text('The data is identical',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: GameUIDiffColors.lineNumberText)),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String icon, int count, String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: color)),
          const SizedBox(width: 4),
          Text('$count',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: color.withValues(alpha: 0.9))),
        ],
      ),
    );
  }

  void _renderNode(_DiffNode node, int depth, List<Widget> out) {
    if (!widget.showUnchanged && node.type == _DiffType.unchanged) return;

    _lineCounter++;
    final currentLine = _lineCounter;
    final indent = depth * 20.0;
    final isExpanded =
        widget.expandAll || _expandedPaths.contains(node.path.join('.'));
    final hasChildren = node.children != null && node.children!.isNotEmpty;

    Color rowBg() => switch (node.type) {
          _DiffType.added => GameUIDiffColors.addedBackground,
          _DiffType.removed => GameUIDiffColors.removedBackground,
          _DiffType.changed => GameUIDiffColors.modifiedBackground,
          _DiffType.unchanged => const Color(0x00000000),
        };

    String marker() => switch (node.type) {
          _DiffType.added => '+',
          _DiffType.removed => '−',
          _DiffType.changed => '≈',
          _DiffType.unchanged => ' ',
        };

    ({Color bg, Color color}) markerStyle() => switch (node.type) {
          _DiffType.added => (
              bg: GameUIDiffColors.markerAddedBackground,
              color: GameUIDiffColors.addedText,
            ),
          _DiffType.removed => (
              bg: GameUIDiffColors.markerRemovedBackground,
              color: GameUIDiffColors.removedText,
            ),
          _DiffType.changed => (
              bg: GameUIDiffColors.markerModifiedBackground,
              color: GameUIDiffColors.modifiedText,
            ),
          _DiffType.unchanged => (
              bg: const Color(0x00000000),
              color: GameUIDiffColors.markerText,
            ),
        };

    final ms = markerStyle();

    final row = Container(
      constraints: const BoxConstraints(minHeight: 26),
      decoration: BoxDecoration(
        color: rowBg(),
        border: const Border(
          bottom: BorderSide(color: Color(0x05FFFFFF), width: 0.5),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              alignment: Alignment.centerRight,
              decoration: const BoxDecoration(
                color: GameUIDiffColors.lineNumberBackground,
                border: Border(
                  right: BorderSide(color: GameUIDiffColors.lineNumberBorder),
                ),
              ),
              child: Text('$currentLine'.padLeft(2, ' '),
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: GameUIDiffColors.lineNumberText)),
            ),
            Container(
              width: 20,
              color: ms.bg,
              alignment: Alignment.center,
              child: Text(marker(),
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: ms.color)),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    left: 12 + indent, right: 12, top: 4, bottom: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasChildren)
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(right: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: GameUIDiffColors.lineNumberBorder,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(isExpanded ? '−' : '+',
                            style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                color: GameUIDiffColors.lineNumberText)),
                      ),
                    Text(node.key,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                            color: GameUIDiffColors.modifiedText
                                .withValues(alpha: 0.9))),
                    const Text(' : ',
                        style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: GameUIDiffColors.lineNumberText)),
                    ..._valueSpans(node, hasChildren, isExpanded),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    out.add(hasChildren
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggle(node.path),
            child: row,
          )
        : row);

    if (hasChildren && isExpanded) {
      for (final child in node.children!) {
        _renderNode(child, depth + 1, out);
      }
    }
  }

  List<Widget> _valueSpans(_DiffNode node, bool hasChildren, bool isExpanded) {
    // When expanded with children, RN renders no inline value.
    if (hasChildren && isExpanded) return const [];

    Widget added(Object? v) => _valueChip(
        _stringifyValue(v), GameUIDiffColors.addedText,
        GameUIDiffColors.addedWordHighlight);
    Widget removed(Object? v) => _valueChip(
        _stringifyValue(v), GameUIDiffColors.removedText,
        GameUIDiffColors.removedWordHighlight,
        strike: true);

    switch (node.type) {
      case _DiffType.changed:
        return [
          removed(node.oldValue),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(' => ',
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: GameUIDiffColors.modifiedText)),
          ),
          added(node.newValue),
        ];
      case _DiffType.added:
        return [added(node.newValue)];
      case _DiffType.removed:
        return [removed(node.oldValue)];
      case _DiffType.unchanged:
        return [
          Text(_stringifyValue(node.oldValue),
              style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: GameUIDiffColors.unchangedText)),
        ];
    }
  }

  Widget _valueChip(String text, Color color, Color bg, {bool strike = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(text,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: color,
            decoration: strike ? TextDecoration.lineThrough : null,
            decorationColor: color,
          )),
    );
  }
}
