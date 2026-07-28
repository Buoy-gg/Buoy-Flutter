/// Ports packages/perf-monitor/src/perf-monitor/utils/AutomationRunner.ts.
///
/// Orchestrates a batch of benchmark cases. Each case runs N times
/// (`config.runsPerCase`) so the report can pick a median and show ± stddev:
///
///   for each case:
///     for run in 1..runsPerCase:
///       1. navigate to bounceRoute (forces unmount of the test screen)
///       2. navigate to target with the case's params (retry once on timeout)
///       3. settle for `settleMs`
///       4. record for `perCaseDurationMs`, saved tagged with
///          { batchId, batchIndex, caseId, runIndex }
///       5. cool down for `coolDownMs`
///     filter valid runs, pick median, re-save with isMedianRun = true
///
/// Failure isolation is per-RUN: one timeout doesn't kill the case; the median
/// is computed over whatever non-failed runs remain, and a placeholder report
/// is persisted per failure so the report view still renders a — column.
///
/// **Flutter deviation:** `reloadBetweenCases` is forced off (Dart can't reload
/// its realm), so there is no reload step and no [PendingBatchState] resume
/// path in practice — the bounce-route remount provides per-case isolation.
/// Determinism helpers (mulberry32 + FNV-1a shuffle, median, warmup discard,
/// clamps) are ported 1:1 and parity-tested.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'aggregate.dart';
import 'benchmark_recorder.dart';
import 'benchmark_storage.dart';
import 'compute_median_run.dart';
import 'pending_batch.dart';
import 'perf_route_bridge.dart';
import 'perf_types.dart';
import 'route_validation.dart';

typedef AutomationStatusSubscriber = void Function(AutomationStatus status);

final math.Random _rng = math.Random();

String _makeBatchId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final suffix = String.fromCharCodes([
    for (var i = 0; i < 4; i++) chars.codeUnitAt(_rng.nextInt(chars.length)),
  ]);
  return 'batch-${DateTime.now().millisecondsSinceEpoch}-$suffix';
}

String _makeReportId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final suffix = String.fromCharCodes([
    for (var i = 0; i < 6; i++) chars.codeUnitAt(_rng.nextInt(chars.length)),
  ]);
  return 'bench-${DateTime.now().millisecondsSinceEpoch}-$suffix';
}

String _caseIdFor(String batchId, int batchIndex) =>
    '$batchId::case-$batchIndex';

class AutomationRunnerImpl {
  AutomationStatus _status = AutomationStatus.idle;
  final Set<AutomationStatusSubscriber> _subscribers = {};
  bool _cancelRequested = false;

  /// The route the user was on when the batch started, restored when it ends
  /// so the test doesn't strand them on the last case's screen.
  String? _originRoute;
  void Function()? _inflightCancel;
  Timer? _tickHandle;

  AutomationStatus getStatus() => _status;

  void Function() subscribe(AutomationStatusSubscriber fn) {
    _subscribers.add(fn);
    fn(_status);
    return () => _subscribers.remove(fn);
  }

  bool isRunning() => _status.isActive;

  /// True when a batch can be started — locally that means a router is wired.
  bool canRun() => isNavigationAvailable();

  /// Kick off a batch. Resolves with the final status once the run finishes or
  /// is cancelled. Throws only on programmer error (already running, no cases,
  /// invalid config); per-run failures land in the final `done` status.
  Future<AutomationStatus> start(AutomationConfig config) async {
    if (isRunning()) {
      throw StateError('AutomationRunner is already running.');
    }
    if (config.cases.isEmpty) {
      throw StateError('AutomationConfig has no cases.');
    }
    if (!isNavigationAvailable()) {
      throw StateError(
        'Navigation unavailable — no GoRouter registered with buoy_routes.',
      );
    }

    // Resolve every case up front so we hard-fail with a clear message before
    // doing any navigation work.
    validateConfig(config);

    // Remember where the user was BEFORE the batch navigates anywhere.
    final origin = getCurrentRoute();
    _originRoute = origin.isEmpty ? null : origin;

    final batchId = _makeBatchId();
    // Deterministic shuffle so a resume reconstructs the same order.
    final orderedConfig = applyShuffle(config, batchId);

    return _executeLoop(
      batchId: batchId,
      config: orderedConfig,
      startIndex: 0,
      startRunIndex: 0,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      reportIds: [],
      perCaseReportIds: {},
      failures: [],
      resumeCount: 0,
    );
  }

  /// Continue a batch interrupted by a reload (RN `resume`). Flutter never
  /// reloads mid-batch, but the entry point is kept so a persisted
  /// [PendingBatchState] (e.g. written by an RN device and synced) still runs.
  Future<AutomationStatus> resume(PendingBatchState state) async {
    if (isRunning()) {
      throw StateError('AutomationRunner is already running.');
    }
    if (!isNavigationAvailable()) {
      throw StateError(
        'Navigation unavailable — no GoRouter registered with buoy_routes.',
      );
    }
    if (state.nextIndex >= state.config.cases.length) {
      await clearPendingBatch();
      final done = AutomationStatus(
        phase: 'done',
        batchId: state.batchId,
        reportIds: state.completedReportIds,
        failures: state.failures,
      );
      _setStatus(done);
      return done;
    }

    validateConfig(state.config);

    return _executeLoop(
      batchId: state.batchId,
      config: state.config,
      startIndex: state.nextIndex,
      startRunIndex: state.nextRunIndex ?? 0,
      startedAt: state.startedAt,
      reportIds: [...state.completedReportIds],
      perCaseReportIds: {...?state.perCaseReportIds},
      failures: [...state.failures],
      resumeCount: state.resumeCount,
      isFirstIterAfterReload: true,
    );
  }

  /// Resolve every case's route; throw on a missing route or a bounce clash
  /// (which would mean no remount — the recording would sample the previous
  /// screen, not the case under test).
  void validateConfig(AutomationConfig config) {
    final normalizedBounce = normalizePathname(config.bounceRoute);
    for (var i = 0; i < config.cases.length; i++) {
      final resolved = resolveCaseRoute(config.cases[i], config.targetRoute);
      if (resolved.isEmpty) {
        throw StateError(
          'Case ${i + 1} has no route and AutomationConfig.targetRoute is empty.',
        );
      }
      if (normalizePathname(resolved) == normalizedBounce) {
        throw StateError(
          'Case ${i + 1} route equals bounceRoute ($normalizedBounce); no remount possible.',
        );
      }
    }
  }

  Future<AutomationStatus> _executeLoop({
    required String batchId,
    required AutomationConfig config,
    required int startIndex,
    required int startRunIndex,
    required int startedAt,
    required List<String> reportIds,
    required Map<String, List<String>> perCaseReportIds,
    required List<({int index, String reason})> failures,
    required int resumeCount,
    bool isFirstIterAfterReload = false,
  }) async {
    _cancelRequested = false;
    final total = config.cases.length;
    final runTotal = clampRunsPerCase(config.runsPerCase);
    final coolDownMs = clampCoolDownMs(config.coolDownMs);

    for (var i = startIndex; i < total; i++) {
      if (_cancelRequested) break;

      final testCase = config.cases[i];
      final caseName =
          testCase.name.trim().isNotEmpty ? testCase.name.trim() : 'case ${i + 1}';
      final caseRoute = resolveCaseRoute(testCase, config.targetRoute);
      final caseId = _caseIdFor(batchId, i);

      final innerStart = i == startIndex ? startRunIndex : 0;
      final caseReportIds = <String>[...?perCaseReportIds['$i']];

      for (var runIdx = innerStart; runIdx < runTotal; runIdx++) {
        if (_cancelRequested) break;

        AutomationStatus phase(String name, {int? remainingMs}) =>
            AutomationStatus(
              phase: name,
              index: i,
              total: total,
              caseName: caseName,
              runIndex: runIdx,
              runTotal: runTotal,
              remainingMs: remainingMs,
            );

        // === step 1: bounce ===
        _setStatus(phase('navigating-bounce'));
        try {
          await navigateAndWait(
            expectedPathname: config.bounceRoute,
            pathname: config.bounceRoute,
            timeoutMs: config.navTimeoutMs,
          );
        } catch (err) {
          await _recordRunFailure(
            batchIndex: i,
            runIndex: runIdx,
            caseName: caseName,
            caseId: caseId,
            batchId: batchId,
            caseRoute: caseRoute,
            params: testCase.params,
            reason: 'bounce navigation failed: ${_describeError(err)}',
            failures: failures,
            reportIds: reportIds,
            caseReportIds: caseReportIds,
          );
          continue;
        }
        if (_cancelRequested) break;

        // === step 2: target (single retry on timeout) ===
        _setStatus(phase('navigating-target'));
        final navOutcome = await _navigateToTargetWithRetry(
          caseRoute: caseRoute,
          params: testCase.params,
          timeoutMs: config.navTimeoutMs,
          bounceRoute: config.bounceRoute,
        );
        if (_cancelRequested) break;
        if (!navOutcome.ok) {
          await _recordRunFailure(
            batchIndex: i,
            runIndex: runIdx,
            caseName: caseName,
            caseId: caseId,
            batchId: batchId,
            caseRoute: caseRoute,
            params: testCase.params,
            reason: navOutcome.reason!,
            failures: failures,
            reportIds: reportIds,
            caseReportIds: caseReportIds,
          );
          continue;
        }

        // === step 3: settle ===
        // A cold-boot first run settles slower than a warm in-process bounce;
        // postReloadSettleMs (default 2× settle) covers that.
        final settleMs = isFirstIterAfterReload && runIdx == innerStart
            ? (config.postReloadSettleMs ?? config.settleMs * 2)
            : config.settleMs;
        _setStatus(phase('settling', remainingMs: settleMs));
        await _tickingSleep(
          settleMs,
          (remaining) =>
              _setStatus(phase('settling', remainingMs: remaining)),
        );
        if (_cancelRequested) break;

        // === step 4: record ===
        _setStatus(phase('recording', remainingMs: config.perCaseDurationMs));
        final savedReport = await _runOneRecording(
          caseName: caseName,
          batchId: batchId,
          batchIndex: i,
          caseId: caseId,
          runIndex: runIdx,
          retriedOnce: navOutcome.retried,
          params: testCase.params,
          targetRoute: caseRoute,
          durationMs: config.perCaseDurationMs,
          onTick: (remaining) =>
              _setStatus(phase('recording', remainingMs: remaining)),
        );

        if (_cancelRequested && savedReport == null) break;

        // === step 5: book-keep ===
        _setStatus(phase('saving'));
        if (savedReport != null) {
          reportIds.add(savedReport.id);
          caseReportIds.add(savedReport.id);
        } else {
          await _recordRunFailure(
            batchIndex: i,
            runIndex: runIdx,
            caseName: caseName,
            caseId: caseId,
            batchId: batchId,
            caseRoute: caseRoute,
            params: testCase.params,
            reason: 'recording produced no samples',
            failures: failures,
            reportIds: reportIds,
            caseReportIds: caseReportIds,
          );
        }

        // === step 6: cool down between runs/cases ===
        final isLastRunInLastCase = runIdx == runTotal - 1 && i == total - 1;
        if (!_cancelRequested && coolDownMs > 0 && !isLastRunInLastCase) {
          _setStatus(phase('cooling-down', remainingMs: coolDownMs));
          await _tickingSleep(
            coolDownMs,
            (remaining) =>
                _setStatus(phase('cooling-down', remainingMs: remaining)),
          );
        }
      }

      // The cold-boot bonus is spent after the first case's run loop.
      isFirstIterAfterReload = false;
      perCaseReportIds['$i'] = caseReportIds;

      if (_cancelRequested) break;

      // === step 7: pick median + tag it ===
      await _tagMedianForCase(
        caseReportIds: caseReportIds,
        warmupToDiscard:
            clampDiscardWarmup(config.discardWarmupRuns, runTotal),
      );

      // === step 8: reload between cases ===
      // Flutter can't reload its realm, so this step is intentionally absent
      // (config.reloadBetweenCases is sanitized to false). See the library doc.
    }

    await clearPendingBatch();

    // Send the user back to the screen they started from (best-effort).
    await _restoreOrigin();

    if (_cancelRequested) {
      final cancelled = AutomationStatus(phase: 'cancelled', batchId: batchId);
      _setStatus(cancelled);
      _cancelRequested = false;
      return cancelled;
    }

    final done = AutomationStatus(
      phase: 'done',
      batchId: batchId,
      reportIds: reportIds,
      failures: failures,
    );
    _setStatus(done);
    return done;
  }

  /// Navigate back to the origin route. Best-effort — a failure to return home
  /// must never fail a batch that already produced its reports.
  Future<void> _restoreOrigin() async {
    final origin = _originRoute;
    _originRoute = null;
    if (origin == null || origin.isEmpty) return;
    try {
      await navigateAndWait(
        expectedPathname: origin,
        pathname: origin,
        timeoutMs: 3000,
      );
    } catch (_) {
      // Best-effort.
    }
  }

  Future<({bool ok, bool retried, String? reason})> _navigateToTargetWithRetry({
    required String caseRoute,
    required Map<String, String> params,
    required int timeoutMs,
    required String bounceRoute,
  }) async {
    Future<({String kind, Object? err})> attempt() async {
      try {
        final result = await navigateAndWait(
          expectedPathname: caseRoute,
          pathname: caseRoute,
          params: params,
          timeoutMs: timeoutMs,
        );
        return result.timedOut
            ? (kind: 'timeout', err: null)
            : (kind: 'ok', err: null);
      } catch (err) {
        return (kind: 'error', err: err);
      }
    }

    final first = await attempt();
    if (first.kind == 'ok') return (ok: true, retried: false, reason: null);
    if (first.kind == 'error') {
      return (
        ok: false,
        retried: false,
        reason: 'target navigation failed: ${_describeError(first.err)}',
      );
    }

    // Timeout — retry once. Bounce again first in case the previous attempt
    // left the router in a half-mounted limbo.
    if (_cancelRequested) {
      return (ok: false, retried: false, reason: 'cancelled before retry');
    }
    try {
      await navigateAndWait(
        expectedPathname: bounceRoute,
        pathname: bounceRoute,
        timeoutMs: timeoutMs,
      );
    } catch (_) {
      // Bounce failed — try the target anyway.
    }
    if (_cancelRequested) {
      return (ok: false, retried: false, reason: 'cancelled before retry');
    }
    final second = await attempt();
    if (second.kind == 'ok') return (ok: true, retried: true, reason: null);
    if (second.kind == 'error') {
      return (
        ok: false,
        retried: true,
        reason:
            'target navigation failed on retry: ${_describeError(second.err)}',
      );
    }
    return (
      ok: false,
      retried: true,
      reason:
          'target navigation timeout — the route observer never reported the new pathname (retried once)',
    );
  }

  /// Load the case's runs and stamp the median one with `isMedianRun: true`.
  /// Skips silently when zero valid runs exist.
  Future<void> _tagMedianForCase({
    required List<String> caseReportIds,
    required int warmupToDiscard,
  }) async {
    if (caseReportIds.isEmpty) return;

    final reports = <BenchmarkReport>[];
    for (final id in caseReportIds) {
      final r = await BenchmarkStorage.load(id);
      if (r != null) reports.add(r);
    }
    // Honour run order — earliest runs are runIndex 0,1,…
    reports.sort(
      (a, b) => (a.metadata.runIndex ?? 0).compareTo(b.metadata.runIndex ?? 0),
    );
    final candidatePool = warmupToDiscard > 0 && warmupToDiscard < reports.length
        ? reports.sublist(warmupToDiscard)
        : (warmupToDiscard > 0 ? <BenchmarkReport>[] : reports);
    final valid = filterToValidRuns(candidatePool);
    if (valid.isEmpty) return;

    final median = computeMedianRun(valid);
    if (median.metadata.isMedianRun == true) return;

    await BenchmarkStorage.save(
      median.copyWith(metadata: median.metadata.copyWith(isMedianRun: true)),
    );
  }

  /// Request cancellation. The in-flight recording aborts, in-flight sleeps
  /// resolve immediately, and subsequent runs/cases are skipped.
  void cancel() {
    if (!isRunning()) return;
    _cancelRequested = true;
    _inflightCancel?.call();
    _inflightCancel = null;
    unawaited(clearPendingBatch());
  }

  /// Reset a finished/cancelled batch to idle so the next one starts fresh.
  void acknowledge() {
    if (_status.phase == 'done' || _status.phase == 'cancelled') {
      _setStatus(AutomationStatus.idle);
    }
  }

  // ── internals ────────────────────────────────────────────────────────────

  void _setStatus(AutomationStatus next) {
    _status = next;
    for (final fn in [..._subscribers]) {
      try {
        fn(next);
      } catch (_) {
        // swallow
      }
    }
  }

  Future<void> _tickingSleep(
    int totalMs,
    void Function(int remainingMs) onTick,
  ) async {
    final end = DateTime.now().millisecondsSinceEpoch + totalMs;
    const interval = 100;
    while (true) {
      if (_cancelRequested) return;
      final remaining = end - DateTime.now().millisecondsSinceEpoch;
      if (remaining <= 0) return;
      onTick(remaining);
      await sleep(math.min(interval, remaining));
    }
  }

  Future<BenchmarkReport?> _runOneRecording({
    required String caseName,
    required String batchId,
    required int batchIndex,
    required String caseId,
    required int runIndex,
    required bool retriedOnce,
    required Map<String, String> params,
    required String targetRoute,
    required int durationMs,
    required void Function(int remainingMs) onTick,
  }) async {
    if (benchmarkRecorder.isRecording()) {
      // A manual recording is already in flight — don't trample it.
      return null;
    }

    final settled = Completer<BenchmarkReport?>();
    void resolveSaved(BenchmarkReport? report) {
      if (!settled.isCompleted) settled.complete(report);
    }

    final unsubscribe = benchmarkRecorder.subscribeSaved((report) {
      if (report.metadata.batchId != batchId) return;
      if (report.metadata.batchIndex != batchIndex) return;
      if (report.metadata.runIndex != runIndex) return;
      resolveSaved(report);
    });

    final cancelRecording = benchmarkRecorder.startQuick(
      BenchmarkMetadata(
        name: caseName,
        route: targetRoute,
        source: 'batch',
        batchId: batchId,
        batchIndex: batchIndex,
        caseId: caseId,
        runIndex: runIndex,
        retriedOnce: retriedOnce ? true : null,
        params: params,
      ),
      durationMs,
    );

    final start = DateTime.now().millisecondsSinceEpoch;
    _inflightCancel = () {
      cancelRecording();
      resolveSaved(null);
    };

    _tickHandle?.cancel();
    _tickHandle = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final remaining = math.max(
        0,
        durationMs - (DateTime.now().millisecondsSinceEpoch - start),
      );
      onTick(remaining);
      if (remaining <= 0) {
        timer.cancel();
        if (identical(_tickHandle, timer)) _tickHandle = null;
      }
    });

    // Backstop: a recording that captured zero samples never fires
    // subscribeSaved, and without this the runner would hang forever.
    final fallback = Timer(
      Duration(milliseconds: durationMs + 3000),
      () => resolveSaved(null),
    );

    try {
      return await settled.future;
    } finally {
      fallback.cancel();
      unsubscribe();
      _tickHandle?.cancel();
      _tickHandle = null;
      _inflightCancel = null;
    }
  }

  /// Persist a placeholder report for a failed run so the report view still
  /// shows a column for the case, and the run count stays stable for median
  /// selection.
  Future<void> _recordRunFailure({
    required int batchIndex,
    required int runIndex,
    required String caseName,
    required String caseId,
    required String batchId,
    required String caseRoute,
    required Map<String, String> params,
    required String reason,
    required List<({int index, String reason})> failures,
    required List<String> reportIds,
    required List<String> caseReportIds,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[perf-monitor] batch case "$caseName" run ${runIndex + 1} failed: $reason',
      );
    }
    failures.add((index: batchIndex, reason: reason));

    final placeholder = BenchmarkReport(
      id: _makeReportId(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      metadata: BenchmarkMetadata(
        name: caseName,
        route: caseRoute,
        source: 'batch',
        batchId: batchId,
        batchIndex: batchIndex,
        caseId: caseId,
        runIndex: runIndex,
        batchFailureReason: reason,
        params: params,
      ),
      samples: const [],
      markers: const [],
      stats: aggregateSamples(const []),
    );

    await BenchmarkStorage.save(placeholder);
    reportIds.add(placeholder.id);
    caseReportIds.add(placeholder.id);
  }
}

String _describeError(Object? err) {
  if (err == null) return 'unknown error';
  if (err is StateError) return err.message;
  return '$err';
}

int clampRunsPerCase(int? raw) {
  if (raw == null) return 3;
  return math.min(10, math.max(1, raw));
}

int clampCoolDownMs(int? raw) {
  if (raw == null) return 2000;
  return math.min(30000, math.max(0, raw));
}

int clampDiscardWarmup(int? raw, int runsPerCase) {
  if (raw == null) return 0;
  final rounded = math.max(0, raw);
  // Discarding everything would leave zero candidates — clamp so at least one
  // run can become the median.
  return math.min(rounded, math.max(0, runsPerCase - 1));
}

// ─── Deterministic case shuffle ──────────────────────────────────────────

/// Fisher-Yates seeded by batchId (mulberry32) so a resume reproduces the
/// order. Pure — same (length, seed) always returns the same indices.
List<int> shuffleIndices(int length, int seed) {
  final out = [for (var i = 0; i < length; i++) i];
  var rng = seed & 0xFFFFFFFF;
  double next() {
    rng = (rng + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = rng;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296;
  }

  for (var i = length - 1; i > 0; i--) {
    final j = (next() * (i + 1)).floor();
    final tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/// 32-bit signed-multiply-and-truncate (JS `Math.imul`).
int _imul(int a, int b) {
  final aHi = (a >>> 16) & 0xFFFF;
  final aLo = a & 0xFFFF;
  final bHi = (b >>> 16) & 0xFFFF;
  final bLo = b & 0xFFFF;
  return (aLo * bLo + (((aHi * bLo + aLo * bHi) << 16) & 0xFFFFFFFF)) &
      0xFFFFFFFF;
}

/// FNV-1a string hash → 32-bit unsigned; derives the shuffle seed from the
/// batchId so the order is deterministic per batch.
int hashStringToU32(String s) {
  var h = 2166136261;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = _imul(h, 16777619);
  }
  return h & 0xFFFFFFFF;
}

/// Apply `config.shuffleCases` deterministically. Same batchId → same order.
AutomationConfig applyShuffle(AutomationConfig config, String batchId) {
  if (!config.shuffleCases || config.cases.length <= 1) return config;
  final order = shuffleIndices(config.cases.length, hashStringToU32(batchId));
  return config.copyWith(cases: [for (final i in order) config.cases[i]]);
}

/// Singleton (RN `AutomationRunner`).
final AutomationRunnerImpl automationRunner = AutomationRunnerImpl();
