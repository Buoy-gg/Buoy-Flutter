/// Ports packages/perf-monitor/src/perf-monitor/utils/batchTimeEstimate.ts.
///
/// Total-batch-time projection for the progress overlay. Deliberately
/// approximate — the aim is "close enough to plan a coffee break", not
/// millisecond accuracy.
library;

import 'dart:math' as math;

import 'perf_types.dart';

/// Wall-clock allowance per case for navigation (bounce + target + observer
/// wait): one second per nav, two navs per case.
const int _navAllowanceMs = 2000;

/// Tiny buffer for the saving phase per case.
const int _saveAllowanceMs = 200;

/// Estimated cost of a realm reload. Flutter forces reloadBetweenCases off, so
/// this only shows up if a config somehow carries it — kept for parity.
const int _reloadAllowanceMs = 2500;

int _effectiveRunsPerCase(AutomationConfig config) =>
    math.min(10, math.max(1, config.runsPerCase));

int _effectiveCoolDownMs(AutomationConfig config) =>
    math.min(30000, math.max(0, config.coolDownMs));

/// Total wall-clock budget for one run — nav + settle + record + save.
int perRunEstimateMs(AutomationConfig config) =>
    _navAllowanceMs + config.settleMs + config.perCaseDurationMs + _saveAllowanceMs;

/// Total wall-clock budget for one case: N runs + (N-1) inter-run cool-downs
/// (+ reload). The inter-CASE cool-down belongs to [totalBatchEstimateMs].
int perCaseEstimateMs(AutomationConfig config) {
  final runs = _effectiveRunsPerCase(config);
  final coolDown = _effectiveCoolDownMs(config);
  return runs * perRunEstimateMs(config) +
      (runs - 1) * coolDown +
      (config.reloadBetweenCases ? _reloadAllowanceMs : 0);
}

/// Estimated wall-clock total for an entire batch. The last case has no
/// post-case cool-down or reload, so one of each is subtracted.
int totalBatchEstimateMs(AutomationConfig config) {
  final cases = config.cases.length;
  if (cases == 0) return 0;
  final coolDown = _effectiveCoolDownMs(config);
  final interCaseCoolDown = math.max(0, cases - 1) * coolDown;
  final total = cases * perCaseEstimateMs(config) + interCaseCoolDown;
  return math.max(
    0,
    config.reloadBetweenCases ? total - _reloadAllowanceMs : total,
  );
}

/// Wall-clock time still ahead given the runner status + config. Null when the
/// batch is idle/done/cancelled (caller should hide the timer).
///
/// Precise within the current case (uses the runner's `remainingMs`);
/// estimated for future cases.
int? batchRemainingMs(AutomationStatus status, AutomationConfig config) {
  if (status.phase == 'idle' ||
      status.phase == 'done' ||
      status.phase == 'cancelled') {
    return null;
  }

  final total = status.total ?? config.cases.length;
  final index = status.index ?? 0;
  final runTotal = status.runTotal ?? _effectiveRunsPerCase(config);
  final runIndex = status.runIndex ?? 0;
  final coolDown = _effectiveCoolDownMs(config);

  final futureCases = math.max(0, total - index - 1);
  final futureCasesMs = futureCases * (perCaseEstimateMs(config) + coolDown);

  final futureRunsInCurrentCase = math.max(0, runTotal - runIndex - 1);
  final futureRunsMs =
      futureRunsInCurrentCase * (perRunEstimateMs(config) + coolDown);

  final remaining = status.remainingMs ?? 0;
  int currentRunRemainingMs;
  switch (status.phase) {
    case 'navigating-bounce':
    case 'navigating-target':
      currentRunRemainingMs = _navAllowanceMs +
          config.settleMs +
          config.perCaseDurationMs +
          _saveAllowanceMs;
    case 'settling':
      currentRunRemainingMs =
          remaining + config.perCaseDurationMs + _saveAllowanceMs;
    case 'recording':
      currentRunRemainingMs = remaining + _saveAllowanceMs;
    case 'saving':
      currentRunRemainingMs = 0;
    case 'cooling-down':
      currentRunRemainingMs = remaining;
    case 'reloading':
      currentRunRemainingMs = _reloadAllowanceMs ~/ 2;
    default:
      currentRunRemainingMs = 0;
  }

  final isLastCase = index == total - 1;
  final reloadOwed =
      config.reloadBetweenCases && !isLastCase ? _reloadAllowanceMs : 0;

  return math.max(
    0,
    currentRunRemainingMs + futureRunsMs + reloadOwed + futureCasesMs,
  );
}

/// Compact human label:
///   < 60s → "42s left" · < 1h → "9m 12s left" (drops seconds ≥ 10 min)
///   ≥ 1h  → "1h 04m left"
String formatDurationLeft(int ms) {
  final totalSeconds = math.max(0, (ms / 1000).round());
  if (totalSeconds < 60) return '${totalSeconds}s left';
  final totalMinutes = totalSeconds ~/ 60;
  if (totalMinutes < 60) {
    if (totalMinutes >= 10) return '${totalMinutes}m left';
    final seconds = totalSeconds % 60;
    return '${totalMinutes}m ${seconds.toString().padLeft(2, '0')}s left';
  }
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m left';
}
