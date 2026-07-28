import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import '../macos_colors.dart';
import 'copy_button.dart';

/// Port of shared-ui's DataViewer (DataViewer.tsx + VirtualizedDataExplorer
/// + TypeLegend) in the configuration the network tool uses everywhere:
/// `rawMode` + `initialExpanded` + optional type-filter legend.
///
/// VS Code-style tree: 24px rows, 16px indent with guide lines, chevron
/// expanders, `key:` in white monospace, values colored by type, expandable
/// rows summarized as "object (3 items)", a per-row copy button, and tap-a-
/// type-chip-to-filter (flattens matching values to `path: value` rows).
///
/// Deviations: no FlatList virtualization (bodies are capped at 500 rows per
/// level like RN; the modal's outer scroll view owns scrolling), no
/// incremental-expand diffing (Flutter rebuilds are cheap at this scale).
class DataViewer extends StatefulWidget {
  const DataViewer({
    super.key,
    required this.data,
    this.showTypeFilter = true,
    this.initialExpanded = false,
  });

  final Object? data;
  final bool showTypeFilter;
  final bool initialExpanded;

  @override
  State<DataViewer> createState() => _DataViewerState();
}

const _itemHeight = 24.0;
const _indentWidth = 16.0;
const _maxItemsPerLevel = 500;
const _maxDepth = 10;

String _valueTypeOf(Object? value) {
  if (value == null) return 'null';
  if (value is String) return 'string';
  if (value is bool) return 'boolean';
  if (value is num) return 'number';
  if (value is List) return 'array';
  if (value is Map) return 'object';
  return 'object';
}

Color _typeColor(String type) => switch (type) {
  'string' => MacOSColors.typeString,
  'number' => MacOSColors.typeNumber,
  'boolean' => MacOSColors.typeBoolean,
  'null' => MacOSColors.typeNull,
  'undefined' => MacOSColors.typeUndefined,
  'function' => MacOSColors.typeFunction,
  'array' => MacOSColors.typeArray,
  'object' => MacOSColors.typeObject,
  _ => MacOSColors.textSecondary,
};

String _formatLeafValue(Object? value, String type) => switch (type) {
  'string' => '"$value"',
  'boolean' => value == true ? 'true' : 'false',
  'null' => 'null',
  _ => '$value',
};

class _FlatItem {
  _FlatItem({
    required this.id,
    required this.key,
    required this.value,
    required this.valueType,
    required this.depth,
    required this.isExpandable,
    required this.isExpanded,
    required this.childCount,
  });

  final String id;
  final String key;
  final Object? value;
  final String valueType;
  final int depth;
  final bool isExpandable;
  final bool isExpanded;
  final int childCount;
}

class _DataViewerState extends State<DataViewer> {
  late final Set<String> _expanded = _initialExpanded();
  String? _activeFilter;

  Set<String> _initialExpanded() {
    final initial = <String>{'root'};
    final data = widget.data;
    if (widget.initialExpanded && data != null) {
      if (data is List) {
        for (var i = 0; i < data.length; i++) {
          initial.add('root.$i');
        }
      } else if (data is Map) {
        for (final key in data.keys) {
          initial.add('root.$key');
        }
      }
    }
    return initial;
  }

  List<_FlatItem> _flatten(
    Object? value,
    String key,
    int depth,
    List<String> path,
  ) {
    if (depth > _maxDepth) return const [];
    final currentPath = [...path, key];
    final id = currentPath.join('.');
    final valueType = _valueTypeOf(value);
    final isExpandable = valueType == 'object' || valueType == 'array';
    final childCount = isExpandable
        ? (value is List
              ? value.length
              : (value as Map).length)
        : 0;
    final item = _FlatItem(
      id: id,
      key: key,
      value: value,
      valueType: valueType,
      depth: depth,
      isExpandable: isExpandable && childCount > 0,
      isExpanded: _expanded.contains(id),
      childCount: childCount,
    );
    final result = [item];
    if (item.isExpandable && item.isExpanded) {
      final entries = value is List
          ? [for (var i = 0; i < value.length; i++) ('$i', value[i])]
          : [
              for (final e in (value as Map).entries) ('${e.key}', e.value),
            ];
      for (final (childKey, childValue)
          in entries.take(_maxItemsPerLevel)) {
        result.addAll(_flatten(childValue, childKey, depth + 1, currentPath));
      }
    }
    return result;
  }

  /// TypeLegend filter: flatten matching values as `path: value` rows
  /// (DataViewer.tsx getFilteredData).
  Map<String, Object?> _filteredByType(String targetType) {
    final filtered = <String, Object?>{};
    var count = 0;
    void walk(Object? obj, String path, int depth) {
      if (depth > 10 || count > 100) return;
      if (obj is List) {
        for (var i = 0; i < obj.length; i++) {
          final item = obj[i];
          final currentPath = path.isEmpty ? '[$i]' : '$path[$i]';
          if (_valueTypeOf(item) == targetType) {
            filtered[currentPath] = item;
            count++;
          }
          if (item is Map || item is List) walk(item, currentPath, depth + 1);
        }
      } else if (obj is Map) {
        for (final entry in obj.entries) {
          final currentPath =
              path.isEmpty ? '${entry.key}' : '$path.${entry.key}';
          if (_valueTypeOf(entry.value) == targetType) {
            filtered[currentPath] = entry.value;
            count++;
          }
          if (entry.value is Map || entry.value is List) {
            walk(entry.value, currentPath, depth + 1);
          }
        }
      }
    }

    walk(widget.data, '', 0);
    return filtered;
  }

  List<String> _visibleTypes() {
    final types = <String>{};
    void walk(Object? value, int depth) {
      if (depth > 3 || types.length >= 8) return;
      types.add(_valueTypeOf(value));
      if (value is Map) {
        for (final v in value.values) {
          walk(v, depth + 1);
        }
      } else if (value is List) {
        for (final v in value) {
          walk(v, depth + 1);
        }
      }
    }

    walk(widget.data, 0);
    return types.toList();
  }

  bool get _hasData {
    final data = widget.data;
    if (data == null) return false;
    if (data is String) return data.isNotEmpty;
    if (data is num || data is bool) return true;
    if (data is List) return data.isNotEmpty;
    if (data is Map) return data.isNotEmpty;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(fontSize: 12, color: MacOSColors.textSecondary),
          ),
        ),
      );
    }

    final activeFilter = _activeFilter;
    final rootData =
        activeFilter != null ? _filteredByType(activeFilter) : widget.data;
    // Filtered view starts fully collapsed except root (flat path rows).
    final items = _flatten(rootData, 'root', 0, const []);
    // Root row itself isn't rendered in raw mode's visual result: RN renders
    // it (key "root"), so keep it for parity.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTypeFilter)
          _TypeLegend(
            types: _visibleTypes(),
            activeFilter: _activeFilter,
            onFilterChange: (type) => setState(() => _activeFilter = type),
          ),
        for (final item in items)
          _TreeRow(
            item: item,
            onToggle: item.isExpandable
                ? () => setState(() {
                    if (!_expanded.remove(item.id)) _expanded.add(item.id);
                  })
                : null,
          ),
      ],
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({required this.item, this.onToggle});

  final _FlatItem item;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(item.valueType);
    final row = Container(
      constraints: const BoxConstraints(minHeight: _itemHeight),
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indent guides: one 1px line per ancestor depth (VS Code style).
          SizedBox(
            width: item.depth * _indentWidth,
            height: _itemHeight,
            child: CustomPaint(painter: _IndentGuidePainter(item.depth)),
          ),
          SizedBox(
            width: 16,
            height: _itemHeight,
            child: item.isExpandable
                ? BuoyGlyph(
                    item.isExpanded
                        ? BuoyIcons.chevronDown
                        : BuoyIcons.chevronRight,
                    size: 14,
                    color: MacOSColors.textSecondary,
                  )
                : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 2, top: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${item.key}: ',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (item.isExpandable || item.childCount > 0)
                      TextSpan(
                        text:
                            '${item.valueType} (${item.childCount} ${item.childCount == 1 ? "item" : "items"})',
                        style: const TextStyle(
                          color: MacOSColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      )
                    else if (item.valueType == 'object' ||
                        item.valueType == 'array')
                      TextSpan(
                        text: '${item.valueType} (0 items)',
                        style: const TextStyle(
                          color: MacOSColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      )
                    else
                      TextSpan(
                        text: _formatLeafValue(item.value, item.valueType),
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CopyButton(value: item.value, size: 14),
          ),
        ],
      ),
    );
    if (onToggle == null) return row;
    return TouchableOpacity(activeOpacity: 0.7, onTap: onToggle, child: row);
  }
}

class _IndentGuidePainter extends CustomPainter {
  _IndentGuidePainter(this.depth);
  final int depth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MacOSColors.textPrimary.hexAlpha(0x14)
      ..strokeWidth = 1;
    for (var i = 0; i < depth; i++) {
      final x = i * _indentWidth + 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_IndentGuidePainter oldDelegate) =>
      oldDelegate.depth != depth;
}

/// TypeLegend.tsx — tappable type chips that filter the tree by value type.
class _TypeLegend extends StatelessWidget {
  const _TypeLegend({
    required this.types,
    required this.activeFilter,
    required this.onFilterChange,
  });

  final List<String> types;
  final String? activeFilter;
  final ValueChanged<String?> onFilterChange;

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final type in types)
            _typeChip(type, activeFilter == type),
        ],
      ),
    );
  }

  Widget _typeChip(String type, bool isActive) {
    final color = _typeColor(type);
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: () => onFilterChange(isActive ? null : type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? MacOSColors.backgroundInput
              : MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color : MacOSColors.textPrimary.hexAlpha(0x1A),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Text(
              type,
              style: TextStyle(
                color: isActive ? color : MacOSColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
