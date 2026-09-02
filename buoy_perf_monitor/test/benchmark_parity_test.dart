/// Parity tests for the B2/B3 pure logic — median selection, case labels, the
/// bulk-paste parser, route validation, library folding, batch-time estimates,
/// the deterministic shuffle, config sanitization, and the wire shapes the
/// desktop/MCP consume. Expected values are hand-derived from the RN sources
/// (packages/perf-monitor/src/perf-monitor/utils/*).
library;

import 'package:buoy_perf_monitor/buoy_perf_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

PerfSample _sample(int t, double js, double ui, double cpu, double mem) =>
    PerfSample(
      timestamp: t,
      jsFps: js,
      uiFps: ui,
      cpuUsage: cpu,
      memoryUsage: mem,
      deviceMaxRefreshRate: 60,
    );

BenchmarkReport _report({
  required String id,
  required double jsAvg,
  required double uiAvg,
  int jsJank = 0,
  int runIndex = 0,
  String? failure,
  String name = 'case',
  String? caseId,
  String? route,
  Map<String, String>? params,
  bool? isMedianRun,
  int createdAt = 0,
  double memMax = 100,
}) {
  return BenchmarkReport(
    id: id,
    createdAt: createdAt,
    metadata: BenchmarkMetadata(
      name: name,
      route: route,
      source: 'batch',
      batchId: 'b1',
      batchIndex: 0,
      caseId: caseId,
      runIndex: runIndex,
      batchFailureReason: failure,
      params: params,
      isMedianRun: isMedianRun,
    ),
    samples: failure == null ? [_sample(0, jsAvg, uiAvg, 10, memMax)] : const [],
    stats: PerfStatsAggregate(
      sampleCount: failure == null ? 1 : 0,
      durationMs: 1000,
      jsFps: AggregateChannel(min: jsAvg, max: jsAvg, avg: jsAvg, p95: jsAvg),
      uiFps: AggregateChannel(min: uiAvg, max: uiAvg, avg: uiAvg, p95: uiAvg),
      cpuUsage: const AggregateChannel(min: 10, max: 10, avg: 10, p95: 10),
      memoryUsage:
          AggregateChannel(min: memMax, max: memMax, avg: memMax, p95: memMax),
      jsJankFrames: jsJank,
      uiJankFrames: 0,
      deviceMaxRefreshRate: 60,
    ),
  );
}

void main() {
  group('computeMedianRun.ts parity', () {
    test('filterToValidRuns drops failed + zero-sample runs, keeps order', () {
      final runs = [
        _report(id: 'a', jsAvg: 60, uiAvg: 60),
        _report(id: 'b', jsAvg: 0, uiAvg: 0, failure: 'nav timeout'),
        _report(id: 'c', jsAvg: 55, uiAvg: 58),
      ];
      expect(
        filterToValidRuns(runs).map((r) => r.id).toList(),
        ['a', 'c'],
      );
    });

    test('picks the run closest to the (median js, median ui) point', () {
      // medians over [50,55,60] = 55 on both axes → the middle run wins.
      final runs = [
        _report(id: 'lo', jsAvg: 50, uiAvg: 50),
        _report(id: 'mid', jsAvg: 55, uiAvg: 55),
        _report(id: 'hi', jsAvg: 60, uiAvg: 60),
      ];
      expect(computeMedianRun(runs).id, 'mid');
    });

    test('ties break toward fewer JS jank frames, order-independently', () {
      // Even N → the median is interpolated, so both runs sit exactly the same
      // distance from it; the smoother one must win either way.
      final runs = [
        _report(id: 'janky', jsAvg: 50, uiAvg: 50, jsJank: 9),
        _report(id: 'smooth', jsAvg: 60, uiAvg: 60, jsJank: 1),
      ];
      expect(computeMedianRun(runs).id, 'smooth');
      expect(computeMedianRun(runs.reversed.toList()).id, 'smooth');
    });

    test('single run passes through; empty throws', () {
      final one = _report(id: 'only', jsAvg: 42, uiAvg: 42);
      expect(computeMedianRun([one]).id, 'only');
      expect(() => computeMedianRun([]), throwsArgumentError);
    });

    test('computeRunSpread uses SAMPLE stddev (÷ N-1)', () {
      final runs = [
        _report(id: 'a', jsAvg: 50, uiAvg: 60),
        _report(id: 'b', jsAvg: 60, uiAvg: 60),
      ];
      final spread = computeRunSpread(runs);
      expect(spread.jsFps.mean, 55);
      // sample stddev of [50,60] = sqrt(((5^2)+(5^2))/1) = sqrt(50) ≈ 7.071
      expect(spread.jsFps.stddev, closeTo(7.0710678, 1e-6));
      // No variance on the UI axis.
      expect(spread.uiFps.stddev, 0);
    });
  });

  group('computeCaseLabels.ts parity', () {
    test('unique names short-circuit — labels are the names, no constants', () {
      final result = computeCaseLabels(const [
        CaseLabelInput(name: 'baseline', params: {'v': '1'}),
        CaseLabelInput(name: 'v2', params: {'v': '2'}),
      ]);
      expect(result.labels, ['baseline', 'v2']);
      expect(result.constantParams, isEmpty);
    });

    test('colliding names → constant params hoisted, differing ones labelled',
        () {
      final result = computeCaseLabels(const [
        CaseLabelInput(name: '/perf', params: {'mode': 'grid', 'cards': '5'}),
        CaseLabelInput(name: '/perf', params: {'mode': 'grid', 'cards': '20'}),
      ]);
      expect(result.constantParams, {'mode': 'grid'});
      expect(result.labels, ['cards=5', 'cards=20']);
    });

    test('identical colliding cases fall back to "<name> #n"', () {
      final result = computeCaseLabels(const [
        CaseLabelInput(name: 'same'),
        CaseLabelInput(name: 'same'),
      ]);
      expect(result.labels, ['same #1', 'same #2']);
    });

    test('route is a synthetic dimension, reported as "route"', () {
      final result = computeCaseLabels(const [
        CaseLabelInput(name: 'x', route: '/a'),
        CaseLabelInput(name: 'x', route: '/b'),
      ]);
      expect(result.labels, ['route=/a', 'route=/b']);
    });

    test('formatParams sorts keys', () {
      expect(formatParams({'b': '2', 'a': '1'}), 'a=1, b=2');
      expect(formatParams(const {}), '');
    });
  });

  group('parseAutomationCases.ts parity', () {
    test('line format: bare name + colon params, kept because one has signal',
        () {
      final result = parseAutomationCases('baseline\nv2: renderer=v2, cards=5');
      expect(result.cases.length, 2);
      expect(result.cases[0].name, 'baseline');
      expect(result.cases[0].params, isEmpty);
      expect(result.cases[1].params, {'renderer': 'v2', 'cards': '5'});
    });

    test('a paste of ONLY bare names is dropped (clipboard junk guard)', () {
      final result = parseAutomationCases('A\nB\nC');
      expect(result.cases, isEmpty);
    });

    test('URL lines capture pathname + query, auto-named from params', () {
      final result = parseAutomationCases('/pokemon?renderer=v2&cards=5');
      expect(result.cases.single.route, '/pokemon');
      expect(result.cases.single.params, {'renderer': 'v2', 'cards': '5'});
      expect(result.cases.single.name, 'cards=5, renderer=v2');
    });

    test('JSON array round-trips through serializeAutomationCases', () {
      final parsed = parseAutomationCases(
        '[{"name":"baseline"},{"name":"v2","params":{"renderer":"v2"}}]',
      );
      expect(parsed.cases.length, 2);
      final json = serializeAutomationCases(parsed.cases);
      final reparsed = parseAutomationCases(json);
      expect(reparsed.cases.map((c) => c.name).toList(), ['baseline', 'v2']);
      expect(reparsed.cases[1].params, {'renderer': 'v2'});
    });

    test('all-empty query values are rejected as a report-dump fragment', () {
      final result = parseAutomationCases('case?route=&count=&engine=');
      expect(result.cases, isEmpty);
      expect(result.errors.single.reason, contains('report-dump fragment'));
    });

    test('wrapped URL fragments are re-joined onto the previous URL', () {
      final result = parseAutomationCases('/perf?a=1&renderSc\nale=1.0');
      expect(result.cases.length, 1);
      expect(result.cases.single.params, {'a': '1', 'renderScale': '1.0'});
    });

    test('URL lines auto-name from their full param set (no collision)', () {
      final result = parseAutomationCases(
        '/perf?mode=grid&cards=5\n/perf?mode=grid&cards=20',
      );
      expect(result.cases.map((c) => c.name).toList(),
          ['cards=5, mode=grid', 'cards=20, mode=grid']);
    });

    test('explicitly colliding names ARE disambiguated by differing params',
        () {
      final result = parseAutomationCases(
        '[{"name":"perf","params":{"mode":"grid","cards":"5"}},'
        '{"name":"perf","params":{"mode":"grid","cards":"20"}}]',
      );
      expect(result.cases.map((c) => c.name).toList(), ['cards=5', 'cards=20']);
    });

    test('filterImportableCases drops routes absent from a loaded sitemap', () {
      final parsed = parseAutomationCases('/pokemon?v=1\n/apps?v=2');
      final gated =
          filterImportableCases(parsed.cases, '', const ['/pokemon', '/']);
      expect(gated.importable.length, 1);
      expect(gated.importable.single.route, '/pokemon');
      expect(gated.droppedUnknown, 1);
    });

    test('no sitemap → nothing is gated (validation skipped)', () {
      final parsed = parseAutomationCases('/anything?v=1');
      final gated = filterImportableCases(parsed.cases, '', const []);
      expect(gated.importable.length, 1);
      expect(gated.droppedUnknown, 0);
    });
  });

  group('routeValidation.ts parity', () {
    test('parseRouteInput strips scheme/host + hash, splits query', () {
      final parsed = parseRouteInput('https://x.dev/a//b?k=v#frag');
      expect(parsed!.pathname, '/a/b');
      expect(parsed.search, 'k=v');
      expect(parseRouteInput('not-a-route'), isNull);
    });

    test('normalizePathname strips groups + trailing slash', () {
      expect(normalizePathname('/(tabs)/home/'), '/home');
      expect(normalizePathname('/'), '/');
      expect(normalizePathname('//a//b'), '/a/b');
    });

    test('sitemap patterns: [id], [...rest], and go_router :id', () {
      expect(validateRouteAgainstSitemap('/users/42', const ['/users/[id]']),
          'valid');
      expect(validateRouteAgainstSitemap('/users/42', const ['/users/:id']),
          'valid');
      expect(validateRouteAgainstSitemap('/a/b/c', const ['/a/[...rest]']),
          'valid');
      expect(validateRouteAgainstSitemap('/nope', const ['/users/[id]']),
          'unknown');
      expect(validateRouteAgainstSitemap('/anything', const []), 'skipped');
    });

    test('resolveCaseRoute: own route wins, target fills the gap', () {
      final own = AutomationCase(id: '1', name: 'x', route: '/own');
      final none = AutomationCase(id: '2', name: 'y');
      expect(resolveCaseRoute(own, '/target'), '/own');
      expect(resolveCaseRoute(none, '/target'), '/target');
      expect(resolveCaseRoute(none, ''), '');
    });

    test('pathnameMatches tolerates patterns + trailing slashes', () {
      expect(pathnameMatches('/users/7/', '/users/[id]'), isTrue);
      expect(pathnameMatches('/home', '/(tabs)/home'), isTrue);
      expect(pathnameMatches('/home', '/other'), isFalse);
    });
  });

  group('aggregateLibrary.ts parity', () {
    test('solos pass through; batch children collapse to a worst-of summary',
        () {
      final items = aggregateLibrary([
        const BenchmarkIndexEntry(
          id: 'solo',
          createdAt: 300,
          name: 'manual run',
        ),
        const BenchmarkIndexEntry(
          id: 'r1',
          createdAt: 100,
          name: 'baseline',
          batchId: 'b1',
          batchIndex: 0,
          jsFpsAvg: 60,
          uiFpsAvg: 58,
          cpuAvg: 20,
          memMaxMb: 400,
          jsJankFrames: 1,
          uiJankFrames: 0,
          sampleCount: 20,
          durationMs: 5000,
          params: {'v': '1'},
        ),
        const BenchmarkIndexEntry(
          id: 'r2',
          createdAt: 200,
          name: 'v2',
          batchId: 'b1',
          batchIndex: 1,
          jsFpsAvg: 40,
          uiFpsAvg: 30,
          cpuAvg: 55,
          memMaxMb: 700,
          jsJankFrames: 4,
          uiJankFrames: 2,
          sampleCount: 20,
          durationMs: 5000,
          params: {'v': '2'},
        ),
      ]);

      expect(items.length, 2);
      // Newest-first: the solo (300) outranks the batch (earliest child = 100).
      expect(items.first.isBatch, isFalse);
      final batch = items[1];
      expect(batch.isBatch, isTrue);
      expect(batch.caseCount, 2);
      expect(batch.createdAt, 100);
      // Worst-of: min FPS, max CPU/MEM, summed jank + duration + samples.
      expect(batch.jsFpsAvg, 40);
      expect(batch.uiFpsAvg, 30);
      expect(batch.cpuAvg, 55);
      expect(batch.memMaxMb, 700);
      expect(batch.jsJankFrames, 5);
      expect(batch.uiJankFrames, 2);
      expect(batch.sampleCount, 40);
      // Pivot = the param key whose value varies.
      expect(batch.pivotKey, 'v');
      expect(batch.pivotValueCount, 2);
      expect(batch.baselineName, 'baseline');
    });

    test('failed children are excluded from the worst-of snapshot', () {
      final items = aggregateLibrary([
        const BenchmarkIndexEntry(
          id: 'ok',
          createdAt: 1,
          name: 'ok',
          batchId: 'b',
          batchIndex: 0,
          jsFpsAvg: 59,
          sampleCount: 10,
        ),
        const BenchmarkIndexEntry(
          id: 'bad',
          createdAt: 2,
          name: 'bad',
          batchId: 'b',
          batchIndex: 1,
          jsFpsAvg: 0,
          sampleCount: 0,
          batchFailureReason: 'nav timeout',
        ),
      ]);
      expect(items.single.failureCount, 1);
      expect(items.single.jsFpsAvg, 59, reason: 'the 0 from the failure is out');
    });
  });

  group('batchTimeEstimate.ts parity', () {
    final config = defaultAutomationConfig().copyWith(
      perCaseDurationMs: 5000,
      settleMs: 600,
      coolDownMs: 3000,
      runsPerCase: 3,
      cases: [
        AutomationCase(id: '1', name: 'a'),
        AutomationCase(id: '2', name: 'b'),
      ],
    );

    test('per-run = nav 2000 + settle + duration + save 200', () {
      expect(perRunEstimateMs(config), 2000 + 600 + 5000 + 200);
    });

    test('per-case = N runs + (N-1) cooldowns', () {
      expect(perCaseEstimateMs(config), 3 * 7800 + 2 * 3000);
    });

    test('total adds one inter-case cooldown per adjacent pair', () {
      expect(totalBatchEstimateMs(config), 2 * 29400 + 3000);
      expect(totalBatchEstimateMs(config.copyWith(cases: const [])), 0);
    });

    test('remaining is null for terminal phases, live mid-recording', () {
      expect(batchRemainingMs(AutomationStatus.idle, config), isNull);
      expect(
        batchRemainingMs(
          const AutomationStatus(phase: 'done', batchId: 'b'),
          config,
        ),
        isNull,
      );
      final mid = batchRemainingMs(
        const AutomationStatus(
          phase: 'recording',
          index: 1,
          total: 2,
          caseName: 'b',
          runIndex: 2,
          runTotal: 3,
          remainingMs: 1000,
        ),
        config,
      );
      // Last run of the last case → only this run's remainder + the save buffer.
      expect(mid, 1200);
    });

    test('formatDurationLeft granularity buckets', () {
      expect(formatDurationLeft(42000), '42s left');
      expect(formatDurationLeft(552000), '9m 12s left');
      expect(formatDurationLeft(600000), '10m left');
      expect(formatDurationLeft(3840000), '1h 04m left');
    });
  });

  group('AutomationRunner determinism helpers', () {
    test('shuffleIndices is a permutation and stable for a seed', () {
      final a = shuffleIndices(8, hashStringToU32('batch-123-abcd'));
      final b = shuffleIndices(8, hashStringToU32('batch-123-abcd'));
      expect(a, b);
      expect(a.toSet(), {0, 1, 2, 3, 4, 5, 6, 7});
    });

    test('different batch ids produce different orders', () {
      final a = shuffleIndices(8, hashStringToU32('batch-a'));
      final b = shuffleIndices(8, hashStringToU32('batch-b'));
      expect(a, isNot(b));
    });

    test('applyShuffle is a no-op when off or with a single case', () {
      final cases = [
        AutomationCase(id: '1', name: 'a'),
        AutomationCase(id: '2', name: 'b'),
      ];
      final off = defaultAutomationConfig()
          .copyWith(cases: cases, shuffleCases: false);
      expect(applyShuffle(off, 'batch-x').cases.map((c) => c.id).toList(),
          ['1', '2']);
      final one = defaultAutomationConfig()
          .copyWith(cases: [cases.first], shuffleCases: true);
      expect(applyShuffle(one, 'batch-x').cases.length, 1);
    });

    test('withBatchWarmup prepends one unrecorded run of the first case', () {
      final cases = [
        AutomationCase(id: '1', name: 'a', route: '/a'),
        AutomationCase(id: '2', name: 'b'),
      ];
      final on = defaultAutomationConfig().copyWith(cases: cases);
      expect(on.discardWarmupCase, isTrue, reason: 'RN default');
      final warmed = withBatchWarmup(on);
      expect(warmed.cases.length, 3);
      expect(warmed.cases.first.name, warmupCaseName);
      expect(warmed.cases.first.route, '/a');
      expect(isWarmupRun(warmed.cases.first.name), isTrue);

      final off = on.copyWith(discardWarmupCase: false);
      expect(withBatchWarmup(off).cases.length, 2);

      // And the aggregate never counts it.
      final items = aggregateLibrary([
        const BenchmarkIndexEntry(
          id: 'w',
          createdAt: 50,
          name: warmupCaseName,
          batchId: 'b9',
          batchIndex: 0,
        ),
        const BenchmarkIndexEntry(
          id: 'r',
          createdAt: 100,
          name: 'a',
          batchId: 'b9',
          batchIndex: 1,
        ),
      ]);
      expect(items.length, 1);
      expect(items.single.childIds, ['r']);
    });

    test('clamps mirror RN (runs 1-10, cooldown 0-30s, warmup < runs)', () {
      expect(clampRunsPerCase(99), 10);
      expect(clampRunsPerCase(0), 1);
      expect(clampRunsPerCase(null), 3);
      expect(clampCoolDownMs(99999), 30000);
      expect(clampCoolDownMs(-5), 0);
      // Discarding everything would leave no median candidate.
      expect(clampDiscardWarmup(5, 3), 2);
      expect(clampDiscardWarmup(null, 3), 0);
    });
  });

  group('automationSettings.ts parity', () {
    test('sanitize clamps ranges and keeps the Flutter reload deviation', () {
      final config = sanitizeAutomationConfig({
        'targetRoute': '/perf',
        'bounceRoute': '',
        'perCaseDurationMs': 999999,
        'settleMs': -10,
        'navTimeoutMs': 1,
        'runsPerCase': 99,
        'coolDownMs': 99999,
        'discardWarmupRuns': 99,
        // Even an explicit true is forced off — Dart can't reload its realm.
        'reloadBetweenCases': true,
        'reloadStrategy': 'nonsense',
        'cases': [
          {'name': 'a', 'params': {'k': 1}, 'route': '/x'},
          'junk',
        ],
      });
      expect(config.targetRoute, '/perf');
      expect(config.bounceRoute, '/', reason: 'empty falls back to default');
      expect(config.perCaseDurationMs, 120000);
      expect(config.settleMs, 0);
      expect(config.navTimeoutMs, 500);
      expect(config.runsPerCase, 10);
      expect(config.coolDownMs, 30000);
      expect(config.discardWarmupRuns, 9);
      expect(config.reloadBetweenCases, isFalse);
      expect(config.reloadStrategy, 'auto');
      expect(config.cases.length, 1);
      expect(config.cases.single.params, {'k': '1'});
      expect(config.cases.single.route, '/x');
    });

    test('speed presets apply + detect, and hand-edits clear the match', () {
      final base = defaultAutomationConfig();
      final fast = applySpeedPreset(base, AutomationSpeedPreset.fast);
      expect(detectSpeedPreset(fast), AutomationSpeedPreset.fast);
      expect(fast.coolDownMs, 3000);
      final slow = applySpeedPreset(base, AutomationSpeedPreset.slow);
      expect(detectSpeedPreset(slow), AutomationSpeedPreset.slow);
      expect(slow.coolDownMs, 20000);
      expect(detectSpeedPreset(slow.copyWith(coolDownMs: 4321)), isNull);
    });

    test('cloneCasesWithNewIds deep-copies params with fresh ids', () {
      final original = AutomationCase(
        id: 'orig',
        name: 'a',
        params: {'k': 'v'},
        route: '/x',
      );
      final clone = cloneCasesWithNewIds([original]).single;
      expect(clone.id, isNot('orig'));
      expect(clone.params, {'k': 'v'});
      expect(clone.route, '/x');
      clone.params['k'] = 'changed';
      expect(original.params['k'], 'v');
    });
  });

  group('wire shapes the desktop + MCP read', () {
    test('IndexEntry carries every ranking field, omitting absent optionals',
        () {
      final entry = BenchmarkIndexEntry.fromReport(
        _report(
          id: 'bench-1',
          jsAvg: 58,
          uiAvg: 55,
          jsJank: 2,
          caseId: 'b1::case-0',
          route: '/perf',
          params: {'v': '2'},
          isMedianRun: true,
          createdAt: 1234,
          memMax: 512,
        ),
      );
      final json = entry.toJson();
      expect(json['id'], 'bench-1');
      expect(json['createdAt'], 1234);
      expect(json['jsFpsAvg'], 58);
      expect(json['uiFpsAvg'], 55);
      expect(json['cpuAvg'], 10);
      expect(json['memMaxMb'], 512);
      expect(json['jsJankFrames'], 2);
      expect(json['uiJankFrames'], 0);
      expect(json['deviceMaxRefreshRate'], 60);
      expect(json['source'], 'batch');
      expect(json['batchId'], 'b1');
      expect(json['batchIndex'], 0);
      expect(json['caseId'], 'b1::case-0');
      expect(json['runIndex'], 0);
      expect(json['isMedianRun'], true);
      expect(json['params'], {'v': '2'});
      expect(json.containsKey('batchFailureReason'), isFalse);
      // v1 omits the RN render-capture mirrors entirely.
      expect(json.containsKey('renderCommits'), isFalse);
      expect(json.containsKey('topRenderers'), isFalse);
    });

    test('BenchmarkReport survives a JSON round-trip', () {
      final report = _report(
        id: 'bench-x',
        jsAvg: 59.5,
        uiAvg: 57.25,
        route: '/perf',
        params: {'a': '1'},
      );
      final back = BenchmarkReport.fromJson(report.toJson())!;
      expect(back.id, 'bench-x');
      expect(back.metadata.route, '/perf');
      expect(back.metadata.params, {'a': '1'});
      expect(back.stats.jsFps.avg, 59.5);
      expect(back.samples.single.uiFps, 57.25);
      expect(BenchmarkReport.fromJson({'no': 'id'}), isNull);
    });

    test('automationConfig snapshot omits cases (RN adapter parity)', () {
      final json = defaultAutomationConfig()
          .copyWith(cases: [AutomationCase(id: '1', name: 'a')])
          .toJson(includeCases: false);
      expect(json.containsKey('cases'), isFalse);
      expect(json['runsPerCase'], 3);
      expect(json['coolDownMs'], 8000);
      expect(json['reloadBetweenCases'], false);
    });

    test('AutomationStatus serializes the RN phase union + active payload', () {
      expect(AutomationStatus.idle.toJson(), {'phase': 'idle'});
      const recording = AutomationStatus(
        phase: 'recording',
        index: 0,
        total: 2,
        caseName: 'baseline',
        runIndex: 1,
        runTotal: 3,
        remainingMs: 2500,
      );
      expect(recording.toJson(), {
        'phase': 'recording',
        'index': 0,
        'total': 2,
        'caseName': 'baseline',
        'runIndex': 1,
        'runTotal': 3,
        'remainingMs': 2500,
      });
      expect(recording.isActive, isTrue);
      const done = AutomationStatus(
        phase: 'done',
        batchId: 'b1',
        reportIds: ['r1'],
        failures: [(index: 0, reason: 'nav timeout')],
      );
      expect(done.isActive, isFalse);
      expect(done.toJson()['failures'], [
        {'index': 0, 'reason': 'nav timeout'},
      ]);
    });

    test('PersistedModalView sanitizer rejects unusable shapes', () {
      expect(sanitizeModalView({'kind': 'list'})?.kind, 'list');
      expect(sanitizeModalView({'kind': 'detail'}), isNull);
      expect(
        sanitizeModalView({'kind': 'detail', 'reportId': 'r1'})?.reportId,
        'r1',
      );
      // A compare of fewer than two survivors is meaningless.
      expect(sanitizeModalView({'kind': 'compare', 'reportIds': ['a']}), isNull);
      expect(
        sanitizeModalView({'kind': 'compare', 'reportIds': ['a', 'b']})
            ?.reportIds,
        ['a', 'b'],
      );
      expect(sanitizeModalView({'kind': 'nope'}), isNull);
    });

    test('pending-batch sanitizer + staleness/resume-loop guards', () {
      final state = sanitizePendingBatch({
        'batchId': 'b1',
        'config': {'cases': <Object?>[]},
        'startedAt': 1000,
        'nextIndex': 1,
        'completedReportIds': ['r1', 7],
        'failures': [
          {'index': 0, 'reason': 'boom'},
          {'bad': true},
        ],
        'resumeCount': 2,
      });
      expect(state, isNotNull);
      expect(state!.completedReportIds, ['r1']);
      expect(state.failures.single.reason, 'boom');
      expect(isStalePendingBatch(state, 1000 + staleBatchTtlMs + 1), isTrue);
      expect(isStalePendingBatch(state, 1000 + 1000), isFalse);
      // 0 cases + headroom 2 → a resumeCount of 3 is a crash loop.
      expect(isResumeLoop(state), isFalse);
      expect(sanitizePendingBatch({'batchId': 'b'}), isNull);
    });
  });

  group('compareDelta.ts parity', () {
    test('tone respects higher-is-better semantics', () {
      final fps = compareRowDef('Avg JS FPS');
      expect(computeDelta(fps, 50, 60).tone, DeltaTone.better);
      expect(computeDelta(fps, 60, 50).tone, DeltaTone.worse);
      expect(computeDelta(fps, 60, 60).tone, DeltaTone.neutral);
      final cpu = compareRowDef('Peak CPU');
      expect(computeDelta(cpu, 50, 60).tone, DeltaTone.worse);
      expect(computeDelta(cpu, 60, 50).tone, DeltaTone.better);
    });

    test('significance uses the 2σ combined-noise band', () {
      expect(computeSignificance(10, 1, 1), 'significant');
      expect(computeSignificance(1, 1, 1), 'noise');
      // Zero spread on both sides: any non-zero delta counts.
      expect(computeSignificance(0.1, 0, 0), 'significant');
      expect(computeSignificance(0, 0, 0), 'noise');
      expect(computeSignificance(1, double.nan, 1), 'unknown');
    });

    test('z-score shares the significance denominator', () {
      expect(computeZScore(4, 1, 1), closeTo(2.8284271, 1e-6));
      expect(computeZScore(0, 0, 0), 0);
      expect(computeZScore(1, 0, 0), double.infinity);
      expect(computeZScore(1, double.nan, 0), isNull);
    });

    test('formatRowValue honours per-row digits + unit', () {
      expect(formatRowValue(compareRowDef('Peak memory'), 512), '512.0 MB');
      expect(formatRowValue(compareRowDef('Min JS FPS'), 58.6), '59');
      expect(formatRowValue(compareRowDef('Peak CPU'), double.nan), '—');
    });
  });

  group('MetricSparkline.tsx parity (bucketing + scaling)', () {
    // Buckets are wall-clock seconds; the in-progress second is excluded, so
    // with nowMs = 10_000 and 30 buckets the window covers [-20s, +10s) and a
    // sample at t lands at index (t ~/ 1000) - (10 - 30).
    const nowMs = 10000;

    test('one column per second, last sample in a bucket wins', () {
      final columns = buildSparklineColumns(
        history: [
          _sample(5000, 30, 0, 0, 0),
          // Same second — this one must win.
          _sample(5900, 60, 0, 0, 0),
          _sample(6000, 15, 0, 0, 0),
        ],
        pick: (s) => s.jsFps,
        max: 60,
        nowMs: nowMs,
      );
      expect(columns.ratios.length, 30);
      // Bucket index for t=5xxx → 5 - (10 - 30) = 25.
      expect(columns.ratios[25], 1.0, reason: '60/60 from the LAST 5s sample');
      expect(columns.ratios[26], 0.25);
      // Every other bucket had no sample → transparent, not zero-height.
      expect(columns.ratios.where((r) => r != null).length, 2);
    });

    test('samples outside the window are dropped, values clamp to 0..1', () {
      // At nowMs = 100s the window is [70s, 100s); the 1 ms sample predates it.
      final columns = buildSparklineColumns(
        history: [
          _sample(1, 60, 0, 0, 0),
          _sample(99000, 120, 0, 0, 0), // above max → clamps to 1
        ],
        pick: (s) => s.jsFps,
        max: 60,
        nowMs: 100000,
      );
      expect(columns.ratios.where((r) => r != null).length, 1);
      expect(columns.ratios[29], 1.0);
    });

    test('fixed scale maps 0..max regardless of the observed values', () {
      final columns = buildSparklineColumns(
        history: [_sample(9000, 30, 0, 0, 0)],
        pick: (s) => s.jsFps,
        max: 60,
        nowMs: nowMs,
      );
      expect(columns.effectiveMin, 0);
      expect(columns.effectiveMax, 60);
      expect(columns.ratios[29], 0.5);
    });

    test('auto scale rescales to the window with 10% padding', () {
      final columns = buildSparklineColumns(
        history: [
          _sample(8000, 0, 0, 0, 400),
          _sample(9000, 0, 0, 0, 500),
        ],
        pick: (s) => s.memoryUsage,
        max: 1024,
        nowMs: nowMs,
        scaleMode: SparklineScale.auto,
      );
      // range 100 → padding 10 → [390, 510]
      expect(columns.effectiveMin, closeTo(390, 1e-9));
      expect(columns.effectiveMax, closeTo(510, 1e-9));
      expect(columns.ratios[28], closeTo(10 / 120, 1e-9));
      expect(columns.ratios[29], closeTo(110 / 120, 1e-9));
    });

    test('auto scale floors a flat signal to 5% of centre (not noise)', () {
      final columns = buildSparklineColumns(
        history: [
          _sample(8000, 0, 0, 0, 500),
          _sample(9000, 0, 0, 0, 500),
        ],
        pick: (s) => s.memoryUsage,
        max: 1024,
        nowMs: nowMs,
        scaleMode: SparklineScale.auto,
      );
      // centre 500 → minRange 25 → [487.5, 512.5], flat trace sits mid-chart.
      expect(columns.effectiveMin, closeTo(487.5, 1e-9));
      expect(columns.effectiveMax, closeTo(512.5, 1e-9));
      expect(columns.ratios[29], closeTo(0.5, 1e-9));
    });

    test('baseline projects through the scale; out-of-chart values are null',
        () {
      final columns = buildSparklineColumns(
        history: [_sample(9000, 30, 0, 0, 0)],
        pick: (s) => s.jsFps,
        max: 60,
        nowMs: nowMs,
      );
      expect(columns.ratioFor(30), closeTo(0.5, 1e-9));
      // A baseline at the refresh rate sits exactly on the ceiling under the
      // fixed scale — RN skips drawing it rather than hugging the edge.
      expect(columns.ratioFor(60), isNull);
      expect(columns.ratioFor(0), isNull);
    });

    test('an empty history paints nothing', () {
      final columns = buildSparklineColumns(
        history: const [],
        pick: (s) => s.jsFps,
        max: 60,
        nowMs: nowMs,
      );
      expect(columns.ratios.every((r) => r == null), isTrue);
    });
  });
}
