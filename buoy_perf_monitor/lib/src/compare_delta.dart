/// Ports packages/perf-monitor/src/perf-monitor/utils/compareDelta.ts.
///
/// Shared delta math for the comparison views. Keeping the row set in one
/// place matters: a green Δ in the batch chart must mean the same thing as a
/// green Δ anywhere else.
library;

import 'dart:math' as math;

import 'perf_types.dart';

class CompareRowDef {
  const CompareRowDef({
    required this.label,
    required this.pick,
    required this.higherIsBetter,
    this.fractionDigits,
    this.unit,
  });

  final String label;
  final double Function(PerfStatsAggregate stats) pick;

  /// True when "more is better" (FPS); false for CPU/memory/jank.
  final bool higherIsBetter;
  final int? fractionDigits;
  final String? unit;
}

/// Canonical metric set rendered by the compare views (RN `COMPARE_ROWS`).
final List<CompareRowDef> compareRows = [
  CompareRowDef(
      label: 'Avg JS FPS', pick: (s) => s.jsFps.avg, higherIsBetter: true),
  CompareRowDef(
      label: 'p95 JS FPS', pick: (s) => s.jsFps.p95, higherIsBetter: true),
  CompareRowDef(
    label: 'Min JS FPS',
    pick: (s) => s.jsFps.min,
    higherIsBetter: true,
    fractionDigits: 0,
  ),
  CompareRowDef(
      label: 'Avg UI FPS', pick: (s) => s.uiFps.avg, higherIsBetter: true),
  CompareRowDef(
      label: 'p95 UI FPS', pick: (s) => s.uiFps.p95, higherIsBetter: true),
  // Peak before Avg: peak is where jank originates.
  CompareRowDef(
    label: 'Peak CPU',
    pick: (s) => s.cpuUsage.max,
    higherIsBetter: false,
    unit: '%',
  ),
  CompareRowDef(
    label: 'Avg CPU',
    pick: (s) => s.cpuUsage.avg,
    higherIsBetter: false,
    unit: '%',
  ),
  CompareRowDef(
    label: 'Peak memory',
    pick: (s) => s.memoryUsage.max,
    higherIsBetter: false,
    unit: ' MB',
  ),
  CompareRowDef(
    label: 'JS jank frames',
    pick: (s) => s.jsJankFrames.toDouble(),
    higherIsBetter: false,
    fractionDigits: 0,
  ),
  CompareRowDef(
    label: 'UI jank frames',
    pick: (s) => s.uiJankFrames.toDouble(),
    higherIsBetter: false,
    fractionDigits: 0,
  ),
  CompareRowDef(
    label: 'Duration (s)',
    pick: (s) => s.durationMs / 1000,
    higherIsBetter: false,
  ),
];

CompareRowDef compareRowDef(String label) =>
    compareRows.firstWhere((r) => r.label == label);

enum DeltaTone { neutral, better, worse }

class DeltaResult {
  const DeltaResult({
    required this.baseline,
    required this.current,
    required this.delta,
    required this.tone,
  });
  final double baseline;
  final double current;
  final double delta;
  final DeltaTone tone;
}

/// Value delta between baseline and current using the row's semantics.
DeltaResult computeDelta(
  CompareRowDef def,
  double baseline,
  double current,
) {
  final delta = current - baseline;
  var tone = DeltaTone.neutral;
  if (delta != 0) {
    final better = def.higherIsBetter ? delta > 0 : delta < 0;
    tone = better ? DeltaTone.better : DeltaTone.worse;
  }
  return DeltaResult(
    baseline: baseline,
    current: current,
    delta: delta,
    tone: tone,
  );
}

/// Format a number with the row's preferred fraction digits + unit.
String formatRowValue(CompareRowDef def, double value) {
  if (!value.isFinite) return '—';
  return '${value.toStringAsFixed(def.fractionDigits ?? 1)}${def.unit ?? ''}';
}

/// Three-way classification of a delta against the noise floor of the two
/// cells being compared (RN `Significance`):
///   significant — |delta| > 2 × sqrt(baseσ² + curσ²)  (~95% CI)
///   noise       — within that 2σ band
///   unknown     — a stddev is missing (legacy single-run reports)
typedef Significance = String;

Significance computeSignificance(
  double delta,
  double baselineStddev,
  double currentStddev,
) {
  if (!baselineStddev.isFinite || !currentStddev.isFinite) return 'unknown';
  final combined = math.sqrt(
    baselineStddev * baselineStddev + currentStddev * currentStddev,
  );
  // Both spreads zero: a single-run case with no variance budget to charge
  // against — any non-zero delta counts.
  if (combined == 0) return delta == 0 ? 'noise' : 'significant';
  return delta.abs() > 2 * combined ? 'significant' : 'noise';
}

/// Signed z-score of the delta against the same denominator, so |z| ≥ 2 means
/// "significant" in this codebase's convention. Null when there isn't enough
/// variance info; ±infinity for the degenerate single-run case.
double? computeZScore(
  double delta,
  double baselineStddev,
  double currentStddev,
) {
  if (!baselineStddev.isFinite || !currentStddev.isFinite) return null;
  final combined = math.sqrt(
    baselineStddev * baselineStddev + currentStddev * currentStddev,
  );
  if (combined == 0) {
    if (delta == 0) return 0;
    return delta > 0 ? double.infinity : double.negativeInfinity;
  }
  return delta / combined;
}
