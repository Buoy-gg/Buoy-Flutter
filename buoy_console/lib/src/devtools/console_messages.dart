/// Ports packages/console/src/devtools/useConsoleMessages.ts.
///
/// Derives the displayed row model from raw captured entries, mirroring DevTools
/// `ConsoleView.updateMessageList`: level + text filtering, consecutive-identical
/// collapse into a repeat-count badge (when timestamps are off), and
/// console.group / groupCollapsed nesting. Also computes per-origin source keys,
/// colors, labels, and the lnav bracket / swimlane / cluster gutters.
///
/// This is pure logic (no widgets) so it can be unit-tested against RN-derived
/// expectations, matching the storage tool's pure-logic port style.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../console_log_store.dart';
import 'console_filter.dart';
import 'console_origin.dart';

/// How the origin gutter is laid out.
enum LayoutMode { chrono, swimlane, cluster }

/// One swimlane gutter cell.
class LaneCell {
  const LaneCell({required this.glyph, this.color});
  final String glyph;
  final Color? color;
}

/// A synthetic collapsed/large-cluster header (Grouped mode).
class ClusterHeader {
  const ClusterHeader({
    required this.key,
    required this.count,
    required this.expanded,
  });
  final String key;
  final int count;
  final bool expanded;
}

/// One display row.
class DisplayRow {
  DisplayRow({
    required this.key,
    required this.entry,
    required this.depth,
    required this.repeatCount,
    required this.isGroupHeader,
    this.groupId,
    this.groupCollapsed,
    this.sourceKey,
    this.bracketGlyph,
    this.lanes,
    this.originColor,
    this.originLabel,
    this.clusterHeader,
  });

  final String key;
  final ConsoleLogEntry entry;
  int depth;
  int repeatCount;
  final bool isGroupHeader;
  final int? groupId;
  bool? groupCollapsed;
  String? sourceKey;
  String? bracketGlyph;
  List<LaneCell>? lanes;
  Color? originColor;
  String? originLabel;
  ClusterHeader? clusterHeader;
}

class ConsoleMessagesResult {
  const ConsoleMessagesResult({
    required this.rows,
    required this.hiddenCount,
    required this.levelCounts,
    required this.totalCount,
  });
  final List<DisplayRow> rows;
  final int hiddenCount;
  final Map<String, int> levelCounts;
  final int totalCount;
}

class BuildOptions {
  const BuildOptions({
    required this.levelsMask,
    required this.query,
    required this.showTimestamps,
    required this.collapsedOverrides,
    required this.groupDimension,
    required this.layoutMode,
    required this.clusterExpanded,
  });
  final LevelsMask levelsMask;
  final String query;
  final bool showTimestamps;

  /// groupId → user-overridden collapsed state.
  final Map<int, bool> collapsedOverrides;
  final GroupDimension groupDimension;
  final LayoutMode layoutMode;

  /// Grouped mode: which large clusters the user has expanded (key → true).
  final Map<String, bool> clusterExpanded;
}

const int _maxLanes = 5;

/// Grouped mode collapses any source cluster larger than this into a header.
const int _clusterThreshold = 5;

const Set<String> _groupStarts = {'group', 'groupCollapsed'};

/// First pass: tag each row with its origin source key, color, and label.
void _computeSourceInfo(List<DisplayRow> rows, GroupDimension dim) {
  for (final row in rows) {
    final key = sourceKey(row.entry.origin, dim);
    row.sourceKey = key;
    row.originColor = key != null ? colorForKey(key) : null;
    row.originLabel =
        dim == GroupDimension.off ? null : sourceLabel(row.entry.origin, dim);
  }
}

/// lnav single-column gutter: bracket consecutive same-source runs.
void _attachContiguousBrackets(List<DisplayRow> rows) {
  for (var i = 0; i < rows.length; i++) {
    final key = rows[i].sourceKey;
    if (key == null) {
      rows[i].bracketGlyph = null;
      continue;
    }
    final sameAsPrev = i > 0 && rows[i - 1].sourceKey == key;
    final sameAsNext = i < rows.length - 1 && rows[i + 1].sourceKey == key;
    final bracket = !sameAsPrev && !sameAsNext
        ? Bracket.single
        : !sameAsPrev
            ? Bracket.top
            : !sameAsNext
                ? Bracket.bottom
                : Bracket.mid;
    rows[i].bracketGlyph = bracketGlyph(bracket);
  }
}

/// Re-order rows so all rows of one source are contiguous (groups by first
/// appearance, chronological within each). Clusters larger than
/// _clusterThreshold collapse into a single expandable header, unless expanded.
List<DisplayRow> _clusterRows(
  List<DisplayRow> rows,
  Map<String, bool> expanded,
) {
  final order = <String>[];
  final groups = <String, List<DisplayRow>>{};
  for (final r in rows) {
    final k = r.sourceKey ?? '—';
    final g = groups.putIfAbsent(k, () {
      order.add(k);
      return <DisplayRow>[];
    });
    g.add(r);
  }

  final out = <DisplayRow>[];
  for (final k in order) {
    final group = groups[k]!;
    for (final r in group) {
      r.depth = 0; // clustering ignores console.group nesting
    }

    final isLarge = group.length > _clusterThreshold;
    final isExpanded = expanded[k] ?? false;

    if (isLarge) {
      out.add(DisplayRow(
        key: 'cluster:$k',
        entry: group.first.entry,
        depth: 0,
        repeatCount: 1,
        isGroupHeader: false,
        sourceKey: k,
        originColor: group.first.originColor,
        originLabel: group.first.originLabel,
        clusterHeader:
            ClusterHeader(key: k, count: group.length, expanded: isExpanded),
      ));
      if (!isExpanded) continue;
    }

    for (var i = 0; i < group.length; i++) {
      final r = group[i];
      final single = group.length == 1;
      final bracket = single
          ? Bracket.single
          : i == 0
              ? Bracket.top
              : i == group.length - 1
                  ? Bracket.bottom
                  : Bracket.mid;
      r.bracketGlyph = bracketGlyph(bracket);
      out.add(r);
    }
  }
  return out;
}

/// Git-graph swimlanes: each source gets a continuous vertical track.
void _attachSwimlanes(List<DisplayRow> rows) {
  final first = <String, int>{};
  final last = <String, int>{};
  for (var i = 0; i < rows.length; i++) {
    final k = rows[i].sourceKey;
    if (k == null) continue;
    first.putIfAbsent(k, () => i);
    last[k] = i;
  }

  final sources = first.keys.toList()
    ..sort((a, b) => first[a]!.compareTo(first[b]!));
  final laneOf = <String, int>{};
  final laneEnd = <int>[];
  for (final s in sources) {
    var lane = laneEnd.indexWhere((end) => end < first[s]!);
    if (lane == -1) {
      lane = laneEnd.length < _maxLanes ? laneEnd.length : _maxLanes - 1;
      if (lane >= laneEnd.length) laneEnd.add(0);
    }
    laneOf[s] = lane;
    laneEnd[lane] = math.max(laneEnd[lane], last[s]!);
  }
  final laneCount = laneEnd.isEmpty ? 1 : laneEnd.length.clamp(1, _maxLanes);

  for (var i = 0; i < rows.length; i++) {
    final cells =
        List<LaneCell>.generate(laneCount, (_) => const LaneCell(glyph: ' '));
    for (final s in sources) {
      final lane = laneOf[s]!;
      if (lane >= laneCount) continue;
      if (i >= first[s]! && i <= last[s]!) {
        cells[lane] = LaneCell(
          glyph: rows[i].sourceKey == s ? '●' : '│',
          color: colorForKey(s),
        );
      }
    }
    rows[i].lanes = cells;
  }
}

class _OpenGroup {
  _OpenGroup(this.id, this.collapsed);
  final int id;
  final bool collapsed;
}

/// Build the display rows for [entries] (chronological) under [opts].
ConsoleMessagesResult buildDisplayRows(
  List<ConsoleLogEntry> entries,
  BuildOptions opts,
) {
  final parsed = parseFilterQuery(opts.query.trim());

  final rows = <DisplayRow>[];
  final levelCounts = <String, int>{
    'verbose': 0,
    'info': 0,
    'warning': 0,
    'error': 0,
  };
  var hiddenCount = 0;
  final stack = <_OpenGroup>[];

  bool anyAncestorCollapsed() => stack.any((g) => g.collapsed);

  for (final entry in entries) {
    levelCounts[entry.level] = (levelCounts[entry.level] ?? 0) + 1;

    if (entry.method == 'groupEnd') {
      if (stack.isNotEmpty) stack.removeLast();
      continue;
    }

    final isHeader = _groupStarts.contains(entry.method);
    final hiddenByGroup = anyAncestorCollapsed();
    final passesFilter = shouldBeVisible(entry, opts.levelsMask, parsed);

    if (!passesFilter) {
      hiddenCount++;
    } else if (!hiddenByGroup) {
      final prev = rows.isNotEmpty ? rows.last : null;
      if (!opts.showTimestamps &&
          !isHeader &&
          prev != null &&
          !prev.isGroupHeader &&
          prev.depth == stack.length &&
          prev.entry.method == entry.method &&
          prev.entry.message == entry.message) {
        prev.repeatCount++;
      } else {
        rows.add(DisplayRow(
          key: '${entry.id}',
          entry: entry,
          depth: stack.length,
          repeatCount: 1,
          isGroupHeader: isHeader,
          groupId: isHeader ? entry.id : null,
          groupCollapsed: null,
        ));
      }
    }

    if (isHeader) {
      final defaultCollapsed = entry.method == 'groupCollapsed';
      final collapsed = opts.collapsedOverrides[entry.id] ?? defaultCollapsed;
      final headerRow = rows.isNotEmpty ? rows.last : null;
      if (headerRow != null && headerRow.groupId == entry.id) {
        headerRow.groupCollapsed = collapsed;
      }
      stack.add(_OpenGroup(entry.id, collapsed || hiddenByGroup));
    }
  }

  _computeSourceInfo(rows, opts.groupDimension);
  var finalRows = rows;
  if (opts.groupDimension != GroupDimension.off) {
    if (opts.layoutMode == LayoutMode.cluster) {
      finalRows = _clusterRows(rows, opts.clusterExpanded);
    } else if (opts.layoutMode == LayoutMode.swimlane) {
      _attachSwimlanes(rows);
    } else {
      _attachContiguousBrackets(rows);
    }
  }

  return ConsoleMessagesResult(
    rows: finalRows,
    hiddenCount: hiddenCount,
    levelCounts: levelCounts,
    totalCount: entries.length,
  );
}
