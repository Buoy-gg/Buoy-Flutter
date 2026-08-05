import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_network/buoy_network.dart';

/// Mirrors packages/network/src/network/overrides/__tests__/resolveOverride.test.ts.
/// Same cases, same expectations — the two runtimes must agree about which rule
/// fires, because one dashboard authors rules for both.

OverrideRule rule({
  String id = 'r1',
  bool enabled = true,
  String urlPattern = '*',
  List<String>? methods,
  OverrideRuleKind kind = OverrideRuleKind.respond,
  int? status,
  String? body,
  OverrideFailKind? failKind,
  int? delayMs,
  int? times,
  bool alternate = false,
  int hits = 0,
  int seen = 0,
}) => OverrideRule(
  id: id,
  enabled: enabled,
  urlPattern: urlPattern,
  methods: methods,
  kind: kind,
  status: status,
  body: body,
  failKind: failKind,
  delayMs: delayMs,
  times: times,
  alternate: alternate,
  hits: hits,
  seen: seen,
  createdAt: 0,
);

void main() {
  group('escapeRegex', () {
    test('neutralizes regex metacharacters but promotes *', () {
      expect(escapeRegex('a.b'), r'a\.b');
      expect(escapeRegex('a*b'), 'a.*b');
      expect(escapeRegex(r'a+b(c)'), r'a\+b\(c\)');
      // Chrome's set, character for character.
      expect(escapeRegex('[]{}()'), r'\[\]\{\}\(\)');
      expect(escapeRegex(r'^$|-,?'), r'\^\$\|\-\,\?');
    });

    test('a bare host matches nothing — patterns are anchored', () {
      final r = rule(urlPattern: 'pokeapi.co');
      expect(ruleMatches(r, 'https://pokeapi.co/api/v2/pokemon/1', 'GET'),
          isFalse);
    });

    test('wildcards on both sides match anywhere on the host', () {
      final r = rule(urlPattern: '*pokeapi.co*');
      expect(
        ruleMatches(r, 'https://pokeapi.co/api/v2/pokemon/1', 'GET'),
        isTrue,
      );
    });
  });

  group('findMatchingRule', () {
    test('first ENABLED match wins', () {
      final rules = [
        rule(id: 'off', enabled: false, urlPattern: '*'),
        rule(id: 'first', urlPattern: '*api*'),
        rule(id: 'second', urlPattern: '*'),
      ];
      expect(
        findMatchingRule('https://x.dev/api/a', 'GET', rules)?.id,
        'first',
      );
    });

    test('method filter excludes a non-listed method', () {
      final rules = [rule(methods: ['POST'])];
      expect(findMatchingRule('https://x.dev/a', 'GET', rules), isNull);
      expect(findMatchingRule('https://x.dev/a', 'post', rules), isNotNull);
    });

    test('OPTIONS preflights are never overridden', () {
      expect(findMatchingRule('https://x.dev/a', 'OPTIONS', [rule()]), isNull);
    });

    test('a spent rule no longer matches', () {
      final spent = rule(times: 2, hits: 2);
      expect(isSpent(spent), isTrue);
      expect(findMatchingRule('https://x.dev/a', 'GET', [spent]), isNull);
    });

    test('licence traffic is protected from a catch-all', () {
      final rules = [rule(urlPattern: '*')];
      expect(
        findMatchingRule('https://api.keygen.sh/v1/x', 'GET', rules),
        isNull,
      );
      // The guard is targeted, not blanket.
      expect(findMatchingRule('https://pokeapi.co/x', 'GET', rules), isNotNull);
    });

    test('an empty rule list short-circuits', () {
      expect(findMatchingRule('https://x.dev/a', 'GET', const []), isNull);
    });
  });

  group('toOutcome', () {
    test('respond clamps status into [200, 599] and defaults to 200', () {
      final low = toOutcome(rule(status: 0)) as RespondOutcome;
      final high = toOutcome(rule(status: 9000)) as RespondOutcome;
      final none = toOutcome(rule()) as RespondOutcome;
      expect(low.status, statusMin);
      expect(high.status, statusMax);
      expect(none.status, 200);
    });

    test('infers application/json for a JSON body', () {
      final outcome = toOutcome(rule(body: '{"a":1}')) as RespondOutcome;
      expect(outcome.headers['content-type'], 'application/json');
    });

    test('does not mislabel JSON-shaped text that will not parse', () {
      final outcome = toOutcome(rule(body: '{not json')) as RespondOutcome;
      expect(outcome.headers['content-type'], startsWith('text/plain'));
    });

    test('an explicit content-type is never overwritten', () {
      final r = rule(body: '{"a":1}')..headers = {'Content-Type': 'text/csv'};
      final outcome = toOutcome(r) as RespondOutcome;
      expect(outcome.headers['Content-Type'], 'text/csv');
      expect(outcome.headers.containsKey('content-type'), isFalse);
    });

    test('fail defaults to a network failure', () {
      final outcome =
          toOutcome(rule(kind: OverrideRuleKind.fail)) as FailOutcome;
      expect(outcome.failKind, OverrideFailKind.network);
    });

    test('a negative delay is floored at zero', () {
      expect(toOutcome(rule(delayMs: -5)).delayMs, 0);
    });
  });

  group('alternate', () {
    test('lets the first request through and overrides the second', () {
      final r = rule(alternate: true);
      expect(shouldApply(r), isFalse); // seen == 0
      r.seen = 1;
      expect(shouldApply(r), isTrue);
      r.seen = 2;
      expect(shouldApply(r), isFalse);
    });

    test('never skips when alternate is off', () {
      expect(shouldApply(rule(seen: 0)), isTrue);
      expect(shouldApply(rule(seen: 7)), isTrue);
    });

    test('still MATCHES on the off beat, so the phase can advance', () {
      final rules = [rule(alternate: true)];
      // findMatchingRule ignores phase on purpose — the caller records the
      // match so `seen` advances even when nothing is overridden.
      expect(findMatchingRule('https://x.dev/a', 'GET', rules), isNotNull);
      expect(resolveOverride('https://x.dev/a', 'GET', rules), isNull);
    });
  });

  group('patternForUrl', () {
    test('drops the query string so a cache-busting client still matches', () {
      expect(
        patternForUrl(
          'https://pokeapi.co/api/v2/pokemon/dewgong'
          '?debug=true&timestamp=1785783081234',
        ),
        'https://pokeapi.co/api/v2/pokemon/dewgong*',
      );
    });

    test('leaves a query-less URL exact', () {
      expect(
        patternForUrl('https://pokeapi.co/api/v2/pokemon/dewgong'),
        'https://pokeapi.co/api/v2/pokemon/dewgong',
      );
    });

    test('the produced pattern matches the URL it came from', () {
      final url = 'https://pokeapi.co/api/v2/pokemon/eevee?t=1';
      final r = rule(urlPattern: patternForUrl(url));
      expect(ruleMatches(r, url, 'GET'), isTrue);
      // And the NEXT call, with a different cache-buster.
      expect(
        ruleMatches(r, 'https://pokeapi.co/api/v2/pokemon/eevee?t=2', 'GET'),
        isTrue,
      );
    });
  });

  group('round-trip', () {
    test('toJson/fromJson preserves every authored field', () {
      final original = OverrideRule(
        id: 'r9',
        enabled: false,
        name: 'named',
        urlPattern: '*api*',
        methods: ['GET', 'POST'],
        kind: OverrideRuleKind.fail,
        status: 503,
        statusText: 'Service Unavailable',
        headers: {'x-a': '1'},
        body: '{"a":1}',
        failKind: OverrideFailKind.timeout,
        delayMs: 250,
        times: 3,
        alternate: true,
        hits: 2,
        seen: 5,
        createdAt: 1234,
      );
      final restored = OverrideRule.fromJson(original.toJson())!;
      expect(restored.id, 'r9');
      expect(restored.enabled, isFalse);
      expect(restored.name, 'named');
      expect(restored.methods, ['GET', 'POST']);
      expect(restored.kind, OverrideRuleKind.fail);
      expect(restored.statusText, 'Service Unavailable');
      expect(restored.headers, {'x-a': '1'});
      expect(restored.failKind, OverrideFailKind.timeout);
      expect(restored.delayMs, 250);
      expect(restored.times, 3);
      expect(restored.alternate, isTrue);
      expect(restored.hits, 2);
      expect(restored.seen, 5);
      expect(restored.createdAt, 1234);
    });

    test('a malformed entry is dropped, not thrown', () {
      expect(OverrideRule.fromJson(null), isNull);
      expect(OverrideRule.fromJson({'id': 'a'}), isNull); // no pattern
      expect(OverrideRule.fromJson({'urlPattern': '*'}), isNull); // no id
      expect(OverrideRule.fromJson({'id': 'a', 'urlPattern': '  '}), isNull);
    });

    test('omitBody strips the body and flags it', () {
      final json = rule(body: 'x' * 100).toJson(omitBody: true);
      expect(json.containsKey('body'), isFalse);
      expect(json['bodyOmitted'], isTrue);
    });
  });
}
