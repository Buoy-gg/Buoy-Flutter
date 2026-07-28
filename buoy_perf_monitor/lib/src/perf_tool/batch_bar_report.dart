/// Ports packages/perf-monitor/src/perf-monitor/components/BatchBarReport.tsx.
///
/// The single comparison view for a batch, modeled on lnav's
/// performance-comparison chart: each metric value is drawn with an inline
/// horizontal bar sized to the value, so the winner is obvious at a glance.
///
/// Layout (left → right): Test Description (the group label, printed once per
/// group with a `┃` continuation glyph beneath) · Program (case/variant name,
/// disambiguated by differing params) · Duration · Memory · JS FPS · Peak CPU.
///
/// Bars scale PER GROUP (a group's worst value fills the bar) so the reading
/// is "which variant wins this scenario". Tint is good/bad within the group:
/// best → green, worst → red, middle → muted, respecting each metric's
/// higher-is-better semantics. Pure Row/Text — no charting library.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../compare_delta.dart';
import '../compute_case_labels.dart';
import '../compute_median_run.dart';
import '../perf_types.dart';

const double _descWidth = 150;
const double _progWidth = 84;
const double _metricWidth = 104;
const double _rowHeight = 34;

/// A case collapsed to a single canonical (median) run.
class CaseView {
  const CaseView({
    required this.caseId,
    required this.caseName,
    required this.median,
    required this.runs,
    required this.representative,
  });

  final String caseId;

  /// Display name, from the median or first run.
  final String caseName;

  /// Canonical report — the median. Null when every run in the case failed.
  final BenchmarkReport? median;

  /// All persisted runs for this case, in runIndex order.
  final List<BenchmarkReport> runs;

  /// Any report from the case, so route/name still render when median is null.
  final BenchmarkReport representative;

  BenchmarkReport get anchor => median ?? representative;
  String? get route => anchor.metadata.route;
  Map<String, String>? get params => anchor.metadata.params;
  int get batchIndex => anchor.metadata.batchIndex ?? 0;
}

/// Group reports by caseId (legacy single-run reports each become their own
/// case) and pick the median run per case. Stable batch-index order.
List<CaseView> computeCaseViews(List<BenchmarkReport> reports) {
  final buckets = <String, List<BenchmarkReport>>{};
  final order = <String>[];
  for (final r in reports) {
    final key = r.metadata.caseId ?? 'legacy::${r.id}';
    if (!buckets.containsKey(key)) {
      buckets[key] = [];
      order.add(key);
    }
    buckets[key]!.add(r);
  }

  final views = <CaseView>[];
  for (final key in order) {
    final runs = [...buckets[key]!]..sort(
        (a, b) =>
            (a.metadata.runIndex ?? 0).compareTo(b.metadata.runIndex ?? 0),
      );
    final valid = filterToValidRuns(runs);
    BenchmarkReport? median;
    for (final r in runs) {
      if (r.metadata.isMedianRun == true) {
        median = r;
        break;
      }
    }
    median ??= valid.isNotEmpty ? computeMedianRun(valid) : null;
    final representative = median ?? runs.first;
    views.add(CaseView(
      caseId: key,
      caseName: representative.metadata.name,
      median: median,
      runs: runs,
      representative: representative,
    ));
  }
  return views;
}

/// MB → "457.5MB" / "3.6GB" (memoryUsage.max is stored in MB).
String humanizeMb(double mb) {
  if (!mb.isFinite) return '—';
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)}GB';
  return '${mb.toStringAsFixed(1)}MB';
}

class _MetricColumn {
  const _MetricColumn({
    required this.key,
    required this.header,
    required this.def,
    required this.format,
  });
  final String key;
  final String header;
  final CompareRowDef def;
  final String Function(double value) format;
}

/// Default columns in lnav reading order — Duration + Memory lead, then the
/// two framework-specific signals.
final List<_MetricColumn> _metricColumns = [
  _MetricColumn(
    key: 'duration',
    header: 'Duration',
    def: compareRowDef('Duration (s)'),
    format: (v) => '${v.toStringAsFixed(2)}s',
  ),
  _MetricColumn(
    key: 'memory',
    header: 'Memory',
    def: compareRowDef('Peak memory'),
    format: humanizeMb,
  ),
  _MetricColumn(
    key: 'jsFps',
    header: 'JS FPS',
    def: compareRowDef('Avg JS FPS'),
    format: (v) => v.toStringAsFixed(1),
  ),
  _MetricColumn(
    key: 'cpu',
    header: 'Peak CPU',
    def: compareRowDef('Peak CPU'),
    format: (v) => '${v.toStringAsFixed(0)}%',
  ),
];

class _ChartRow {
  const _ChartRow({
    required this.caseId,
    required this.program,
    required this.stats,
  });
  final String caseId;

  /// Variant/program label (disambiguated within the group).
  final String program;

  /// Median stats, or null when the case has no usable run.
  final PerfStatsAggregate? stats;
}

class _ChartGroup {
  const _ChartGroup({
    required this.id,
    required this.title,
    required this.rows,
  });
  final String id;

  /// Test Description — the route, or a generic label for a flat batch.
  final String title;
  final List<_ChartRow> rows;
}

/// Partition cases into groups by route. A single-route (or route-less) batch
/// collapses to one group. [singleGroup] forces everything into one group
/// regardless of route — used by the Library's multi-select Compare, where the
/// point is scaling/tinting every selected run against each other.
List<_ChartGroup> _buildGroups(List<CaseView> cases, bool singleGroup) {
  final distinctRoutes = <String>{
    for (final c in cases)
      if (c.route != null && c.route!.isNotEmpty) c.route!,
  };
  final groupByRoute = !singleGroup && distinctRoutes.length > 1;

  final ordered = [...cases]
    ..sort((a, b) => a.batchIndex.compareTo(b.batchIndex));

  final buckets = <String, List<CaseView>>{};
  final bucketOrder = <String>[];
  for (final c in ordered) {
    final key = groupByRoute ? (c.route ?? '(no route)') : '(all)';
    if (!buckets.containsKey(key)) {
      buckets[key] = [];
      bucketOrder.add(key);
    }
    buckets[key]!.add(c);
  }

  return [
    for (final key in bucketOrder)
      () {
        final groupCases = buckets[key]!;
        final labels = computeCaseLabels([
          for (final c in groupCases)
            CaseLabelInput(
              name: c.caseName,
              params: c.params,
              route: groupByRoute ? null : c.route,
            ),
        ]).labels;
        final title = groupByRoute
            ? key
            : (distinctRoutes.length == 1 ? distinctRoutes.first : 'All cases');
        return _ChartGroup(
          id: key,
          title: title,
          rows: [
            for (var i = 0; i < groupCases.length; i++)
              _ChartRow(
                caseId: groupCases[i].caseId,
                program:
                    i < labels.length ? labels[i] : groupCases[i].caseName,
                stats: groupCases[i].median?.stats,
              ),
          ],
        );
      }(),
  ];
}

enum _Tone { best, worst, neutral }

/// Per-group, per-metric scaling + good/bad ranking.
class _ColumnStats {
  const _ColumnStats({required this.max, this.best, this.worst});
  final double max;
  final double? best;
  final double? worst;
}

_ColumnStats _columnStats(List<double> values, CompareRowDef def) {
  final finite = [
    for (final v in values)
      if (v.isFinite) v,
  ];
  if (finite.isEmpty) return const _ColumnStats(max: 0);
  final max = finite.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
  final lo = finite.reduce((a, b) => a < b ? a : b);
  final hi = finite.reduce((a, b) => a > b ? a : b);
  // Only tint when there's a spread to distinguish.
  if (lo == hi) return _ColumnStats(max: max);
  return _ColumnStats(
    max: max,
    best: def.higherIsBetter ? hi : lo,
    worst: def.higherIsBetter ? lo : hi,
  );
}

_Tone _toneFor(double value, _ColumnStats stats) {
  if (stats.best == null || stats.worst == null) return _Tone.neutral;
  if (value == stats.best) return _Tone.best;
  if (value == stats.worst) return _Tone.worst;
  return _Tone.neutral;
}

const Map<_Tone, Color> _toneFill = {
  _Tone.best: MacOSColors.successBackground,
  _Tone.worst: MacOSColors.errorBackground,
  _Tone.neutral: MacOSColors.backgroundHover,
};

const Map<_Tone, Color> _toneText = {
  _Tone.best: MacOSColors.success,
  _Tone.worst: MacOSColors.error,
  _Tone.neutral: MacOSColors.textPrimary,
};

class BatchBarReport extends StatelessWidget {
  const BatchBarReport({
    super.key,
    required this.caseViews,
    this.singleGroup = false,
  });

  final List<CaseView> caseViews;

  /// Chart every case in one group (cross-route scaling + best/worst tint).
  final bool singleGroup;

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups(caseViews, singleGroup);
    if (groups.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Column header.
          Container(
            padding: const EdgeInsets.only(bottom: 6),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: MacOSColors.borderDefault),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(
                  width: _descWidth,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('TEST DESCRIPTION', style: _headerStyle),
                  ),
                ),
                const SizedBox(
                  width: _progWidth,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('PROGRAM', style: _headerStyle),
                  ),
                ),
                for (final col in _metricColumns)
                  SizedBox(
                    width: _metricWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        col.header.toUpperCase(),
                        textAlign: TextAlign.right,
                        style: _headerStyle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var gi = 0; gi < groups.length; gi++)
            _group(groups[gi], showSeparator: gi > 0),
        ],
      ),
    );
  }

  Widget _group(_ChartGroup group, {required bool showSeparator}) {
    // Precompute per-metric scaling/tint for this group's rows.
    final stats = [
      for (final col in _metricColumns)
        _columnStats(
          [
            for (final r in group.rows)
              if (r.stats != null) col.def.pick(r.stats!),
          ],
          col.def,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSeparator)
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: MacOSColors.borderDefault,
          ),
        for (var ri = 0; ri < group.rows.length; ri++)
          SizedBox(
            height: _rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: _descWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ri == 0
                        ? Text(
                            group.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MacOSColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Text(
                              '┃',
                              style: TextStyle(
                                color: MacOSColors.textDisabled,
                                fontSize: 12,
                              ),
                            ),
                          ),
                  ),
                ),
                SizedBox(
                  width: _progWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      group.rows[ri].program,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MacOSColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                for (var ci = 0; ci < _metricColumns.length; ci++)
                  _metricCell(group.rows[ri], _metricColumns[ci], stats[ci]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _metricCell(_ChartRow row, _MetricColumn col, _ColumnStats colStats) {
    final value = row.stats != null ? col.def.pick(row.stats!) : double.nan;
    final hasValue = value.isFinite;
    final tone = hasValue ? _toneFor(value, colStats) : _Tone.neutral;
    final pct = hasValue && colStats.max > 0
        ? (value.abs() / colStats.max).clamp(0.04, 1.0)
        : 0.0;

    return SizedBox(
      width: _metricWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: _rowHeight - 8,
              color: MacOSColors.backgroundBase,
              child: Stack(
                children: [
                  if (pct > 0)
                    FractionallySizedBox(
                      widthFactor: pct,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: _toneFill[tone]),
                      ),
                    ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          hasValue ? col.format(value) : '—',
                          maxLines: 1,
                          style: TextStyle(
                            color: _toneText[tone],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const TextStyle _headerStyle = TextStyle(
  color: MacOSColors.textMuted,
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.5,
);
