/// Parity tests for buoy_perf_monitor (Phase B1).
///
/// Every expected value is hand-derived from the RN source
/// (aggregate.ts / windowedStats.ts / settings.ts) so these lock the Flutter
/// port to byte-compatible schema math.
library;

import 'package:buoy_perf_monitor/buoy_perf_monitor.dart';
// The HUD body isn't part of the package's public surface (the register()
// entry point mounts it), but the layout budget it enforces is worth pinning.
// ignore: implementation_imports
import 'package:buoy_perf_monitor/src/perf_tool/perf_hud_body.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

PerfSample _s(
  int ts,
  double js,
  double ui, {
  double cpu = 0,
  double mem = 0,
  double refresh = 60,
  bool active = true,
}) =>
    PerfSample(
      timestamp: ts,
      jsFps: js,
      uiFps: ui,
      cpuUsage: cpu,
      memoryUsage: mem,
      deviceMaxRefreshRate: refresh,
      active: active,
    );

void main() {
  group('aggregate.ts parity', () {
    test('empty → zeroed channels, refresh 60', () {
      final agg = aggregateSamples(const []);
      expect(agg.sampleCount, 0);
      expect(agg.durationMs, 0);
      expect(agg.deviceMaxRefreshRate, 60);
      expect(agg.jsFps.avg, 0);
    });

    test('channel min/max/avg/p95 + jank thresholds vs hand-derived RN', () {
      final samples = [
        _s(1000, 60, 60, cpu: 10, mem: 100),
        _s(1250, 40, 55, cpu: 20, mem: 110),
        _s(1500, 30, 45, cpu: 30, mem: 120),
        _s(1750, 58, 59, cpu: 40, mem: 130),
      ];
      final agg = aggregateSamples(samples);

      expect(agg.sampleCount, 4);
      expect(agg.durationMs, 750);
      expect(agg.deviceMaxRefreshRate, 60);

      // jsFps sorted [30,40,58,60] → min30 max60 avg47 p95(idx3)=60.
      expect(agg.jsFps.min, 30);
      expect(agg.jsFps.max, 60);
      expect(agg.jsFps.avg, closeTo(47, 1e-9));
      expect(agg.jsFps.p95, 60);

      // uiFps sorted [45,55,59,60] → avg 54.75.
      expect(agg.uiFps.avg, closeTo(54.75, 1e-9));

      expect(agg.cpuUsage.avg, closeTo(25, 1e-9));
      expect(agg.memoryUsage.avg, closeTo(115, 1e-9));

      // jsJankThreshold = min(50, round(60*0.66)=40) = 40 → js<40 = {30} = 1.
      expect(agg.jsJankFrames, 1);
      // uiJankThreshold = round(60*0.66)=40 → ui<40 = {} = 0.
      expect(agg.uiJankFrames, 0);
    });

    test('p95 index = ceil(n*0.95)-1 clamped (n=4 → idx3)', () {
      final agg = aggregateSamples([
        _s(0, 10, 10),
        _s(1, 20, 20),
        _s(2, 30, 30),
        _s(3, 40, 40),
      ]);
      expect(agg.jsFps.p95, 40); // sorted[3]
      expect(agg.jsFps.avg, 25);
    });

    test('deviceMaxRefreshRate = dominant (histogram mode), not max', () {
      final agg = aggregateSamples([
        _s(0, 60, 60, refresh: 120),
        _s(1, 60, 60, refresh: 120),
        _s(2, 60, 60, refresh: 60),
      ]);
      expect(agg.deviceMaxRefreshRate, 120);
    });

    test('120Hz jank floor: jsJank stays min(50,...) not 79', () {
      // refresh 120 → uiJankThreshold round(120*0.66)=79; jsJankThreshold
      // min(50, 79) = 50. A 55fps sample is UI-jank (55<79) but not JS-jank.
      final agg = aggregateSamples([_s(0, 55, 55, refresh: 120)]);
      expect(agg.jsJankFrames, 0);
      expect(agg.uiJankFrames, 1);
    });
  });

  group('windowedStats.ts parity + idle skip', () {
    final history = [
      _s(0, 60, 60),
      _s(250, 20, 30),
      _s(500, 0, 0, active: false), // idle tick
    ];

    test('computeWindowStats skips idle samples (activeOnly default)', () {
      final s = computeWindowStats(history, MetricKey.jsFps);
      expect(s.samplesUsed, 2); // idle dropped
      expect(s.min, 20);
      expect(s.max, 60);
      expect(s.mean, 40);
      expect(s.current, 20);
    });

    test('computeWindowStats includes idle when activeOnly:false', () {
      final s =
          computeWindowStats(history, MetricKey.jsFps, activeOnly: false);
      expect(s.samplesUsed, 3);
      expect(s.min, 0);
    });

    test('computeJankCounts: jsThreshold 50 over active samples only', () {
      final j = computeJankCounts(history);
      // active js = [60,20] → <50 = {20} = 1; ui = [60,30] floor=51 → both<51? 60>=51 no, 30<51 yes = 1.
      expect(j.jsJank, 1);
      expect(j.uiJank, 1);
      expect(j.samplesUsed, 2);
    });

    test('empty history → empty stats', () {
      expect(computeWindowStats(const [], MetricKey.uiFps).samplesUsed, 0);
      expect(computeJankCounts(const []).samplesUsed, 0);
    });
  });

  group('deriveFps (synthetic FrameTiming lists)', () {
    test('active window at ~8ms builds → ~60/60', () {
      // 15 frames of 8ms build over a 250ms tick.
      final d = deriveFps(
        frameBuildMicros: List.filled(15, 8000),
        elapsedMs: 250,
        refresh: 60,
        lastUiFps: 42,
      );
      expect(d.active, isTrue);
      expect(d.uiFps, closeTo(60, 1e-9)); // 15/0.25=60 capped at refresh
      expect(d.jsFps, closeTo(60, 1e-9)); // min(60,125)=60
    });

    test('idle tick → jsFps=refresh, uiFps=last-held, active=false', () {
      final d = deriveFps(
        frameBuildMicros: const [],
        elapsedMs: 250,
        refresh: 60,
        lastUiFps: 42,
      );
      expect(d.active, isFalse);
      expect(d.jsFps, 60);
      expect(d.uiFps, 42);
    });

    test('heavy 40ms builds drop jsFps below refresh', () {
      final d = deriveFps(
        frameBuildMicros: List.filled(6, 40000),
        elapsedMs: 250,
        refresh: 60,
        lastUiFps: 60,
      );
      expect(d.jsFps, closeTo(25, 1e-9)); // 1000/40
    });

    test('uiFps capped at refresh even with a burst', () {
      final d = deriveFps(
        frameBuildMicros: List.filled(40, 1000),
        elapsedMs: 250,
        refresh: 60,
        lastUiFps: 60,
      );
      expect(d.uiFps, 60);
    });
  });

  group('refresh-rate clamp', () {
    test('min 60 floor', () {
      expect(clampRefreshRate(60), 60);
      expect(clampRefreshRate(59.9), 60); // sim ProMotion-off
      expect(clampRefreshRate(120), 120);
      expect(clampRefreshRate(0), 60);
      expect(clampRefreshRate(double.nan), 60);
    });
  });

  group('/proc/self/stat parser', () {
    test('parses utime+stime past a comm with spaces + parens', () {
      const stat =
          '1234 (my app) S 1 1234 0 0 -1 0 0 0 0 0 100 50 5 5 20 0 1 0 12345';
      expect(parseProcSelfStatJiffies(stat), 150);
    });

    test('malformed → null', () {
      expect(parseProcSelfStatJiffies('garbage'), isNull);
      expect(parseProcSelfStatJiffies('1234 (x) S 1'), isNull);
    });

    test('procCpuPercent: 25 jiffies / 250ms / 4 cores @100Hz = 25%', () {
      expect(
        procCpuPercent(
          deltaJiffies: 25,
          intervalMs: 250,
          clockTicksPerSec: 100,
          cores: 4,
        ),
        closeTo(25, 1e-9),
      );
    });

    test('procCpuPercent clamps to [0,100] and guards bad intervals', () {
      expect(
        procCpuPercent(
            deltaJiffies: 1000,
            intervalMs: 100,
            clockTicksPerSec: 100,
            cores: 1),
        100,
      );
      expect(
        procCpuPercent(
            deltaJiffies: 10,
            intervalMs: 0,
            clockTicksPerSec: 100,
            cores: 1),
        0,
      );
    });
  });

  group('settings sanitize (settings.ts parity)', () {
    test('windowMs clamped to [1000, 30000]', () {
      expect(sanitizePerfSettings({'windowMs': 999999}).windowMs, 30000);
      expect(sanitizePerfSettings({'windowMs': 5}).windowMs, 1000);
      expect(sanitizePerfSettings({'windowMs': 5000}).windowMs, 5000);
    });

    test('invalid frameBudgetMode → fps; bools honored', () {
      expect(sanitizePerfSettings({'frameBudgetMode': 'nope'}).frameBudgetMode,
          'fps');
      expect(sanitizePerfSettings({'frameBudgetMode': 'ms'}).frameBudgetMode,
          'ms');
      expect(sanitizePerfSettings({'showJsFps': false}).showJsFps, isFalse);
    });

    test('non-map → defaults', () {
      final d = sanitizePerfSettings('nope');
      expect(d.windowMs, 5000);
      expect(d.showUiFps, isTrue);
    });
  });

  group('HUD preferences mode parse', () {
    test('valid + fallback', () {
      expect(HudModeWire.fromWire('strip'), HudMode.strip);
      expect(HudModeWire.fromWire('compact'), HudMode.compact);
      expect(HudModeWire.fromWire('card'), HudMode.card);
      // The retired pill/full modes migrate to the default rather than
      // stranding the HUD in a mode that no longer renders.
      expect(HudModeWire.fromWire('pill'), HudMode.strip);
      expect(HudModeWire.fromWire('full'), HudMode.strip);
      expect(HudModeWire.fromWire('junk'), HudMode.strip);
    });

    test('every mode round-trips through the wire', () {
      for (final mode in HudMode.values) {
        expect(HudModeWire.fromWire(mode.wire), mode);
      }
    });

    test('tap cycles strip → compact → card → strip', () {
      expect(nextHudMode(HudMode.strip), HudMode.compact);
      expect(nextHudMode(HudMode.compact), HudMode.card);
      expect(nextHudMode(HudMode.card), HudMode.strip);
      // Cycling once per mode must land back where it started — otherwise a
      // mode is unreachable or the user can't get back to the default.
      var m = HudMode.strip;
      for (var i = 0; i < HudMode.values.length; i++) {
        m = nextHudMode(m);
      }
      expect(m, HudMode.strip);
    });
  });

  group('HUD surface sizing', () {
    test('every mode has a positive height, ordered compact < card < strip',
        () {
      final heights = {
        for (final mode in HudMode.values) mode: hudHeightFor(mode),
      };
      for (final h in heights.values) {
        expect(h, greaterThan(0));
      }
      // Card carries big numbers but no chart, so it lands between the
      // numbers-only compact row and the charted strip.
      expect(heights[HudMode.compact]!, lessThan(heights[HudMode.card]!));
      expect(heights[HudMode.card]!, lessThan(heights[HudMode.strip]!));
    });

    test('card height is derived from the card body budget, not a guess', () {
      // The chip adds its own vertical padding on top of the card interior;
      // if either drifts this catches the clip before the device does.
      expect(hudHeightFor(HudMode.card, padV: 8), kCardBodyHeight + 16);
      expect(hudHeightFor(HudMode.card, padV: 0), kCardBodyHeight);
    });
  });

  group('HUD body renders without overflow', () {
    PerfSnapshot snapshotWithHistory() {
      const now = 1700000000000;
      return PerfSnapshot(
        jsFps: 57,
        uiFps: 60,
        cpuUsage: 39,
        memoryUsage: 1638,
        deviceMaxRefreshRate: 60,
        history: [
          for (var i = 0; i < 40; i++)
            PerfSample(
              timestamp: now - (40 - i) * 1000,
              jsFps: 45 + (i % 15).toDouble(),
              uiFps: 50 + (i % 10).toDouble(),
              cpuUsage: 20 + (i % 40).toDouble(),
              memoryUsage: 1400 + (i * 8).toDouble(),
              deviceMaxRefreshRate: 60,
            ),
        ],
        mode: PerfMode.native,
        capabilities: const PerfCapabilities(
          cpu: true,
          accurateMemory: true,
          trueUiFps: true,
          reaFrameCallback: false,
        ),
      );
    }

    Widget host(HudMode mode, Size box) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: Padding(
                // The chip's own padding — the body gets what's left.
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                child: PerfHudBody(
                  mode: mode,
                  snapshot: snapshotWithHistory(),
                  settings: PerfSettings.defaults,
                  idle: false,
                  recording: true,
                  recordingElapsed: '02:48',
                  onRecordTap: () {},
                  onStopTap: () {},
                  routeLabel: '/pokemon/pikachu',
                ),
              ),
            ),
          ),
        );

    // A RenderFlex overflow throws in tests, so pumping card mode at its own
    // declared box IS the assertion — and it's the mode worth pinning, since
    // its height comes from a hand-summed interior budget. Phone width
    // (393 - 8pt margins) is the tight case: five cards across ~67pt each.
    //
    // Only card mode is pumped. flutter_test substitutes a square-em test
    // font, so a 14pt glyph measures 14pt wide instead of ~8.4pt in Menlo;
    // strip/compact pack a 14pt number and a hint into a ~100pt cell and
    // "overflow" by 2-3px under that font while fitting real metrics fine.
    // Card mode clearing the bar under the WIDER font is the stronger result.
    for (final width in const [377.0, 520.0]) {
      testWidgets('card mode fits its declared box at ${width.toInt()}pt',
          (tester) async {
        await tester.pumpWidget(
          host(HudMode.card, Size(width, hudHeightFor(HudMode.card))),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('card mode draws a card per visible metric plus Rec',
        (tester) async {
      await tester.pumpWidget(
        host(HudMode.card, const Size(520, 92)),
      );
      // JS / UI / CPU / MEM / Rec.
      expect(find.text('JS'), findsOneWidget);
      expect(find.text('UI'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('MEM'), findsOneWidget);
      expect(find.text('Rec'), findsOneWidget);
      // Value + unit render separately (1638MB → "1.6" + "GB").
      expect(find.text('1.6'), findsOneWidget);
      expect(find.text('GB'), findsOneWidget);
      expect(find.text('39'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      // In fps mode the frame counts carry NO unit — the three characters
      // "fps" x2 are the difference between MEM fitting its unit and clipping
      // it at five columns on a phone.
      expect(find.text('fps'), findsNothing);
      // The recording timer takes the hint slot on the Rec card.
      expect(find.text('02:48'), findsOneWidget);
      // No route row in card mode — the cards own the full height.
      expect(find.text('/pokemon/pikachu'), findsNothing);
    });
  });

  group('snapshot wire shape (desktop live parity)', () {
    test('PerfSnapshot.toJson has the RN fields', () {
      final snap = PerfSnapshot(
        jsFps: 60,
        uiFps: 58,
        cpuUsage: 0,
        memoryUsage: 420,
        deviceMaxRefreshRate: 60,
        history: [_s(0, 60, 58, mem: 420)],
        mode: PerfMode.native,
        capabilities: const PerfCapabilities(
          cpu: false,
          accurateMemory: true,
          trueUiFps: true,
          reaFrameCallback: false,
        ),
      );
      final json = snap.toJson();
      expect(json.keys, containsAll(<String>[
        'jsFps',
        'uiFps',
        'cpuUsage',
        'memoryUsage',
        'deviceMaxRefreshRate',
        'history',
        'mode',
        'capabilities',
      ]));
      expect(json['mode'], 'native');
      final sample = (json['history'] as List).first as Map;
      // Sample wire shape must NOT leak the internal `active` field.
      expect(sample.containsKey('active'), isFalse);
      expect(sample['jsFps'], 60);
    });
  });
}
