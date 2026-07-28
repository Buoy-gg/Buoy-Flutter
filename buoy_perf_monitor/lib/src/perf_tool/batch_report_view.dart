/// Ports packages/perf-monitor/src/perf-monitor/components/BatchReportView.tsx.
///
/// Loads every run in a batch, collapses each case to its median run, and
/// renders the lnav-style bar chart ([BatchBarReport]). Also powers the
/// Library's multi-select Compare: pass [reportIds] instead of [batchId] and
/// each selected run becomes its own chart row (no median collapsing — the
/// user picked exact runs).
///
/// Load → header → chart → failure summary. (The RN "top re-renderers" card is
/// omitted: Flutter has no React commit profiler, so no run carries render
/// data — RN hides that card in exactly the same situation.)
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../benchmark_storage.dart';
import '../compare_delta.dart';
import '../exporters.dart';
import '../perf_types.dart';
import 'batch_bar_report.dart';

class BatchReportView extends StatefulWidget {
  const BatchReportView({
    super.key,
    this.batchId,
    this.reportIds,
    this.onOpenLibrary,
  });

  /// Load every run of an automation batch (median per case).
  final String? batchId;

  /// Explicit set of saved runs to compare (Library multi-select). Each report
  /// becomes its own chart row. Takes precedence over [batchId].
  final List<String>? reportIds;

  /// Re-open the library if the user wants out.
  final VoidCallback? onOpenLibrary;

  @override
  State<BatchReportView> createState() => _BatchReportViewState();
}

class _BatchReportViewState extends State<BatchReportView> {
  List<BenchmarkReport> _reports = const [];
  bool _isLoading = true;

  bool get _isCompare => widget.reportIds != null;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _load();
  }

  @override
  void didUpdateWidget(BatchReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.reportIds?.join('\n');
    final newKey = widget.reportIds?.join('\n');
    if (oldWidget.batchId != widget.batchId || oldKey != newKey) {
      // ignore: discarded_futures
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final loaded = <BenchmarkReport>[];
    final ids = widget.reportIds;
    if (ids != null) {
      for (final id in ids) {
        final r = await BenchmarkStorage.load(id);
        if (r != null) loaded.add(r);
      }
      // Selection order is tap order — normalize to recording order so the
      // chart reads oldest → newest.
      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else {
      final all = await BenchmarkStorage.list();
      final matching = [
        for (final e in all)
          if (e.batchId == widget.batchId) e,
      ]..sort((a, b) {
          final byIndex =
              (a.batchIndex ?? 0).compareTo(b.batchIndex ?? 0);
          return byIndex != 0 ? byIndex : a.createdAt.compareTo(b.createdAt);
        });
      for (final entry in matching) {
        final r = await BenchmarkStorage.load(entry.id);
        if (r != null) loaded.add(r);
      }
    }
    if (!mounted) return;
    setState(() {
      _reports = loaded;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _EmptyBlock(title: 'Loading batch…');
    }

    final caseViews = _isCompare
        ? [
            for (final r in _reports)
              CaseView(
                caseId: r.id,
                caseName: r.metadata.name,
                median: r,
                runs: [r],
                representative: r,
              ),
          ]
        : computeCaseViews(_reports);

    if (caseViews.isEmpty) {
      return _EmptyBlock(
        title: _isCompare ? 'Nothing to compare' : 'No runs in this batch',
        body: _isCompare
            ? 'The selected runs could not be loaded — they may have been deleted.'
            : 'The batch finished without saving any reports. This usually means every case failed before recording started.',
        onOpenLibrary: widget.onOpenLibrary,
      );
    }

    final distinctRoutes = <String>{
      for (final c in caseViews)
        if (c.route != null && c.route!.isNotEmpty) c.route!,
    }.toList();
    final headerRoute = distinctRoutes.length > 1
        ? 'mixed (${distinctRoutes.length} routes)'
        : (distinctRoutes.isNotEmpty ? distinctRoutes.first : null);
    var totalRunCount = 0;
    var totalDuration = 0;
    for (final c in caseViews) {
      totalRunCount += c.runs.length;
      for (final r in c.runs) {
        totalDuration += r.stats.durationMs;
      }
    }

    // Surface any failing diagnostics captured at recording start so an
    // automated harness sees missing-capability state without opening every
    // report. Uniqued by diagnostic id across all runs.
    final diagnosticFailures = <String, String>{};
    for (final r in _reports) {
      for (final d in r.diagnostics ?? const <PerfDiagnostic>[]) {
        if (d.severity == 'fail') {
          diagnosticFailures.putIfAbsent(d.id, () => '${d.label} — ${d.detail}');
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (diagnosticFailures.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x1FEF4444),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x8CEF4444)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚠ ${diagnosticFailures.length} diagnostic${diagnosticFailures.length == 1 ? "" : "s"} failed during this batch',
                  style: const TextStyle(
                    color: MacOSColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                for (final line in diagnosticFailures.values)
                  Text(
                    '✗ $line',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MacOSColors.textPrimary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Header card.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MacOSColors.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Batch report',
                style: TextStyle(
                  color: MacOSColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${caseViews.length} ${caseViews.length == 1 ? "case" : "cases"} · '
                '$totalRunCount ${totalRunCount == 1 ? "run" : "runs"}'
                '${headerRoute != null ? " · $headerRoute" : ""}'
                '${totalDuration > 0 ? " · ${(totalDuration / 1000).toStringAsFixed(1)}s recorded" : ""}',
                style: const TextStyle(
                  color: MacOSColors.textMuted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _HeaderButton(
                    label: 'Copy markdown',
                    onTap: () {
                      // ignore: discarded_futures
                      copyText(_buildBatchMarkdown(caseViews));
                    },
                  ),
                  if (widget.onOpenLibrary != null) ...[
                    const SizedBox(width: 8),
                    _HeaderButton(
                      label: 'Library',
                      onTap: widget.onOpenLibrary!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Chart card.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MacOSColors.borderDefault),
          ),
          child: BatchBarReport(
            caseViews: caseViews,
            singleGroup: _isCompare,
          ),
        ),

        _FailureSummary(cases: caseViews),
      ],
    );
  }
}

/// Every failed run, so partial-case failures stay visible.
class _FailureSummary extends StatelessWidget {
  const _FailureSummary({required this.cases});
  final List<CaseView> cases;

  @override
  Widget build(BuildContext context) {
    final rows = <({String caseName, String reason, int runIndex})>[];
    for (final c in cases) {
      for (final r in c.runs) {
        final reason = r.metadata.batchFailureReason;
        if (reason == null) continue;
        rows.add((
          caseName: c.caseName,
          reason: reason,
          runIndex: r.metadata.runIndex ?? 0,
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MacOSColors.errorBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: MacOSColors.error.withValues(alpha: 0x55 / 255),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${rows.length} ${rows.length == 1 ? "run" : "runs"} failed',
            style: const TextStyle(
              color: MacOSColors.error,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          for (final row in rows) ...[
            Text(
              '· ${row.caseName} (run ${row.runIndex + 1})',
              style: const TextStyle(
                color: MacOSColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                row.reason,
                style: const TextStyle(
                  color: MacOSColors.textSecondary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.title, this.body, this.onOpenLibrary});
  final String title;
  final String? body;
  final VoidCallback? onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: MacOSColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MacOSColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (onOpenLibrary != null) ...[
            const SizedBox(height: 8),
            TouchableOpacity(
              activeOpacity: 0.7,
              onTap: onOpenLibrary,
              child: const Text(
                'Back to library →',
                style: TextStyle(
                  color: MacOSColors.info,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundInput,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: MacOSColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Markdown table matching the on-screen chart: one row per case, the same
/// four metric columns. Plain numbers (no bars) so it pastes cleanly.
String _buildBatchMarkdown(List<CaseView> cases) {
  final durationDef = compareRowDef('Duration (s)');
  final memoryDef = compareRowDef('Peak memory');
  final jsFpsDef = compareRowDef('Avg JS FPS');
  final cpuDef = compareRowDef('Peak CPU');

  final lines = <String>[
    '| Program | Route | Duration | Memory | JS FPS | Peak CPU |',
    '| --- | --- | ---: | ---: | ---: | ---: |',
  ];
  for (final c in cases) {
    final route = c.anchor.metadata.route ?? '';
    final stats = c.median?.stats;
    if (stats == null) {
      lines.add('| ${c.caseName} | $route | — | — | — | — |');
      continue;
    }
    lines.add(
      '| ${c.caseName} | $route | ${durationDef.pick(stats).toStringAsFixed(2)}s | '
      '${humanizeMb(memoryDef.pick(stats))} | ${jsFpsDef.pick(stats).toStringAsFixed(1)} | '
      '${cpuDef.pick(stats).toStringAsFixed(0)}% |',
    );
  }
  return lines.join('\n');
}
