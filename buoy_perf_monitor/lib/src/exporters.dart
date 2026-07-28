/// Ports packages/perf-monitor/src/perf-monitor/utils/exporters.ts (+ the
/// clipboard helper from utils/clipboard.ts).
///
/// The markdown output is meant to drop straight into a PR or Slack post —
/// hence tables and no custom symbols. `reaFps` / render-commit / synthetic
/// sections are omitted (no Flutter analog).
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import 'perf_types.dart';

String _fmt(double n, [int fractionDigits = 0]) {
  if (!n.isFinite) return '—';
  return n.toStringAsFixed(fractionDigits);
}

String _tableRow(List<String> cells) => '| ${cells.join(' | ')} |';

String _channelRow(String label, AggregateChannel c, int digits) => _tableRow([
      label,
      _fmt(c.avg, digits),
      _fmt(c.p95, digits),
      _fmt(c.min, digits),
      _fmt(c.max, digits),
    ]);

String formatReportAsMarkdown(BenchmarkReport report) {
  final metadata = report.metadata;
  final stats = report.stats;
  final date =
      DateTime.fromMillisecondsSinceEpoch(report.createdAt).toIso8601String();
  final route = metadata.route != null ? ' · route `${metadata.route}`' : '';

  final lines = <String>[
    '# ${metadata.name}',
    '',
    'Captured $date$route',
    'Device max refresh rate: ${stats.deviceMaxRefreshRate.round()} Hz',
    'Samples: ${stats.sampleCount} · Duration: ${_fmt(stats.durationMs / 1000, 1)}s',
  ];

  if (report.samples.isNotEmpty) {
    lines.addAll([
      '',
      '## Aggregate stats',
      '',
      _tableRow(['Metric', 'Avg', 'p95', 'Min', 'Max']),
      _tableRow(['---', '---', '---', '---', '---']),
      _channelRow('JS FPS', stats.jsFps, 1),
      _channelRow('UI FPS', stats.uiFps, 1),
      _channelRow('CPU %', stats.cpuUsage, 1),
      _channelRow('Memory MB', stats.memoryUsage, 1),
      '',
      'Jank frames — JS < 50fps: ${stats.jsJankFrames}, UI <85% of max: ${stats.uiJankFrames}',
    ]);
  }

  final diagnostics = report.diagnostics ?? const [];
  final fails = [
    for (final d in diagnostics)
      if (d.severity == 'fail') d,
  ];
  final warns = [
    for (final d in diagnostics)
      if (d.severity == 'warn') d,
  ];
  if (fails.isNotEmpty || warns.isNotEmpty) {
    lines.addAll(['', '## Diagnostics', '']);
    for (final d in fails) {
      lines.add('- ❌ **${d.label}** — ${d.detail}');
      if (d.hint != null) lines.add('  - ${d.hint}');
    }
    for (final d in warns) {
      lines.add('- ⚠️ **${d.label}** — ${d.detail}');
    }
  }

  if (metadata.notes != null) {
    lines.addAll(['', '## Notes', metadata.notes!]);
  }
  return lines.join('\n');
}

String formatReportAsJson(BenchmarkReport report) =>
    const JsonEncoder.withIndent('  ').convert(report.toJson());

/// Compare N runs as a markdown table; Δ column = last run vs first
/// (RN `formatCompareAsMarkdown`).
String formatCompareAsMarkdown(List<BenchmarkReport> reports) {
  if (reports.isEmpty) return '';
  if (reports.length == 1) return formatReportAsMarkdown(reports.first);

  final names = [for (final r in reports) r.metadata.name];
  final lines = <String>[
    '# Perf compare — ${names.join(" vs ")}',
    '',
    'Comparing ${reports.length} runs. Δ column = last run vs first.',
    '',
  ];

  final headerCells = ['Metric', ...names, 'Δ vs first'];
  lines.add(_tableRow(headerCells));
  lines.add(_tableRow([for (final _ in headerCells) '---']));

  void row(
    String label,
    double Function(PerfStatsAggregate) pick,
    bool higherIsBetter, {
    int fractionDigits = 1,
    String unit = '',
  }) {
    final values = [for (final r in reports) pick(r.stats)];
    final cells = [label, for (final v in values) '${_fmt(v, fractionDigits)}$unit'];
    final baseline = values.first;
    final delta = values.last - baseline;
    final better = higherIsBetter ? delta > 0 : delta < 0;
    final sign = delta == 0 ? '·' : (better ? '✅' : '⚠️');
    final deltaStr = delta == 0
        ? '0'
        : '${delta > 0 ? "+" : ""}${delta.toStringAsFixed(fractionDigits)}';
    final pctStr = (!delta.isFinite || !baseline.isFinite || baseline == 0)
        ? '—'
        : '${(delta / baseline) * 100 > 0 ? "+" : ""}${((delta / baseline) * 100).toStringAsFixed(0)}%';
    cells.add('$sign $deltaStr$unit ($pctStr)');
    lines.add(_tableRow(cells));
  }

  row('Avg JS FPS', (s) => s.jsFps.avg, true);
  row('p95 JS FPS', (s) => s.jsFps.p95, true);
  row('Min JS FPS', (s) => s.jsFps.min, true, fractionDigits: 0);
  row('Avg UI FPS', (s) => s.uiFps.avg, true);
  row('p95 UI FPS', (s) => s.uiFps.p95, true);
  row('Peak CPU', (s) => s.cpuUsage.max, false, unit: '%');
  row('Avg CPU', (s) => s.cpuUsage.avg, false, unit: '%');
  row('Peak memory', (s) => s.memoryUsage.max, false, unit: ' MB');
  row('JS jank frames', (s) => s.jsJankFrames.toDouble(), false,
      fractionDigits: 0);
  row('UI jank frames', (s) => s.uiJankFrames.toDouble(), false,
      fractionDigits: 0);
  row('Duration (s)', (s) => s.durationMs / 1000, false);

  return lines.join('\n');
}

/// Copy text to the system clipboard (RN `copyText`). Returns false when the
/// platform channel refuses.
Future<bool> copyText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

/// Read the system clipboard (RN `readClipboardText`). Null when unavailable.
Future<String?> readClipboardText() async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  } catch (_) {
    return null;
  }
}
