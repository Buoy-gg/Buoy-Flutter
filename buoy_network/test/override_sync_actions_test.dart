import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_network/buoy_network.dart';

/// The contract with Buoy Desktop and the MCP server.
///
/// Neither has any Flutter-specific code: they call actions by name and read a
/// snapshot by shape. If these names or shapes drift from
/// `packages/network/src/network/sync/networkSyncAdapter.ts`, both surfaces
/// break silently against Flutter apps while continuing to work against RN —
/// which is the failure mode this file exists to prevent.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OverrideRulesStore.instance.resetForTest();
    NetworkEventStore.instance.capturing = true;
    NetworkEventStore.instance.clear();
  });

  Object? call(String action, [Object? params]) =>
      networkSyncAdapter.actions[action]!(params);

  test('the adapter advertises v4 and the object payload shape', () {
    expect(networkSyncAdapter.version, 4);
    final snapshot = networkSyncAdapter.getSnapshot() as Map;
    expect(snapshot.containsKey('events'), isTrue);
    expect(snapshot.containsKey('overrides'), isTrue);
  });

  test('every action RN exposes exists here under the same name', () {
    // Named literally rather than derived: the whole point is that a rename on
    // either side has to be a deliberate, visible edit in both.
    for (final name in const [
      'clearEvents',
      'getEventBody',
      'setOverridesEnabled',
      'upsertOverrideRule',
      'setOverrideRuleEnabled',
      'deleteOverrideRule',
      'clearOverrideRules',
      'listOverrideRules',
      'getOverrideRuleBody',
      'debugOverrides',
    ]) {
      expect(
        networkSyncAdapter.actions.containsKey(name),
        isTrue,
        reason: 'missing sync action `$name`',
      );
    }
  });

  group('upsertOverrideRule', () {
    test('creates a rule and returns a receipt, not the rule', () {
      final result = call('upsertOverrideRule', {
        'rule': {
          'urlPattern': '*example.com*',
          'kind': 'respond',
          'status': 503,
          'statusText': 'Service Unavailable',
          'body': 'x' * 5000,
        },
      })! as Map;

      expect(result['ok'], isTrue);
      final receipt = result['rule']! as Map;
      // A receipt: the body is reported by SIZE. Echoing it would send the
      // whole payload back down the socket for something no caller reads.
      expect(receipt.containsKey('body'), isFalse);
      expect(receipt['bodySize'], 5000);
      expect(receipt['urlPattern'], '*example.com*');
      expect(receipt['status'], 503);
    });

    test('rejects a rule with no pattern rather than persisting junk', () {
      final result = call('upsertOverrideRule', {
        'rule': {'kind': 'respond'},
      })! as Map;
      expect(result['ok'], isFalse);
      expect(result['error'], contains('urlPattern'));
      expect(OverrideRulesStore.instance.rules, isEmpty);
    });

    test('an enabled rule arms the master switch', () {
      OverrideRulesStore.instance.setEnabled(false);
      call('upsertOverrideRule', {
        'rule': {'urlPattern': '*', 'enabled': true},
      });
      // Leaving a pushed rule dark under an OFF master switch reads as a
      // silent failure to whoever pushed it.
      expect(OverrideRulesStore.instance.enabled, isTrue);
    });

    test('enabled:false stages a rule without arming anything', () {
      call('upsertOverrideRule', {
        'rule': {'urlPattern': '*', 'enabled': false},
      });
      expect(OverrideRulesStore.instance.rules.single.enabled, isFalse);
      expect(OverrideRulesStore.instance.activeCount, 0);
    });

    test('a JSON body sent as an object is serialized, not stringified', () {
      call('upsertOverrideRule', {
        'rule': {
          'urlPattern': '*',
          'body': {'a': 1},
        },
      });
      expect(OverrideRulesStore.instance.rules.single.body, contains('"a": 1'));
    });

    test('bodyOmitted preserves the body a remote surface never received', () {
      final created =
          (call('upsertOverrideRule', {
                'rule': {'urlPattern': '*', 'body': 'the real payload'},
              })!
              as Map)['rule']!
              as Map;
      final id = created['id']! as String;

      // What a dashboard sends back after editing a rule whose body was
      // stripped from the snapshot: no body, and the flag saying why.
      call('upsertOverrideRule', {
        'rule': {
          'id': id,
          'urlPattern': '*',
          'status': 404,
          'bodyOmitted': true,
        },
      });

      final rule = OverrideRulesStore.instance.rules.single;
      expect(rule.status, 404, reason: 'the edit applied');
      expect(rule.body, 'the real payload', reason: 'the body survived');
    });

    test('fromRequestId builds the rule the UI would, query dropped to *', () {
      final event = NetworkCaptureEvent(
        id: 'evt-1',
        method: 'GET',
        url: 'https://pokeapi.co/api/v2/pokemon/eevee?ts=1785783081234',
        timestamp: 0,
        requestClient: 'dio',
      )
        ..status = 200
        ..responseData = {'name': 'eevee'};
      NetworkEventStore.instance.add(event);

      final result = call('upsertOverrideRule', {
        'fromRequestId': 'evt-1',
        'rule': {'status': 500},
      })! as Map;

      expect(result['ok'], isTrue);
      final rule = OverrideRulesStore.instance.rules.single;
      // The cache-buster is gone — this is the difference between a rule that
      // fires on the next call and one that sits at 0 hits forever.
      expect(rule.urlPattern, 'https://pokeapi.co/api/v2/pokemon/eevee*');
      expect(rule.methods, ['GET']);
      expect(rule.status, 500, reason: 'explicit fields beat the prefill');
      expect(rule.body, contains('eevee'), reason: 'seeded with the real body');
    });

    test('fromRequestId for an unknown id fails loudly', () {
      final result = call('upsertOverrideRule', {
        'fromRequestId': 'nope',
      })! as Map;
      expect(result['ok'], isFalse);
      expect(result['error'], contains('nope'));
    });
  });

  group('read + lifecycle actions', () {
    String seed({String body = 'payload'}) {
      final result = call('upsertOverrideRule', {
        'rule': {'urlPattern': '*seed*', 'body': body},
      })! as Map;
      return (result['rule']! as Map)['id']! as String;
    }

    test('listOverrideRules returns state with counters and autoPaused', () {
      seed();
      final state = call('listOverrideRules')! as Map;
      expect(state['enabled'], isTrue);
      expect(state['autoPaused'], isFalse);
      final rules = state['rules']! as List;
      expect(rules, hasLength(1));
      expect((rules.first as Map)['hits'], 0);
      expect((rules.first as Map)['seen'], 0);
    });

    test('getOverrideRuleBody returns the full body the snapshot withheld', () {
      final id = seed(body: 'y' * 40000);
      final result = call('getOverrideRuleBody', {'id': id})! as Map;
      expect((result['body']! as String).length, 40000);
    });

    test('getOverrideRuleBody works while the master switch is off', () {
      final id = seed();
      OverrideRulesStore.instance.setEnabled(false);
      // A rule is perfectly editable when overrides are paused, so the lookup
      // must not read the engine-visible list.
      expect((call('getOverrideRuleBody', {'id': id})! as Map)['body'],
          'payload');
    });

    test('editing a rule resets its budget so a new `times` can fire', () {
      final id = seed();
      // Simulate a rule that has already been used a lot.
      OverrideRulesStore.instance.recordHit(id);
      OverrideRulesStore.instance.recordHit(id);
      OverrideRulesStore.instance.recordHit(id);
      expect(OverrideRulesStore.instance.rules.single.hits, 3);

      // Now make it a one-shot. Carrying the old hits over would make
      // `hits >= times` true before it ever runs — enabled, and permanently
      // dead. Found on device exactly that way.
      call('upsertOverrideRule', {
        'rule': {'id': id, 'urlPattern': '*seed*', 'times': 1},
      });

      final rule = OverrideRulesStore.instance.rules.single;
      expect(rule.hits, 0);
      expect(rule.seen, 0);
      expect(isSpent(rule), isFalse, reason: 'must be able to fire once');
    });

    test('re-enabling a spent rule clears its budget', () {
      final id = seed();
      call('upsertOverrideRule', {
        'rule': {'id': id, 'urlPattern': '*seed*', 'times': 1},
      });
      OverrideRulesStore.instance.recordHit(id);
      // recordHit auto-disables a spent rule.
      expect(OverrideRulesStore.instance.rules.single.enabled, isFalse);

      call('setOverrideRuleEnabled', {'id': id, 'enabled': true});
      final rule = OverrideRulesStore.instance.rules.single;
      expect(rule.enabled, isTrue);
      expect(isSpent(rule), isFalse, reason: 'the toggle must do something');
    });

    test('setOverrideRuleEnabled flips one rule, not the master switch', () {
      final id = seed();
      call('setOverrideRuleEnabled', {'id': id, 'enabled': false});
      expect(OverrideRulesStore.instance.rules.single.enabled, isFalse);
      expect(OverrideRulesStore.instance.enabled, isTrue);
    });

    test('delete and clear', () {
      final id = seed();
      call('deleteOverrideRule', {'id': id});
      expect(OverrideRulesStore.instance.rules, isEmpty);
      seed();
      call('clearOverrideRules');
      expect(OverrideRulesStore.instance.rules, isEmpty);
    });

    test('debugOverrides answers "why is my rule not firing"', () {
      call('upsertOverrideRule', {
        'rule': {'urlPattern': '*pokeapi*'},
      });
      final hit =
          call('debugOverrides', {'url': 'https://pokeapi.co/x'})! as Map;
      expect((hit['engine']! as Map)['matches'], isTrue);
      expect((hit['store']! as Map)['enabled'], isTrue);

      final miss =
          call('debugOverrides', {'url': 'https://elsewhere.dev/x'})! as Map;
      expect((miss['engine']! as Map)['matches'], isFalse);
    });
  });

  group('snapshot', () {
    test('strips an oversized rule body and flags it', () {
      call('upsertOverrideRule', {
        'rule': {'urlPattern': '*', 'body': 'z' * (20 * 1024)},
      });

      final snapshot = networkSyncAdapter.getSnapshot() as Map;
      final rule =
          ((snapshot['overrides']! as Map)['rules']! as List).single as Map;
      expect(rule.containsKey('body'), isFalse);
      expect(rule['bodyOmitted'], isTrue);
      // Everything else still rides, so the dashboard can render the rule.
      expect(rule['urlPattern'], '*');
    });

    test('keeps a small body inline so the common case needs no round trip',
        () {
      call('upsertOverrideRule', {
        'rule': {'urlPattern': '*', 'body': 'small'},
      });
      final rule =
          (((networkSyncAdapter.getSnapshot() as Map)['overrides']!
                      as Map)['rules']!
                  as List)
              .single
          as Map;
      expect(rule['body'], 'small');
      expect(rule.containsKey('bodyOmitted'), isFalse);
    });
  });
}
