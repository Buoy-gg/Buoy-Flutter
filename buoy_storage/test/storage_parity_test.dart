import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_storage/src/storage_capture.dart';
import 'package:buoy_storage/src/storage_tool/storage_action_helpers.dart';
import 'package:buoy_storage/src/storage_tool/storage_models.dart';
import 'package:buoy_storage/src/storage_tool/storage_time_travel.dart';
import 'package:buoy_storage/src/storage_tool/storage_value_type.dart';

StorageEvent _event(
  String key,
  String action, {
  Object? value,
  Object? prevValue,
  String type = 'async',
  DateTime? at,
}) =>
    StorageEvent(
      id: 'id-$key-$action-${at?.millisecondsSinceEpoch ?? 0}',
      action: action,
      timestamp: at ?? DateTime(2026, 7, 22, 12),
      storageType: type,
      key: key,
      value: value,
      prevValue: prevValue,
    );

class _FakeMmkv implements BuoyMmkvBackend {
  @override
  List<Map<String, Object?>> snapshot() => const [
        {
          'id': 'mmkv.default',
          'encrypted': false,
          'readOnly': false,
          'entries': [
            {'key': 'session.launch_count', 'value': 3, 'valueType': 'number'},
            {'key': 'session.onboarded', 'value': true, 'valueType': 'boolean'},
            {'key': 'shared.key', 'value': 'a', 'valueType': 'string'},
            {'key': '@react_buoy_x', 'value': '1', 'valueType': 'string'},
          ],
        },
        {
          'id': 'pokedex.cache',
          'encrypted': true,
          'readOnly': false,
          'entries': [
            {'key': 'sprite.etag', 'value': 'W/"1"', 'valueType': 'string'},
            {'key': 'shared.key', 'value': 'b', 'valueType': 'string'},
          ],
        },
      ];

  @override
  void set(String instanceId, String key, Object value) {}

  @override
  void remove(String instanceId, String key) {}
}

class _FakeSecure implements BuoySecureBackend {
  @override
  List<Map<String, Object?>> keys() => const [
        {
          'key': '@pokedex/auth_token',
          'keychainService': 'svc',
          'requireAuthentication': false,
        },
        {
          'key': '@pokedex/trainer_pin',
          'keychainService': 'svc',
          'requireAuthentication': true,
        },
        {'key': '@pokedex/unset', 'keychainService': 'svc'},
      ];

  @override
  Future<String?> get(String key) async =>
      key == '@pokedex/auth_token' ? 'jwt' : null;

  @override
  Future<void> delete(String key) async {}
}

void main() {
  group('devtool key separation (RN isDevToolsStorageKey)', () {
    test('buoy keys are dev-tool keys, app keys are not', () {
      expect(isDevToolsStorageKey('@react_buoy_storage_is_monitoring'), isTrue);
      expect(isDevToolsStorageKey('@react_buoy_network_modal'), isTrue);
      expect(isDevToolsStorageKey('buoy-license'), isTrue);
      expect(isDevToolsStorageKey('@buoy_anything'), isTrue);
      expect(isDevToolsStorageKey('@pokedex/trainer_name'), isFalse);
      expect(isDevToolsStorageKey('redux-persist:root'), isFalse);
      expect(isDevToolsStorageKey(''), isFalse);
    });
  });

  group('value type detection (RN getValueType / valueType.ts)', () {
    test('getValueType parses stringified JSON before typing', () {
      expect(getValueType('{"a":1}'), 'object');
      expect(getValueType('[1,2,3]'), 'array');
      expect(getValueType('42'), 'number');
      expect(getValueType('true'), 'boolean');
      expect(getValueType('hello'), 'string');
      expect(getValueType(null), 'null');
      expect(getValueType(7), 'number');
      expect(getValueType(['x']), 'array');
    });

    test('getValueTypeLabel types the raw value (no parse)', () {
      expect(getValueTypeLabel('{"a":1}'), 'string');
      expect(getValueTypeLabel(true), 'boolean');
      expect(getValueTypeLabel(3.14), 'number');
      expect(getValueTypeLabel({'a': 1}), 'object');
    });

    test('getValueTypeWithPreview matches RN previews', () {
      expect(getValueTypeWithPreview(true), 'boolean · true');
      expect(getValueTypeWithPreview(42), 'number · 42');
      expect(getValueTypeWithPreview('hi'), 'string · "hi"');
      expect(getValueTypeWithPreview(''), 'string · ""');
      // Long strings drop the preview.
      expect(getValueTypeWithPreview('x' * 60), 'string');
      // Objects have no inline preview.
      expect(getValueTypeWithPreview({'a': 1}), 'object');
    });
  });

  group('action helpers (RN storageActionHelpers.ts)', () {
    test('translateStorageAction maps RN labels', () {
      expect(translateStorageAction('setItem'), 'SET');
      expect(translateStorageAction('removeItem'), 'REMOVE');
      expect(translateStorageAction('clear'), 'CLEAR');
      expect(translateStorageAction('multiSet'), 'MULTI SET');
      expect(translateStorageAction('set.boolean'), 'SET');
      expect(translateStorageAction('get.string'), 'GET');
      expect(translateStorageAction('delete'), 'REMOVE');
      expect(translateStorageAction('nonsense'), 'UNKNOWN ACTION');
    });
  });

  group('conversation grouping (RN conversations memo)', () {
    test('groups by key, counts ops, newest-first, honors filters', () {
      final events = [
        _event('b', 'setItem', value: 1, at: DateTime(2026, 7, 22, 12, 0, 3)),
        _event('a', 'setItem', value: 'x', at: DateTime(2026, 7, 22, 12, 0, 2)),
        _event('a', 'removeItem', at: DateTime(2026, 7, 22, 12, 0, 1)),
        _event('secret', 'setItem',
            value: 1, at: DateTime(2026, 7, 22, 12, 0, 4)),
        _event('m', 'set.string',
            value: 'z', type: 'mmkv', at: DateTime(2026, 7, 22, 12, 0, 5)),
      ];

      final convos = buildConversations(
        events,
        ignoredPatterns: {'secret'},
        enabledStorageTypes: {'async', 'mmkv', 'secure'},
      );

      // 'secret' filtered out; a, b, m remain.
      expect(convos.map((c) => c.key), containsAll(['a', 'b', 'm']));
      expect(convos.any((c) => c.key == 'secret'), isFalse);

      // 'a' has 2 events.
      final a = convos.firstWhere((c) => c.key == 'a');
      expect(a.totalOperations, 2);

      // Newest-first by last event timestamp: m (12:0:5) first.
      expect(convos.first.key, 'm');
    });

    test('enabledStorageTypes gate drops disabled backends', () {
      final events = [
        _event('a', 'setItem', value: 1),
        _event('m', 'set.string', value: 'z', type: 'mmkv'),
      ];
      final convos = buildConversations(
        events,
        ignoredPatterns: {},
        enabledStorageTypes: {'async'},
      );
      expect(convos.map((c) => c.key), ['a']);
    });
  });

  group('event store cap + ordering (BaseEventStore)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('newest-first, capped at maxEvents', () {
      final store = StorageEventStore.instance..clearEvents();
      // Directly exercise addEvent via recordOwnedWrite path is gated on
      // capturing; use the base addEvent through a public surface: clear then
      // push via recordOwnedWrite after forcing capture on.
      store.startCapturing();
      for (var i = 0; i < 10; i++) {
        store.recordOwnedWrite(action: 'setItem', key: 'k$i', value: i);
      }
      final events = store.events;
      expect(events.first.key, 'k9'); // newest-first
      expect(events.last.key, 'k0');
      store.stopCapturing();
      store.clearEvents();
    });

    test('dev-tool keys are ignored by the monitor', () {
      final store = StorageEventStore.instance..clearEvents();
      store.startCapturing();
      store.recordOwnedWrite(
        action: 'setItem',
        key: '@react_buoy_storage_is_monitoring',
        value: 'true',
      );
      store.recordOwnedWrite(action: 'setItem', key: '@pokedex/x', value: 1);
      expect(store.events.map((e) => e.key), ['@pokedex/x']);
      store.stopCapturing();
      store.clearEvents();
    });
  });

  // Registered last: the backend registry is global with no unregister, so
  // these must not leak into the groups above.
  group('optional backends (RN MMKV / SecureStore registries)', () {
    setUpAll(() {
      registerBuoyMmkvBackend(_FakeMmkv());
      registerBuoySecureBackend(_FakeSecure());
    });

    test('MMKV instances flatten to entries with RN value types', () async {
      final entries = readBuoyMmkvEntries();
      // Buoy's own keys never surface, even from a backend.
      expect(entries.values.map((e) => e.key), isNot(contains('@react_buoy_x')));
      final byKey = {for (final e in entries.values) e.key: e};
      expect(byKey['session.launch_count']?.valueType, 'number');
      expect(byKey['session.onboarded']?.instanceId, 'mmkv.default');
      expect(byKey['sprite.etag']?.instanceId, 'pokedex.cache');
      expect(mmkvSetAction('number'), 'set.number');
      expect(mmkvSetAction('boolean'), 'set.boolean');
      expect(mmkvSetAction(null), 'set.string');
    });

    test('same key in two instances gets its own entry', () {
      final entries = readBuoyMmkvEntries();
      final shared =
          entries.values.where((e) => e.key == 'shared.key').toList();
      expect(shared.map((e) => e.instanceId), ['mmkv.default', 'pokedex.cache']);
    });

    test('biometric secure keys are listed but never read', () async {
      final entries = await readBuoySecureEntries();
      final byKey = {for (final e in entries) e.key: e};
      expect(byKey['@pokedex/auth_token']?.value, 'jwt');
      expect(byKey['@pokedex/auth_token']?.keychainService, 'svc');
      expect(byKey['@pokedex/trainer_pin']?.value, secureBiometricPlaceholder);
      expect(byKey['@pokedex/trainer_pin']?.requireAuthentication, isTrue);
      // Declared but unset → surfaced with a null value (missing row).
      expect(byKey.containsKey('@pokedex/unset'), isTrue);
      expect(byKey['@pokedex/unset']?.value, isNull);
    });

    test('owned writes carry storage type, instance + value type', () {
      final store = StorageEventStore.instance..clearEvents();
      store.startCapturing();
      store.recordOwnedWrite(
        action: mmkvSetAction('boolean'),
        key: 'session.onboarded',
        value: false,
        storageType: 'mmkv',
        valueType: 'boolean',
        instanceId: 'mmkv.default',
      );
      final e = store.events.first;
      expect(e.action, 'set.boolean');
      expect(e.storageType, 'mmkv');
      expect(e.instanceId, 'mmkv.default');
      expect((e.toJson()['data'] as Map)['valueType'], 'boolean');
      store.stopCapturing();
      store.clearEvents();
    });
  });

  group('event serialization shape (RN wire parity)', () {
    test('toJson matches JSON.stringify(Date) ISO + nested data', () {
      final e = _event('@pokedex/badges', 'setItem',
          value: 8, at: DateTime.utc(2026, 7, 22, 12));
      final json = e.toJson();
      expect(json['action'], 'setItem');
      expect(json['storageType'], 'async');
      expect(json['timestamp'], '2026-07-22T12:00:00.000Z');
      final data = json['data'] as Map;
      expect(data['key'], '@pokedex/badges');
      expect(data['value'], 8);
    });
  });

  group('time travel (RN storageTimeTravelUtils.ts)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('canUndo: async setItem/removeItem only', () {
      expect(canUndo(_event('k', 'setItem', value: '1')), isTrue);
      expect(canUndo(_event('k', 'removeItem')), isTrue);
      expect(canUndo(_event('k', 'set.string', type: 'mmkv')), isFalse);
      expect(canUndo(_event('k', 'setItem', type: 'secure')), isFalse);
      expect(canUndo(_event('k', 'clear')), isFalse);
    });

    test('undo setItem restores the previous value (typed)', () async {
      SharedPreferences.setMockInitialValues({'@pokedex/badges': 8});
      await undoOperation(_event('@pokedex/badges', 'setItem',
          value: 8, prevValue: 3));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('@pokedex/badges'), 3);
    });

    test('undo setItem with no previous value removes the key', () async {
      SharedPreferences.setMockInitialValues({'@pokedex/new_key': 'v'});
      await undoOperation(_event('@pokedex/new_key', 'setItem', value: 'v'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('@pokedex/new_key'), isFalse);
    });

    test('undo removeItem restores the removed value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await undoOperation(_event('@pokedex/party', 'removeItem',
          prevValue: ['pikachu', 'eevee']));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('@pokedex/party'), ['pikachu', 'eevee']);
    });

    test('jump replays to the target and removes later-created keys', () async {
      SharedPreferences.setMockInitialValues(
          {'@pokedex/badges': 8, '@pokedex/later_key': 'x'});
      final t = DateTime(2026, 7, 23, 12);
      final events = [
        _event('@pokedex/badges', 'setItem', value: 1, at: t),
        _event('@pokedex/badges', 'setItem',
            value: 3, at: t.add(const Duration(seconds: 1))),
        _event('@pokedex/badges', 'setItem',
            value: 8, at: t.add(const Duration(seconds: 2))),
        _event('@pokedex/later_key', 'setItem',
            value: 'x', at: t.add(const Duration(seconds: 3))),
      ];
      await jumpToState(events, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('@pokedex/badges'), 3);
      // Created after the target — removed, not left behind (RN parity).
      expect(prefs.containsKey('@pokedex/later_key'), isFalse);
    });

    test('jump never touches dev-tool keys', () async {
      SharedPreferences.setMockInitialValues(
          {'@react_buoy_storage_active_tab': 'events', '@pokedex/badges': 8});
      final t = DateTime(2026, 7, 23, 12);
      final events = [
        _event('@pokedex/badges', 'setItem', value: 1, at: t),
        _event('@react_buoy_storage_active_tab', 'setItem',
            value: 'browser', at: t.add(const Duration(seconds: 1))),
      ];
      await jumpToState(events, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('@pokedex/badges'), 1);
      expect(prefs.getString('@react_buoy_storage_active_tab'), 'events');
    });

    test('jump rejects an out-of-range index', () async {
      expect(
        () => jumpToState([_event('k', 'setItem', value: '1')], 2),
        throwsRangeError,
      );
    });
  });
}
