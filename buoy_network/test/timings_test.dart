import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_network/buoy_network.dart';

/// The request waterfall: TTFB and Content download.
///
/// Both come from real sample points — headers landing and the body finishing —
/// rather than being derived by multiplying the total by a fixed fraction. A
/// test that only checked "the numbers exist" would pass for invented ones too,
/// so these check the SPLIT.
///
/// Plain `test`, not `testWidgets`: the latter runs under FakeAsync, where a
/// real HTTP future never completes and the suite hangs.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpOverrides? previous;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = HttpOverrides.current;
    BuoyHttpOverrides.install();
    OverrideRulesStore.instance.resetForTest();
    NetworkSavedStore.instance.resetForTest();
    NetworkEventStore.instance.capturing = true;
    NetworkEventStore.instance.clear();
  });

  tearDown(() {
    HttpOverrides.global = previous;
    OverrideRulesStore.instance.resetForTest();
  });

  test('serializes as RN does, so the desktop reads it unchanged', () {
    const timings = NetworkTimings(ttfb: 120, download: 30);
    expect(timings.toJson(), {'ttfb': 120, 'download': 30});
  });

  test('the event omits timings entirely when unmeasured', () {
    final event = NetworkCaptureEvent(
      id: 'e1',
      method: 'GET',
      url: 'https://api.dev/a',
      timestamp: 0,
      requestClient: 'dio',
    );
    // Absent, NOT zeroed: 0ms/0ms would read as a measurement.
    expect(event.toJson().containsKey('timings'), isFalse);
  });

  test('a real request splits its duration into the two phases', () async {
    // The test binding stubs every request as a 400 without touching the
    // network, which is enough: the phases are sampled by OUR wrappers, not by
    // the server.
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    await dio.get<dynamic>('https://buoy-timings-test.invalid/thing');

    final event = NetworkEventStore.instance.events.first;
    final timings = event.timings;
    expect(timings, isNotNull, reason: 'a completed request is measurable');
    expect(timings!.ttfb, greaterThanOrEqualTo(0));
    expect(timings.download, greaterThanOrEqualTo(0));
    // The two halves reconstruct the whole — that is what makes them a split
    // rather than two independent guesses.
    expect(timings.ttfb + timings.download, event.duration);
  });

  test('download is floored at zero, never negative', () async {
    // ttfb and the total are sampled at different points, so a sub-millisecond
    // body can otherwise produce a negative download and a bar drawn backwards.
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    await dio.get<dynamic>('https://buoy-timings-test.invalid/tiny');

    final timings = NetworkEventStore.instance.events.first.timings!;
    expect(timings.download, greaterThanOrEqualTo(0));
  });

  test('a synthesized override reports no timings', () async {
    OverrideRulesStore.instance.upsertRule(
      OverrideRule(
        id: 'r1',
        enabled: true,
        urlPattern: '*buoy-timings-test.invalid*',
        kind: OverrideRuleKind.respond,
        status: 500,
        body: 'forged',
        createdAt: 0,
      ),
    );

    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    final response = await dio.get<dynamic>(
      'https://buoy-timings-test.invalid/thing',
    );
    expect(response.statusCode, 500);

    // Nothing was waited for and nothing was downloaded. Drawing a waterfall
    // for a response we invented would be inventing measurements too.
    expect(NetworkEventStore.instance.events.first.timings, isNull);
  });
}
