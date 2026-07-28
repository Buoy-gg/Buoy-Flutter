/// Ports the remaining screens + cards of
/// packages/perf-monitor/src/perf-monitor/components/PerfMonitorModal.tsx:
/// `DetailView` (+ TimelineBlock / Sparkline / stat blocks), `SettingsView`,
/// the `RunCard` / `BatchRunCard` library cards, and PerfDiagnostics.tsx.
///
/// RN geometry preserved: two-row run card (duration-or-checkbox · name+route ·
/// verdict pill + chevron / four metric pills + relative age), 10pt mono
/// muted meta, verdict thresholds GOOD (0 jank) · WARN (<5% of samples) ·
/// JANK, memory tone <300MB green / <600MB amber / else red, 36px timeline
/// sparkline rows drawn as stacked bars.
library;

import 'dart:math' as math;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../aggregate_library.dart';
import '../benchmark_recorder.dart';
import '../benchmark_storage.dart';
import '../exporters.dart';
import '../perf_monitor_controller.dart';
import '../perf_settings.dart';
import '../perf_types.dart';
import 'automation_config_view.dart' show PerfMiniToggle;

const String _mono = 'monospace';
const double _timelineHeight = 36;

String _fmt(double n, [int digits = 0]) {
  if (!n.isFinite) return '—';
  return n.toStringAsFixed(digits);
}

Color fpsTone(double fps, double deviceMaxRefreshRate) {
  final max = deviceMaxRefreshRate > 0 ? deviceMaxRefreshRate : 60;
  if (fps >= max * PerfThresholds.fpsGoodPct) return MacOSColors.success;
  if (fps >= max * PerfThresholds.fpsWarnPct) return MacOSColors.warning;
  return MacOSColors.error;
}

Color cpuTone(double cpu) {
  if (cpu < PerfThresholds.cpuGoodMax) return MacOSColors.success;
  if (cpu < PerfThresholds.cpuWarnMax) return MacOSColors.warning;
  return MacOSColors.error;
}

Color memTone(double mb) {
  if (mb < 300) return MacOSColors.success;
  if (mb < 600) return MacOSColors.warning;
  return MacOSColors.error;
}

String fmtMemShort(double mb) {
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)}gb';
  return '${mb.round()}mb';
}

String formatRelativeAge(int then, int now) {
  final diffSec = math.max(0, ((now - then) / 1000).floor());
  if (diffSec < 60) return '${diffSec}s ago';
  final diffMin = diffSec ~/ 60;
  if (diffMin < 60) return '${diffMin}m ago';
  final diffHr = diffMin ~/ 60;
  if (diffHr < 24) return '${diffHr}h ago';
  return '${diffHr ~/ 24}d ago';
}

String formatDurationShort(int? ms) {
  if (ms == null) return '—';
  final sec = ms / 1000;
  if (sec < 10) return '${sec.toStringAsFixed(1)}s';
  if (sec < 60) return '${sec.round()}s';
  final min = sec ~/ 60;
  final rem = (sec % 60).round();
  return '${min}m${rem.toString().padLeft(2, '0')}';
}

/// One-word health verdict from the jank ratio (RN `runHealth`).
({String label, Color color, Color bg}) runHealth(BenchmarkIndexEntry? entry) {
  if (entry == null || entry.sampleCount == null) {
    return (
      label: '—',
      color: MacOSColors.textMuted,
      bg: MacOSColors.backgroundHover,
    );
  }
  final total = entry.sampleCount!;
  final jank = (entry.jsJankFrames ?? 0) + (entry.uiJankFrames ?? 0);
  final ratio = total > 0 ? jank / total : 0;
  if (ratio == 0) {
    return (
      label: 'GOOD',
      color: MacOSColors.success,
      bg: MacOSColors.successBackground,
    );
  }
  if (ratio < 0.05) {
    return (
      label: 'WARN',
      color: MacOSColors.warning,
      bg: MacOSColors.warningBackground,
    );
  }
  return (
    label: 'JANK',
    color: MacOSColors.error,
    bg: MacOSColors.errorBackground,
  );
}

/// Batch verdict — the same jank-ratio logic summed across non-failed children
/// (RN `batchHealth`).
({String label, Color color, Color bg}) batchHealth(LibraryItem item) {
  final total = item.sampleCount;
  final recorded = item.caseCount - item.failureCount;
  if (recorded == 0 || total == 0) {
    return (
      label: '—',
      color: MacOSColors.textMuted,
      bg: MacOSColors.backgroundHover,
    );
  }
  final ratio = (item.jsJankFrames + item.uiJankFrames) / total;
  if (ratio == 0) {
    return (
      label: 'GOOD',
      color: MacOSColors.success,
      bg: MacOSColors.successBackground,
    );
  }
  if (ratio < 0.05) {
    return (
      label: 'WARN',
      color: MacOSColors.warning,
      bg: MacOSColors.warningBackground,
    );
  }
  return (
    label: 'JANK',
    color: MacOSColors.error,
    bg: MacOSColors.errorBackground,
  );
}

// ── Library cards ─────────────────────────────────────────────────────────

class RunCard extends StatelessWidget {
  const RunCard({
    super.key,
    required this.entry,
    required this.selected,
    required this.selectionMode,
    required this.onOpen,
    required this.onToggleSelect,
    required this.onEnterSelection,
  });

  final BenchmarkIndexEntry entry;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onToggleSelect;
  final VoidCallback onEnterSelection;

  @override
  Widget build(BuildContext context) {
    final verdict = runHealth(entry);
    final deviceMax = entry.deviceMaxRefreshRate ?? 60;

    return _CardShell(
      selected: selected,
      onTap: selectionMode ? onToggleSelect : onOpen,
      onLongPress: selectionMode ? onToggleSelect : onEnterSelection,
      row1: _CardRow1(
        selectionMode: selectionMode,
        selected: selected,
        duration: formatDurationShort(entry.durationMs),
        name: entry.name,
        route: entry.route,
        chipLabel: entry.source == 'batch'
            ? (entry.batchFailureReason != null ? 'FAIL' : 'BATCH')
            : null,
        chipFailed: entry.batchFailureReason != null,
        verdict: verdict,
      ),
      row2: _CardRow2(
        js: entry.jsFpsAvg,
        ui: entry.uiFpsAvg,
        cpu: entry.cpuAvg,
        mem: entry.memMaxMb,
        deviceMax: deviceMax,
        age: formatRelativeAge(
          entry.createdAt,
          DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }
}

/// One Library card representing an automation batch. Pill values are the
/// worst-of-batch snapshot (lowest FPS, highest CPU/MEM across non-failed
/// children) so the card surfaces the loudest signal without opening it.
class BatchRunCard extends StatelessWidget {
  const BatchRunCard({
    super.key,
    required this.item,
    required this.selected,
    required this.selectionMode,
    required this.onOpen,
    required this.onDelete,
    required this.onToggleSelect,
    required this.onEnterSelection,
  });

  final LibraryItem item;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onToggleSelect;
  final VoidCallback onEnterSelection;

  @override
  Widget build(BuildContext context) {
    final verdict = batchHealth(item);
    final recorded = item.caseCount - item.failureCount;
    final hasValues = recorded > 0;

    // Subtitle: route or "mixed (N routes)", tagged with the pivot dimension
    // so the user knows what the batch is varying.
    final subtitleParts = <String>[
      if (item.routeCount == 1 && item.route != null) item.route!
      else if (item.routeCount > 1) 'mixed (${item.routeCount} routes)',
      if (item.pivotKey != null && item.pivotValueCount > 1)
        'by ${item.pivotKey}',
    ];

    return _CardShell(
      selected: selected,
      onTap: selectionMode ? onToggleSelect : onOpen,
      onLongPress: selectionMode ? onToggleSelect : onEnterSelection,
      row1: _CardRow1(
        selectionMode: selectionMode,
        selected: selected,
        duration: formatDurationShort(item.durationMs),
        name: item.baselineName ?? 'Batch',
        route: subtitleParts.isEmpty ? null : subtitleParts.join(' · '),
        failureNote:
            item.failureCount > 0 ? '${item.failureCount} failed' : null,
        chipLabel: 'BATCH · ${item.caseCount}',
        verdict: verdict,
        trailing: selectionMode
            ? null
            : TouchableOpacity(
                activeOpacity: 0.2,
                onTap: onDelete,
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: BuoyGlyph(BuoyIcons.trash2,
                      size: 14, color: MacOSColors.textMuted),
                ),
              ),
      ),
      row2: _CardRow2(
        js: hasValues ? item.jsFpsAvg : null,
        ui: hasValues ? item.uiFpsAvg : null,
        cpu: hasValues ? item.cpuAvg : null,
        mem: hasValues ? item.memMaxMb : null,
        deviceMax: item.deviceMaxRefreshRate,
        age: formatRelativeAge(
          item.createdAt,
          DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.row1,
    required this.row2,
  });

  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Widget row1;
  final Widget row2;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: TouchableOpacity(
        activeOpacity: 0.8,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? MacOSColors.info : MacOSColors.borderDefault,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [row1, const SizedBox(height: 8), row2],
          ),
        ),
      ),
    );
  }
}

class _CardRow1 extends StatelessWidget {
  const _CardRow1({
    required this.selectionMode,
    required this.selected,
    required this.duration,
    required this.name,
    required this.verdict,
    this.route,
    this.failureNote,
    this.chipLabel,
    this.chipFailed = false,
    this.trailing,
  });

  final bool selectionMode;
  final bool selected;
  final String duration;
  final String name;
  final String? route;
  final String? failureNote;
  final String? chipLabel;
  final bool chipFailed;
  final ({String label, Color color, Color bg}) verdict;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 56,
          child: selectionMode
              ? Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? MacOSColors.infoBackground : null,
                    border: Border.all(
                      width: 1.5,
                      color: selected
                          ? MacOSColors.info
                          : MacOSColors.borderDefault,
                    ),
                  ),
                  child: selected
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: MacOSColors.info,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                )
              : Text(
                  duration,
                  style: const TextStyle(
                    fontSize: 10,
                    color: MacOSColors.textMuted,
                    fontFamily: _mono,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MacOSColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFamily: _mono,
                        height: 1.23,
                      ),
                    ),
                  ),
                  if (chipLabel != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: chipFailed
                            ? MacOSColors.errorBackground
                            : MacOSColors.infoBackground,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: (chipFailed
                                  ? MacOSColors.error
                                  : MacOSColors.info)
                              .withValues(alpha: 0x55 / 255),
                        ),
                      ),
                      child: Text(
                        chipLabel!,
                        style: TextStyle(
                          color: chipFailed
                              ? MacOSColors.error
                              : MacOSColors.info,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          fontFamily: _mono,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (route != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    route!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MacOSColors.textMuted,
                      fontSize: 11,
                      fontFamily: _mono,
                    ),
                  ),
                ),
              if (failureNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    failureNote!,
                    maxLines: 1,
                    style: const TextStyle(
                      color: MacOSColors.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: verdict.bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            verdict.label,
            style: TextStyle(
              color: verdict.color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: _mono,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ?trailing,
        const BuoyGlyph(BuoyIcons.chevronRight,
            size: 14, color: MacOSColors.textMuted),
      ],
    );
  }
}

class _CardRow2 extends StatelessWidget {
  const _CardRow2({
    required this.js,
    required this.ui,
    required this.cpu,
    required this.mem,
    required this.deviceMax,
    required this.age,
  });

  final double? js;
  final double? ui;
  final double? cpu;
  final double? mem;
  final double deviceMax;
  final String age;

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, String value, Color tone) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: MacOSColors.backgroundHover,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: MacOSColors.borderDefault),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: MacOSColors.textMuted,
                  fontFamily: _mono,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: _mono,
                  color: tone,
                ),
              ),
            ],
          ),
        );

    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              pill(
                'JS',
                js != null && js!.isFinite ? '${js!.round()}' : '—',
                js != null && js!.isFinite
                    ? fpsTone(js!, deviceMax)
                    : MacOSColors.textMuted,
              ),
              pill(
                'UI',
                ui != null && ui!.isFinite ? '${ui!.round()}' : '—',
                ui != null && ui!.isFinite
                    ? fpsTone(ui!, deviceMax)
                    : MacOSColors.textMuted,
              ),
              pill(
                'CPU',
                cpu != null && cpu!.isFinite ? '${cpu!.round()}%' : '—',
                cpu != null && cpu!.isFinite
                    ? cpuTone(cpu!)
                    : MacOSColors.textMuted,
              ),
              pill(
                'MEM',
                mem != null && mem!.isFinite ? fmtMemShort(mem!) : '—',
                mem != null && mem!.isFinite
                    ? memTone(mem!)
                    : MacOSColors.textMuted,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          age,
          style: const TextStyle(
            fontSize: 10,
            color: MacOSColors.textMuted,
            fontFamily: _mono,
          ),
        ),
      ],
    );
  }
}

// ── Detail view ──────────────────────────────────────────────────────────

class PerfDetailView extends StatelessWidget {
  const PerfDetailView({super.key, required this.report});
  final BenchmarkReport report;

  @override
  Widget build(BuildContext context) {
    final stats = report.stats;
    final created = DateTime.fromMillisecondsSinceEpoch(report.createdAt);
    final route = report.metadata.route;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          report.metadata.name,
          style: const TextStyle(
            color: MacOSColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${created.toLocal()} · ${stats.deviceMaxRefreshRate.round()} Hz device'
          '${route != null ? " · route $route" : ""}',
          style: const TextStyle(
            color: MacOSColors.textMuted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ExportButton(
                label: 'Copy summary',
                // ignore: discarded_futures
                onTap: () => copyText(formatReportAsMarkdown(report)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ExportButton(
                label: 'Export JSON',
                // ignore: discarded_futures
                onTap: () => copyText(formatReportAsJson(report)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TimelineBlock(report: report),
        _FpsStatsBlock(
          title: 'JS thread',
          channel: stats.jsFps,
          jankFrames: stats.jsJankFrames,
          jankLabel: 'Jank frames (<50fps)',
          deviceMaxRefreshRate: stats.deviceMaxRefreshRate,
        ),
        const SizedBox(height: 12),
        _FpsStatsBlock(
          title: 'UI thread',
          channel: stats.uiFps,
          jankFrames: stats.uiJankFrames,
          jankLabel:
              'Jank frames (<${(stats.deviceMaxRefreshRate * 0.85).round()}fps)',
          deviceMaxRefreshRate: stats.deviceMaxRefreshRate,
        ),
        const SizedBox(height: 12),
        _StatsBlock(
          title: 'CPU usage',
          rows: [
            ('Avg', '${_fmt(stats.cpuUsage.avg, 1)} %', cpuTone(stats.cpuUsage.avg)),
            ('p95', '${_fmt(stats.cpuUsage.p95, 1)} %', cpuTone(stats.cpuUsage.p95)),
            ('Max', '${_fmt(stats.cpuUsage.max, 1)} %', null),
            ('Min', '${_fmt(stats.cpuUsage.min, 1)} %', null),
          ],
        ),
        const SizedBox(height: 12),
        _StatsBlock(
          title: 'Memory',
          rows: [
            ('Avg', '${_fmt(stats.memoryUsage.avg, 1)} MB', null),
            ('Peak', '${_fmt(stats.memoryUsage.max, 1)} MB', null),
            ('Min', '${_fmt(stats.memoryUsage.min, 1)} MB', null),
          ],
        ),
        _DiagnosticsBlock(report: report),
      ],
    );
  }
}

class _FpsStatsBlock extends StatelessWidget {
  const _FpsStatsBlock({
    required this.title,
    required this.channel,
    required this.jankFrames,
    required this.jankLabel,
    required this.deviceMaxRefreshRate,
  });

  final String title;
  final AggregateChannel channel;
  final int jankFrames;
  final String jankLabel;
  final double deviceMaxRefreshRate;

  @override
  Widget build(BuildContext context) => _StatsBlock(
        title: title,
        rows: [
          (
            'Avg',
            '${_fmt(channel.avg, 1)} fps',
            fpsTone(channel.avg, deviceMaxRefreshRate)
          ),
          (
            'Min',
            '${_fmt(channel.min)} fps',
            fpsTone(channel.min, deviceMaxRefreshRate)
          ),
          (
            'p95',
            '${_fmt(channel.p95, 1)} fps',
            fpsTone(channel.p95, deviceMaxRefreshRate)
          ),
          ('Max', '${_fmt(channel.max)} fps', null),
          (jankLabel, '$jankFrames', null),
        ],
      );
}

class _StatsBlock extends StatelessWidget {
  const _StatsBlock({required this.title, required this.rows});
  final String title;
  final List<(String, String, Color?)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: MacOSColors.textSecondary,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        color: MacOSColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    row.$2,
                    style: TextStyle(
                      color: row.$3 ?? MacOSColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Recording-start capability snapshot, surfaced inline so a reviewer doesn't
/// have to open Settings → Diagnostics to know whether the run is trustworthy.
class _DiagnosticsBlock extends StatelessWidget {
  const _DiagnosticsBlock({required this.report});
  final BenchmarkReport report;

  @override
  Widget build(BuildContext context) {
    final diagnostics = report.diagnostics ?? const <PerfDiagnostic>[];
    final fails = [
      for (final d in diagnostics)
        if (d.severity == 'fail') d,
    ];
    final warns = [
      for (final d in diagnostics)
        if (d.severity == 'warn') d,
    ];
    if (fails.isEmpty && warns.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: fails.isNotEmpty
              ? MacOSColors.error
              : MacOSColors.borderDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DIAGNOSTICS AT RECORDING START',
            style: TextStyle(
              color: MacOSColors.textSecondary,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          for (final d in [...fails, ...warns])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.severity == "fail" ? "✗" : "!"} ${d.label}',
                    style: TextStyle(
                      color: d.severity == 'fail'
                          ? MacOSColors.error
                          : MacOSColors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    d.detail,
                    style: const TextStyle(
                      color: MacOSColors.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Stacked-bar sparklines + marker ticks over the recording's samples
/// (RN `TimelineBlock` / `Sparkline`, no charting library).
class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({required this.report});
  final BenchmarkReport report;

  @override
  Widget build(BuildContext context) {
    if (report.samples.length < 2) return const SizedBox.shrink();
    final first = report.samples.first.timestamp;
    final last = report.samples.last.timestamp;
    final span = math.max(1, last - first);
    final refreshRate = report.stats.deviceMaxRefreshRate > 0
        ? report.stats.deviceMaxRefreshRate
        : 60.0;
    final markers = report.markers;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'TIMELINE',
            style: TextStyle(
              color: MacOSColors.textSecondary,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          _Spark(
            title: 'JS FPS',
            samples: report.samples,
            markers: markers,
            first: first,
            span: span,
            valueOf: (s) => s.jsFps,
            max: refreshRate,
            toneFor: (v) => fpsTone(v, refreshRate),
          ),
          _Spark(
            title: 'UI FPS',
            samples: report.samples,
            markers: markers,
            first: first,
            span: span,
            valueOf: (s) => s.uiFps,
            max: refreshRate,
            toneFor: (v) => fpsTone(v, refreshRate),
          ),
          _Spark(
            title: 'CPU %',
            samples: report.samples,
            markers: markers,
            first: first,
            span: span,
            valueOf: (s) => s.cpuUsage,
            max: 100,
            toneFor: cpuTone,
          ),
          _Spark(
            title: 'Memory MB',
            samples: report.samples,
            markers: markers,
            first: first,
            span: span,
            valueOf: (s) => s.memoryUsage,
            max: math.max(
              512,
              (report.stats.memoryUsage.max / 100).ceil() * 100,
            ).toDouble(),
            toneFor: (_) => MacOSColors.info,
          ),
          if (markers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${markers.length} ${markers.length == 1 ? "marker" : "markers"} dropped',
                style: const TextStyle(
                  color: MacOSColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark({
    required this.title,
    required this.samples,
    required this.markers,
    required this.first,
    required this.span,
    required this.valueOf,
    required this.max,
    required this.toneFor,
  });

  final String title;
  final List<PerfSample> samples;
  final List<BenchmarkMarker> markers;
  final int first;
  final int span;
  final double Function(PerfSample) valueOf;
  final double max;
  final Color Function(double) toneFor;

  @override
  Widget build(BuildContext context) {
    final bucketCount = math.min(samples.length, 60);
    final stride = math.max(1, samples.length ~/ bucketCount);
    final bars = <({double ratio, Color color})>[];
    for (var i = 0; i < samples.length; i += stride) {
      final v = valueOf(samples[i]);
      final ratio = max > 0 ? (v / max).clamp(0.0, 1.0) : 0.0;
      bars.add((ratio: ratio, color: toneFor(v)));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: MacOSColors.textSecondary,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: _timelineHeight,
              color: const Color(0x0AFFFFFF),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < bars.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: i == bars.length - 1 ? 0 : 1,
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.bottomCenter,
                                heightFactor:
                                    math.max(0.02, bars[i].ratio),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: bars[i].color,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final m in markers)
                    if ((m.timestamp - first) / span >= 0 &&
                        (m.timestamp - first) / span <= 1)
                      Align(
                        alignment: Alignment(
                          ((m.timestamp - first) / span) * 2 - 1,
                          0,
                        ),
                        child: Container(
                          width: 1.5,
                          height: _timelineHeight,
                          color: const Color(0xD9FCD34D),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TouchableOpacity(
        activeOpacity: 0.7,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MacOSColors.backgroundInput,
            borderRadius: BorderRadius.circular(8),
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

// ── Settings ─────────────────────────────────────────────────────────────

/// RN `SettingsView`: the RECORDING + STRIP METRICS sections, the Diagnostics
/// link, and Reset to defaults. Rows with no Flutter analog (render capture /
/// live highlights / REA worklet FPS) are omitted — the persisted JSON keeps
/// their fields, so the blob stays shape-compatible with the RN tool.
class PerfSettingsView extends StatefulWidget {
  const PerfSettingsView({
    super.key,
    required this.onOpenDiagnostics,
    required this.onReset,
  });

  final VoidCallback onOpenDiagnostics;
  final VoidCallback onReset;

  @override
  State<PerfSettingsView> createState() => _PerfSettingsViewState();
}

class _PerfSettingsViewState extends State<PerfSettingsView> {
  PerfSettings _settings = PerfSettingsStore.instance.current;
  void Function()? _unsub;

  @override
  void initState() {
    super.initState();
    _unsub = PerfSettingsStore.instance.subscribe((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stripCount = [
      _settings.showJsFps,
      _settings.showUiFps,
      _settings.showCpu,
      _settings.showMem,
    ].where((v) => v).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsSection(
          title: 'RECORDING',
          icon: BuoyIcons.circle,
          iconColor: MacOSColors.error,
          children: [
            _SettingsRow(
              label: 'Auto-stop recording when app is backgrounded',
              value: _settings.autoStopOnBackground,
              onChanged: (v) => PerfSettingsStore.instance.update(
                (s) => s.copyWith(autoStopOnBackground: v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          title: 'STRIP METRICS',
          icon: BuoyIcons.database,
          iconColor: MacOSColors.warning,
          badgeCount: stripCount,
          children: [
            _SettingsRow(
              label: 'JS FPS',
              value: _settings.showJsFps,
              onChanged: (v) => PerfSettingsStore.instance
                  .update((s) => s.copyWith(showJsFps: v)),
            ),
            _SettingsRow(
              label: 'UI FPS',
              value: _settings.showUiFps,
              onChanged: (v) => PerfSettingsStore.instance
                  .update((s) => s.copyWith(showUiFps: v)),
            ),
            _SettingsRow(
              label: 'CPU',
              value: _settings.showCpu,
              onChanged: (v) => PerfSettingsStore.instance
                  .update((s) => s.copyWith(showCpu: v)),
            ),
            _SettingsRow(
              label: 'MEM',
              value: _settings.showMem,
              onChanged: (v) => PerfSettingsStore.instance
                  .update((s) => s.copyWith(showMem: v)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TouchableOpacity(
          activeOpacity: 0.7,
          onTap: widget.onOpenDiagnostics,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MacOSColors.backgroundInput,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MacOSColors.borderDefault),
            ),
            child: const Text(
              'Open Diagnostics →',
              style: TextStyle(
                color: MacOSColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TouchableOpacity(
          activeOpacity: 0.7,
          onTap: widget.onReset,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x1FEF4444),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x66EF4444)),
            ),
            child: const Text(
              'Reset to defaults',
              style: TextStyle(
                color: Color(0xFFFCA5A5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
    this.badgeCount,
  });

  final String title;
  final LucideIcon icon;
  final Color iconColor;
  final int? badgeCount;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: icon,
            iconColor: iconColor,
            title: title,
            badgeCount: badgeCount,
            badgeColor: iconColor,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: MacOSColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PerfMiniToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Ports PerfDiagnostics.tsx — the live capability probe, rendered from the
/// same rows embedded in every saved report.
class PerfDiagnosticsView extends StatelessWidget {
  const PerfDiagnosticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final rows = buildPerfDiagnostics();
    final snapshot = PerfMonitorController.instance.getSnapshot();

    Color severityColor(String severity) => switch (severity) {
          'ok' => MacOSColors.success,
          'warn' => MacOSColors.warning,
          'fail' => MacOSColors.error,
          _ => MacOSColors.textMuted,
        };
    String glyph(String severity) => switch (severity) {
          'ok' => '✓',
          'warn' => '!',
          'fail' => '✗',
          _ => '–',
        };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MacOSColors.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CAPABILITIES',
                style: TextStyle(
                  color: MacOSColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${glyph(row.severity)} ${row.label}',
                        style: TextStyle(
                          color: severityColor(row.severity),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        row.detail,
                        style: const TextStyle(
                          color: MacOSColors.textSecondary,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      if (row.hint != null)
                        Text(
                          row.hint!,
                          style: const TextStyle(
                            color: MacOSColors.textMuted,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StatsBlock(
          title: 'Live sampler',
          rows: [
            ('Mode', snapshot.mode.wire, null),
            (
              'Refresh rate',
              '${snapshot.deviceMaxRefreshRate.round()} Hz',
              null
            ),
            ('History samples', '${snapshot.history.length}', null),
            (
              'CPU available',
              snapshot.capabilities.cpu ? 'yes' : 'no',
              null
            ),
            (
              'Accurate memory',
              snapshot.capabilities.accurateMemory ? 'yes' : 'no',
              null
            ),
          ],
        ),
      ],
    );
  }
}
