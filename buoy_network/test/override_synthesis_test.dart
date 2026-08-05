import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_network/buoy_network.dart';

/// The claim this file exists to prove: a response fabricated by
/// `SyntheticHttpClientRequest` survives a real client end to end.
///
/// Every URL here points at a host that cannot resolve, and
/// `TestWidgetsFlutterBinding` installs its own HttpOverrides that stubs every
/// real request as **400** without touching the network. [BuoyHttpOverrides]
/// chains to it, so a request that is NOT overridden comes back 400 — which
/// makes pass-through directly observable instead of merely "some error".
///
/// So throughout this file: the rule's status means the override fired, and
/// [_passThroughStatus] means it didn't. Nothing here reaches the network.
///
/// The RN equivalent had to assert on private XMLHttpRequest fields. Here the
/// assertions are just "what did the app get back", which is the thing that
/// actually matters.
const String _unreachable = 'https://buoy-override-test.invalid/api/thing';

/// What the Flutter test binding returns for any request we let through.
const int _passThroughStatus = 400;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpOverrides? previousOverrides;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousOverrides = HttpOverrides.current;
    BuoyHttpOverrides.install();
    OverrideRulesStore.instance.resetForTest();
    NetworkEventStore.instance.capturing = true;
    NetworkEventStore.instance.clear();
  });

  tearDown(() {
    HttpOverrides.global = previousOverrides;
    OverrideRulesStore.instance.resetForTest();
  });

  OverrideRule addRule({
    required OverrideRuleKind kind,
    int? status,
    String? body,
    OverrideFailKind? failKind,
    int? delayMs,
    int? times,
    bool alternate = false,
    String pattern = '*buoy-override-test.invalid*',
  }) {
    final rule = OverrideRule(
      id: OverrideRulesStore.instance.nextId(),
      enabled: true,
      urlPattern: pattern,
      kind: kind,
      status: status,
      body: body,
      failKind: failKind,
      delayMs: delayMs,
      times: times,
      alternate: alternate,
      createdAt: 0,
    );
    OverrideRulesStore.instance.upsertRule(rule);
    return rule;
  }

  group('respond', () {
    test('dio receives the forced status and body, without a socket', () async {
      addRule(
        kind: OverrideRuleKind.respond,
        status: 500,
        body: '{"error":"forced"}',
      );

      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      final response = await dio.get<dynamic>(_unreachable);

      expect(response.statusCode, 500);
      // The inferred content-type is application/json, so dio's default
      // transformer decodes it — the app gets a Map, not a String. Getting the
      // header wrong here is what makes an override "look broken".
      expect(response.data, isA<Map>());
      expect((response.data as Map)['error'], 'forced');
    });

    test('raw HttpClient receives it too — synthesis is client-agnostic',
        () async {
      addRule(kind: OverrideRuleKind.respond, status: 418, body: 'teapot');

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(_unreachable));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

      expect(response.statusCode, 418);
      expect(response.reasonPhrase, "I'm a teapot");
      expect(text, 'teapot');
      expect(response.contentLength, 6);
    });

    test('an empty body closes the stream without emitting a chunk', () async {
      addRule(kind: OverrideRuleKind.respond, status: 204, body: '');

      final client = HttpClient();
      final response = await (await client.getUrl(Uri.parse(_unreachable)))
          .close();
      final chunks = await response.toList();

      expect(response.statusCode, 204);
      expect(chunks, isEmpty);
    });

    test('the request is captured, marked, and never left pending', () async {
      final rule = addRule(
        kind: OverrideRuleKind.respond,
        status: 503,
        body: '{"a":1}',
      );

      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      await dio.post<dynamic>(_unreachable, data: {'sent': true});

      final event = NetworkEventStore.instance.events.first;
      expect(event.status, 503);
      expect(event.method, 'POST');
      expect(event.override?.ruleId, rule.id);
      expect(event.override?.kind, OverrideRuleKind.respond);
      // The body the app TRIED to send is still recorded.
      expect(event.requestData, isA<Map>());
      expect((event.requestData as Map)['sent'], true);
      // And the synthesized response body, sized.
      expect(event.responseSize, 7);
    });
  });

  group('fail', () {
    test('network failure reaches dio as connectionError, not unknown',
        () async {
      addRule(
        kind: OverrideRuleKind.fail,
        failKind: OverrideFailKind.network,
      );

      final dio = Dio();
      await expectLater(
        dio.get<dynamic>(_unreachable),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionError,
          ),
        ),
      );
    });

    test('timeout reaches dio as connectionTimeout', () async {
      // dio branches on the exception MESSAGE ("timed out"), which is why the
      // wording in `failException` is load-bearing rather than cosmetic.
      addRule(
        kind: OverrideRuleKind.fail,
        failKind: OverrideFailKind.timeout,
      );

      final dio = Dio();
      await expectLater(
        dio.get<dynamic>(_unreachable),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionTimeout,
          ),
        ),
      );
    });

    test('raw HttpClient sees a SocketException, as it would offline',
        () async {
      addRule(kind: OverrideRuleKind.fail);
      final client = HttpClient();
      await expectLater(
        client.getUrl(Uri.parse(_unreachable)),
        throwsA(isA<SocketException>()),
      );
    });

    test('the failed request is still recorded', () async {
      addRule(kind: OverrideRuleKind.fail);
      try {
        await HttpClient().getUrl(Uri.parse(_unreachable));
        fail('expected the override to raise');
      } on SocketException {
        // Expected — the point is what the tool recorded.
      }

      final event = NetworkEventStore.instance.events.first;
      expect(event.error, 'Network request failed');
      expect(event.override?.kind, OverrideRuleKind.fail);
      expect(event.url, _unreachable);
    });
  });

  group('lifetime', () {
    test('times: 1 fires once, then lets the next request through', () async {
      final rule = addRule(
        kind: OverrideRuleKind.respond,
        status: 500,
        times: 1,
      );
      final dio = Dio(BaseOptions(validateStatus: (_) => true));

      expect((await dio.get<dynamic>(_unreachable)).statusCode, 500);
      // Retired, not silently continuing.
      expect(
        (await dio.get<dynamic>(_unreachable)).statusCode,
        _passThroughStatus,
      );
      expect(OverrideRulesStore.instance.rules.single.enabled, isFalse);
      expect(rule.hits, 1);
    });

    test('alternate lets the first through and overrides the second', () async {
      addRule(kind: OverrideRuleKind.respond, status: 500, alternate: true);
      final dio = Dio(BaseOptions(validateStatus: (_) => true));

      // Phase off, on, off — the sequence that exercises a retry recovering.
      expect(
        (await dio.get<dynamic>(_unreachable)).statusCode,
        _passThroughStatus,
      );
      expect((await dio.get<dynamic>(_unreachable)).statusCode, 500);
      expect(
        (await dio.get<dynamic>(_unreachable)).statusCode,
        _passThroughStatus,
      );
    });

    test('the master switch stops everything without losing rules', () async {
      addRule(kind: OverrideRuleKind.respond, status: 500);
      OverrideRulesStore.instance.setEnabled(false);

      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      expect(
        (await dio.get<dynamic>(_unreachable)).statusCode,
        _passThroughStatus,
      );
      expect(OverrideRulesStore.instance.rules, hasLength(1));

      // And back on again, without having lost the rule.
      OverrideRulesStore.instance.setEnabled(true);
      expect((await dio.get<dynamic>(_unreachable)).statusCode, 500);
    });

    test('a disabled rule alone does not stop the others', () async {
      final off = addRule(kind: OverrideRuleKind.respond, status: 500);
      OverrideRulesStore.instance.setRuleEnabled(off.id, false);

      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      expect(
        (await dio.get<dynamic>(_unreachable)).statusCode,
        _passThroughStatus,
      );

      OverrideRulesStore.instance.setRuleEnabled(off.id, true);
      expect((await dio.get<dynamic>(_unreachable)).statusCode, 500);
    });
  });

  group('delay', () {
    test('a respond rule waits before answering', () async {
      addRule(
        kind: OverrideRuleKind.respond,
        status: 200,
        body: 'ok',
        delayMs: 300,
      );

      final started = DateTime.now();
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      final response = await dio.get<dynamic>(_unreachable);
      final elapsed = DateTime.now().difference(started);

      expect(response.statusCode, 200);
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(300));
    });

    test('a delayed respond trips receiveTimeout, not connectTimeout',
        () async {
      // This is why the delay lives in close() rather than at openUrl: a slow
      // SERVER should exhaust receiveTimeout. Delaying the connect would
      // produce connectionTimeout instead, which is a different bug to chase.
      addRule(
        kind: OverrideRuleKind.respond,
        status: 200,
        body: 'ok',
        delayMs: 600,
      );

      final dio = Dio(
        BaseOptions(receiveTimeout: const Duration(milliseconds: 150)),
      );
      await expectLater(
        dio.get<dynamic>(_unreachable),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.receiveTimeout,
          ),
        ),
      );
    });
  });

  group('safety', () {
    test('a catch-all rule never touches licence traffic', () async {
      addRule(kind: OverrideRuleKind.respond, status: 500, pattern: '*');
      // Not asserting on a real request — `findMatchingRule` is the gate, and
      // reaching keygen from a unit test would be worse than the bug.
      expect(
        findMatchingRule(
          'https://api.keygen.sh/v1/accounts/x/licenses/actions/validate-key',
          'POST',
          OverrideRulesStore.instance.activeRules,
        ),
        isNull,
      );
      expect(
        findMatchingRule(
          _unreachable,
          'GET',
          OverrideRulesStore.instance.activeRules,
        ),
        isNotNull,
      );
    });
  });
}
