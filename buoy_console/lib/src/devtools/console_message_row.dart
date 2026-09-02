/// Ports packages/console/src/devtools/ConsoleMessageRow.tsx.
///
/// A single DevTools `.console-message-wrapper`:
///   [origin gutter] [nesting markers] [group triangle] [level icon]
///   [timestamp] [stack triangle] [content] [repeat badge] [origin label]
/// Error/warning rows get the surface background + text colors; other rows get a
/// hairline top divider. Group headers show a bold title with an expand
/// triangle; error/warn/trace rows can expand a captured stack trace.
library;

import 'package:flutter/widgets.dart';

import 'console_format.dart';
import 'console_theme.dart';
import 'console_messages.dart';
import 'console_value.dart';

String _formatTimestamp(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  String pad(int n, [int len = 2]) => n.toString().padLeft(len, '0');
  return '${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}.${pad(d.millisecond, 3)}';
}

const TextStyle _textStyle = TextStyle(
  fontFamily: monoFont,
  fontSize: 12,
  height: 16 / 12,
);

class ConsoleMessageRow extends StatefulWidget {
  const ConsoleMessageRow({
    super.key,
    required this.row,
    required this.showTimestamps,
    required this.onToggleGroup,
    required this.onToggleCluster,
  });

  final DisplayRow row;
  final bool showTimestamps;
  final void Function(int groupId, bool currentlyCollapsed) onToggleGroup;
  final void Function(String key) onToggleCluster;

  @override
  State<ConsoleMessageRow> createState() => _ConsoleMessageRowState();
}

class _ConsoleMessageRowState extends State<ConsoleMessageRow> {
  /// RN `expanded`: EVERY row is tap-to-expand. Collapsed, the content wraps
  /// clamp to one 16pt line (long objects and multi-line strings no longer
  /// blow the list open); expanded shows everything and, for rows that have
  /// one, the stack. Trace rows start expanded, as before.
  late bool _expanded = widget.row.entry.method == 'trace';

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final entry = row.entry;
    final level = levelStyles[entry.level] ?? levelStyles['info']!;
    final isErrorOrWarn = entry.level == 'error' || entry.level == 'warning';
    final textColor = level.text;

    // Collapsed/large cluster header (Grouped mode).
    if (row.clusterHeader != null) {
      final ch = row.clusterHeader!;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onToggleCluster(ch.key),
        child: _wrapper(
          dividerTop: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _originGutter(ch.expanded ? '▼' : '▶', row.originColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: [
                      Text(
                        row.originLabel ?? '',
                        style: _textStyle.copyWith(
                          color: row.originColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        ' · ${ch.count} logs',
                        style: _textStyle.copyWith(
                          color: ConsoleTheme.tokenSubtle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final tokens = formatConsoleMessage(entry.args);
    final hasStack = (entry.stack != null && entry.stack!.isNotEmpty) &&
        (isErrorOrWarn || entry.method == 'trace');

    final metaAndContent = <Widget>[
      if (row.isGroupHeader)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            row.groupCollapsed == true ? '▶' : '▼',
            style: TextStyle(fontSize: 9, height: 16 / 9, color: textColor),
          ),
        ),
      if (level.icon != null)
        Padding(
          padding: const EdgeInsets.only(right: 5),
          child: Text(
            level.icon == 'warning' ? '⚠' : '⊘',
            style: TextStyle(fontSize: 12, height: 16 / 12, color: textColor),
          ),
        ),
      if (widget.showTimestamps)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
            _formatTimestamp(entry.timestamp),
            style: const TextStyle(
              fontFamily: monoFont,
              fontSize: 11,
              height: 16 / 11,
              color: ConsoleTheme.tokenSubtle,
            ),
          ),
        ),
      if (hasStack)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            _expanded ? '▼' : '▶',
            style: TextStyle(fontSize: 8, height: 16 / 8, color: textColor),
          ),
        ),
      // Content tokens.
      for (final token in tokens)
        token is StringToken
            ? Text(
                token.value,
                style: _textStyle
                    .copyWith(
                      color: textColor,
                      fontWeight: row.isGroupHeader ? FontWeight.bold : null,
                    )
                    .merge(token.style),
              )
            : ConsoleValue(value: (token as ValueToken).value),
      if (row.repeatCount > 1)
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 1),
          child: _RepeatBadge(count: row.repeatCount, color: textColor),
        ),
      if (row.originLabel != null)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Opacity(
            opacity: 0.9,
            child: Text(
              row.originLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: monoFont,
                fontSize: 10,
                height: 16 / 10,
                color: row.originColor,
              ),
            ),
          ),
        ),
    ];

    final wrap = Wrap(
      crossAxisAlignment: WrapCrossAlignment.start,
      children: metaAndContent,
    );
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // RN contentWrapClamped: nowrap + hidden + maxHeight 16 while collapsed.
        _expanded
            ? wrap
            : ClipRect(
                child: SizedBox(
                  height: 16,
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxHeight: double.infinity,
                    child: wrap,
                  ),
                ),
              ),
        if (hasStack && _expanded)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in (entry.stack ?? '')
                    .split('\n')
                    .where((l) => l.trim().isNotEmpty))
                  Text(
                    line.trim(),
                    style: const TextStyle(
                      fontFamily: monoFont,
                      fontSize: 11,
                      height: 15 / 11,
                      color: ConsoleTheme.tokenSubtle,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    // Nesting indentation markers.
    final markers = [
      for (var i = 0; i < row.depth; i++)
        Container(
          width: 14,
          margin: const EdgeInsets.only(left: 2),
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: ConsoleTheme.divider, width: 0.5),
            ),
          ),
        ),
    ];

    // Origin gutter: swimlane columns or a single bracket.
    Widget? gutter;
    if (row.lanes != null) {
      gutter = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final cell in row.lanes!)
            SizedBox(
              width: 9,
              child: Text(
                cell.glyph,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: monoFont,
                  fontSize: 13,
                  height: 18 / 13,
                  color: cell.color,
                ),
              ),
            ),
        ],
      );
    } else if (row.bracketGlyph != null) {
      gutter = _originGutter(row.bracketGlyph!, row.originColor);
    }

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?gutter,
        ...markers,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: inner,
          ),
        ),
      ],
    );

    final content = _wrapper(
      background: level.background,
      dividerTop: level.background == null,
      child: body,
    );

    if (row.isGroupHeader && row.groupId != null) {
      final gid = row.groupId!;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onToggleGroup(gid, row.groupCollapsed == true),
        child: content,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: content,
    );
  }

  Widget _originGutter(String glyph, Color? color) => SizedBox(
        width: 11,
        child: Text(
          glyph,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: monoFont,
            fontSize: 13,
            height: 18 / 13,
            color: color,
          ),
        ),
      );

  Widget _wrapper({
    required Widget child,
    Color? background,
    bool dividerTop = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 18),
      padding: const EdgeInsets.only(top: 2, bottom: 2, right: 8),
      decoration: BoxDecoration(
        color: background,
        border: dividerTop
            ? const Border(
                top: BorderSide(color: ConsoleTheme.divider, width: 0.5),
              )
            : null,
      ),
      child: child,
    );
  }
}

class _RepeatBadge extends StatelessWidget {
  const _RepeatBadge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          height: 14 / 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
