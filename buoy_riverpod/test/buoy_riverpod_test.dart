import 'package:buoy_riverpod/buoy_riverpod.dart';
import 'package:buoy_riverpod/src/riverpod_serialize.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncValue;
import 'package:buoy_riverpod/src/riverpod_state_store.dart';
import 'package:buoy_riverpod/src/riverpod_types.dart';
import 'package:buoy_core/buoy_core.dart' show isOverWireBudget;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    riverpodStateStore.isEnabled = true;
    riverpodStateStore.setMaxChanges(200);
    riverpodStateStore.clearChanges();
  });

  group('riverpodStateStore', () {
    test('records prev → next on update, newest-first', () {
      riverpodStateStore.recordUpdate('counter', 1, 2);
      final changes = riverpodStateStore.getChanges();
      expect(changes, isNotEmpty);
      final c = changes.first;
      expect(c.providerLabel, 'counter');
      expect(c.prevValue, 1);
      expect(c.nextValue, 2);
      expect(c.hasValueChange, isTrue);
      expect(c.category, ProviderChangeCategory.update);
      expect(c.valuePreview, '2');
    });

    test('initial capture registers the provider with current value', () {
      riverpodStateStore.recordInitial('settings', {'theme': 'dark'});
      final provider = riverpodStateStore.getProvider('settings');
      expect(provider, isNotNull);
      expect(provider!.currentValue, {'theme': 'dark'});
      expect(riverpodStateStore.getChanges().first.category,
          ProviderChangeCategory.initial);
    });

    test('dispose is logged and marks the provider disposed but kept', () {
      riverpodStateStore.recordInitial('temp', 1);
      riverpodStateStore.recordDispose('temp');
      expect(riverpodStateStore.getProvider('temp')!.disposed, isTrue);
      expect(riverpodStateStore.getChanges().first.category,
          ProviderChangeCategory.dispose);
    });

    test('error is logged with error category', () {
      riverpodStateStore.recordError('bad', Exception('boom'));
      final c = riverpodStateStore.getChanges().first;
      expect(c.category, ProviderChangeCategory.error);
      expect('${c.nextValue}', contains('boom'));
    });

    test('history is capped at maxChanges (200), newest kept', () {
      for (var i = 0; i < 250; i++) {
        riverpodStateStore.recordUpdate('spin', i, i + 1);
      }
      final changes = riverpodStateStore.getChanges();
      expect(changes.length, 200);
      // Newest-first: the most recent update (249 → 250) is at the head.
      expect(changes.first.nextValue, 250);
    });

    test('capture disabled suppresses recording', () {
      riverpodStateStore.isEnabled = false;
      riverpodStateStore.recordUpdate('ignored', 1, 2);
      expect(riverpodStateStore.getChanges()
          .where((c) => c.providerLabel == 'ignored'), isEmpty);
    });

    test('subscribeToNewChanges fires once per new change', () {
      final seen = <ProviderChange>[];
      final unsub = riverpodStateStore.subscribeToNewChanges(seen.add);
      riverpodStateStore.recordUpdate('n', 0, 1);
      riverpodStateStore.recordUpdate('n', 1, 2);
      unsub();
      riverpodStateStore.recordUpdate('n', 2, 3);
      expect(seen.length, 2);
      expect(seen.last.nextValue, 2);
    });
  });

  group('color palette (RN getAtomColor parity)', () {
    test('exact palette hits', () {
      expect(providerColorFor('count'), 0xFF10B981);
      expect(providerColorFor('auth'), 0xFF8B5CF6);
    });

    test('substring match', () {
      expect(providerColorFor('userProfile'), 0xFF3B82F6); // contains "user"
    });

    test('unmatched labels are deterministic opaque colors', () {
      final a = providerColorFor('zzz_widget');
      final b = providerColorFor('zzz_widget');
      expect(a, b);
      expect((a >> 24) & 0xFF, 0xFF); // fully opaque
    });
  });

  group('valueDiffSummary (RN getValueDiffSummary parity)', () {
    test('object key change → "~1 key"', () {
      final r = valueDiffSummary({'a': 1, 'b': 2}, {'a': 1, 'b': 3});
      expect(r.summary, '~1 key');
      expect(r.changedKeys, ['b']);
      expect(r.changedCount, 1);
    });

    test('added + removed keys', () {
      final r = valueDiffSummary({'a': 1}, {'b': 2});
      expect(r.summary, contains('+1'));
      expect(r.summary, contains('-1'));
      expect(r.changedCount, 2);
    });

    test('equal values → no change', () {
      expect(valueDiffSummary(5, 5).summary, 'no change');
    });

    test('primitive change → changed', () {
      expect(valueDiffSummary(1, 2).summary, 'changed');
    });
  });

  group('serializeValue (RN displayValue caps)', () {
    test('primitives pass through', () {
      expect(serializeValue(42), 42);
      expect(serializeValue(true), true);
      expect(serializeValue('hi'), 'hi');
      expect(serializeValue(null), null);
    });

    test('long strings are truncated with a length marker', () {
      final long = 'x' * 6000;
      final out = serializeValue(long) as String;
      expect(out.length, lessThan(long.length));
      expect(out, contains('6000 chars'));
    });

    test('depth beyond the cap is summarized', () {
      Object nest(int n) => n == 0 ? 'leaf' : {'next': nest(n - 1)};
      // 10 levels deep exceeds the depth cap (6): the deep tail collapses to a
      // "{ N keys }" summary rather than recursing forever.
      final out = serializeValue(nest(10));
      expect(out.toString(), contains('keys'));
    });

    test('large lists are capped with an overflow marker', () {
      final out = serializeValue(List<int>.generate(500, (i) => i)) as List;
      expect(out.length, lessThanOrEqualTo(201));
      expect('${out.last}', contains('more'));
    });

    test('objects with toJson() are serialized via toJson', () {
      final out = serializeValue(_Model(7));
      expect(out, {'value': 7});
    });

    test('AsyncValue is unwrapped into {state, value}', () {
      final data = serializeValue(const AsyncValue.data([1, 2, 3])) as Map;
      expect(data['state'], 'data');
      expect(data['value'], [1, 2, 3]);

      final loading = serializeValue(const AsyncValue<int>.loading()) as Map;
      expect(loading['state'], 'loading');

      final error =
          serializeValue(AsyncValue<int>.error('boom', StackTrace.empty)) as Map;
      expect(error['state'], 'error');
      expect('${error['error']}', contains('boom'));
    });
  });

  group('riverpodSyncAdapter wire shape (jotai-shaped)', () {
    test('getSnapshot returns {changes, atoms} with atom fields', () {
      riverpodStateStore.recordInitial('wireProvider', {'k': 1});
      final snap = riverpodSyncAdapter.getSnapshot() as Map<String, Object?>;
      expect(snap.keys, containsAll(['changes', 'atoms']));
      final atoms = snap['atoms'] as List;
      final atom = atoms.firstWhere(
          (a) => (a as Map)['label'] == 'wireProvider') as Map;
      expect(atom.keys, containsAll(['label', 'changeCount', 'color', 'currentValue']));
      expect('${atom['color']}', startsWith('#'));

      final changes = snap['changes'] as List;
      final change = changes.first as Map;
      // Jotai wire field name kept for compatibility.
      expect(change.keys, contains('atomLabel'));
    });

    test('listAtoms returns the jotai-shaped envelope', () {
      riverpodStateStore.recordInitial('listMe', 1);
      final result = riverpodSyncAdapter.actions['listAtoms']!(
          {'includeValues': true}) as Map;
      expect(result.keys,
          containsAll(['atoms', 'total', 'returned', 'includedValues']));
      expect(result['includedValues'], isTrue);
      final atom = (result['atoms'] as List)
          .firstWhere((a) => (a as Map)['label'] == 'listMe') as Map;
      expect(atom['writable'], isFalse); // riverpod is observer-read-only
      expect(atom.containsKey('currentValue'), isTrue);
    });

    test('setAtom is honestly unsupported (throws)', () {
      expect(
        () => riverpodSyncAdapter.actions['setAtom']!({'label': 'x', 'value': 1}),
        throwsA(isA<StateError>()),
      );
    });

    test('clearEvents empties the change log', () {
      riverpodStateStore.recordUpdate('clearMe', 1, 2);
      riverpodSyncAdapter.actions['clearEvents']!(null);
      expect(riverpodStateStore.getChanges(), isEmpty);
    });

    test('adapter version is 2 (jotai parity)', () {
      expect(riverpodSyncAdapter.version, 2);
    });

    test('v2 snapshot is value-free; getChangeDetail / getAtomValue fetch', () {
      riverpodStateStore.clearChanges();
      riverpodStateStore.recordInitial('counter', 1);
      riverpodStateStore.recordUpdate('counter', 1, 2);
      final snap = riverpodSyncAdapter.getSnapshot() as Map<String, Object?>;
      final changes = snap['changes'] as List;
      final change = changes.first as Map;
      expect((change['prevValue'] as Map)['__buoyValueOnDevice'], isTrue);
      expect((change['nextValue'] as Map)['__buoyValueOnDevice'], isTrue);
      // Small current values stay inline on the atoms list.
      final atoms = snap['atoms'] as List;
      expect((atoms.first as Map)['currentValue'], 2);

      final detail = riverpodSyncAdapter.actions['getChangeDetail']!(
        {'id': change['id']},
      ) as Map;
      expect(detail['found'], isTrue);
      expect(detail['prevValue'], 1);
      expect(detail['nextValue'], 2);
      expect(
        (riverpodSyncAdapter.actions['getChangeDetail']!({'id': 'nope'}) as Map)['found'],
        isFalse,
      );

      final value = riverpodSyncAdapter.actions['getAtomValue']!(
        {'label': 'counter'},
      ) as Map;
      expect(value['currentValue'], 2);
    });

    test('a huge currentValue is bounded by the serializer, so it stays inline', () {
      riverpodStateStore.clearChanges();
      riverpodStateStore.recordInitial('big', List.filled(20000, 'x'));
      final snap = riverpodSyncAdapter.getSnapshot() as Map<String, Object?>;
      final atoms = (snap['atoms'] as List).cast<Map>();
      final big = atoms.firstWhere((a) => a['label'] == 'big');
      // serializeValue truncates to _maxItems (+ a "… N more" tail), which is
      // well under the 16KB wire cap — the on-device marker is the backstop
      // for values the serializer cannot bound.
      expect(big['currentValue'], isA<List>());
      expect(isOverWireBudget(big['currentValue'], 16 * 1024), isFalse);
    });
  });

  group('observer label', () {
    test('shared observer is const and available', () {
      expect(buoyRiverpodObserver, isA<BuoyRiverpodObserver>());
    });
  });
}

class _Model {
  _Model(this.value);
  final int value;
  Map<String, Object?> toJson() => {'value': value};
}
