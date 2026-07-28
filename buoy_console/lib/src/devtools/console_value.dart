/// Ports packages/console/src/devtools/ConsoleValue.tsx.
///
/// Approximation of DevTools' object/value rendering. Primitives render with the
/// dark-theme `object-value-*` token colors. Maps/Lists render an italic
/// one-line preview with an expand triangle; expanding reveals a property tree
/// (lazy, recursive). Dart values arrive already sanitized on the wire, but the
/// local capture path can carry real Maps/Lists (from %o/%O), so both are
/// handled. Dart has no bigint/symbol/undefined — those RN kinds are dropped.
library;

import 'package:flutter/widgets.dart';

import 'console_theme.dart';

const int _maxPreviewProperties = 5;
const int _maxPreviewArray = 6;

enum _ValueKind { number, boolean, string, nul, function, array, object }

_ValueKind _kindOf(Object? value) {
  if (value == null) return _ValueKind.nul;
  if (value is List) return _ValueKind.array;
  if (value is Map) return _ValueKind.object;
  if (value is num) return _ValueKind.number;
  if (value is bool) return _ValueKind.boolean;
  if (value is String) return _ValueKind.string;
  if (value is Function) return _ValueKind.function;
  return _ValueKind.object;
}

const Map<_ValueKind, Color> _kindColor = {
  _ValueKind.number: ConsoleTheme.valueNumber,
  _ValueKind.boolean: ConsoleTheme.valueNumber,
  _ValueKind.string: ConsoleTheme.valueString,
  _ValueKind.nul: ConsoleTheme.valueNullish,
  _ValueKind.function: ConsoleTheme.valueNode,
};

/// One-line scalar text for a value (used inside previews).
String _scalarText(Object? value) {
  switch (_kindOf(value)) {
    case _ValueKind.string:
      return "'$value'";
    case _ValueKind.function:
      return 'ƒ ';
    case _ValueKind.array:
      return 'Array(${(value as List).length})';
    case _ValueKind.object:
      return '{…}';
    case _ValueKind.nul:
      return 'null';
    default:
      return value.toString();
  }
}

/// Build the collapsed italic preview string for a Map/List.
String _buildPreview(Object value) {
  if (value is List) {
    final head =
        value.take(_maxPreviewArray).map(_scalarText).join(', ');
    final more = value.length > _maxPreviewArray ? ', …' : '';
    return '(${value.length}) [$head$more]';
  }
  final map = value as Map;
  final entries = map.entries.toList();
  final head = entries
      .take(_maxPreviewProperties)
      .map((e) => '${e.key}: ${_scalarText(e.value)}')
      .join(', ');
  final more = entries.length > _maxPreviewProperties ? ', …' : '';
  return '{$head$more}';
}

bool _isExpandable(Object? value) {
  if (value is List) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return false;
}

const TextStyle _mono = TextStyle(
  fontFamily: monoFont,
  fontSize: 12,
  height: 16 / 12,
);

/// Render a single console argument / property value.
class ConsoleValue extends StatefulWidget {
  const ConsoleValue({super.key, required this.value, this.depth = 0});

  final Object? value;
  final int depth;

  @override
  State<ConsoleValue> createState() => _ConsoleValueState();
}

class _ConsoleValueState extends State<ConsoleValue> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final value = widget.value;

    if (!_isExpandable(value)) {
      final color = _kindColor[_kindOf(value)] ?? ConsoleTheme.onSurface;
      return Text(_scalarText(value), style: _mono.copyWith(color: color));
    }

    final entries = value is List
        ? [
            for (var i = 0; i < value.length; i++)
              MapEntry<String, Object?>('$i', value[i]),
          ]
        : (value as Map)
            .entries
            .map((e) => MapEntry<String, Object?>('${e.key}', e.value))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Triangle(open: _expanded),
              Flexible(
                child: Text(
                  _buildPreview(value as Object),
                  maxLines: _expanded ? null : 1,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: _mono.copyWith(
                    color: ConsoleTheme.valuePreview,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_expanded && widget.depth < 6)
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in entries)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '${e.key}:',
                          style: _mono.copyWith(color: ConsoleTheme.valueNode),
                        ),
                      ),
                      Flexible(
                        child: ConsoleValue(
                          value: e.value,
                          depth: widget.depth + 1,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Triangle extends StatelessWidget {
  const _Triangle({required this.open});
  final bool open;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      child: Transform.rotate(
        angle: open ? 1.5707963267948966 : 0,
        child: const Text(
          '▶',
          style: TextStyle(
            color: ConsoleTheme.tokenSubtle,
            fontSize: 8,
            height: 16 / 8,
          ),
        ),
      ),
    );
  }
}
