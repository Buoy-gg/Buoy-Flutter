/// Covers the value editor's write path — the half of
/// packages/storage/src/storage/utils/setStorageValue.ts that decides what a
/// key can become, plus the draft buffering from hooks/useTreeDraft.ts.
///
/// Everything here is a way to corrupt a stored value in a way the UI would
/// happily show as fine: writing a String over a `setBool` slot, flattening a
/// JSON object into a quoted string, or committing a draft the device refused.
library;

import 'dart:convert';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_storage/src/storage_capture.dart';
import 'package:buoy_storage/src/storage_tool/key_editor.dart';
import 'package:buoy_storage/src/storage_tool/set_storage_value.dart';
import 'package:buoy_storage/src/storage_tool/storage_models.dart';

class _ReadOnlyMmkv implements BuoyMmkvBackend {
  final writes = <String>[];

  @override
  List<Map<String, Object?>> snapshot() => const [
    {
      'id': 'mmkv.default',
      'readOnly': false,
      'entries': [
        {'key': 'launches', 'value': 3, 'valueType': 'number'},
        {'key': 'blob', 'value': '<ArrayBuffer 8 bytes>', 'valueType': 'buffer'},
      ],
    },
    {'id': 'frozen', 'readOnly': true, 'entries': []},
  ];

  @override
  void set(String instanceId, String key, Object value) =>
      writes.add('$instanceId/$key=$value');

  @override
  void remove(String instanceId, String key) {}
}

/// Read-only on purpose: a backend that doesn't opt into writes must say so
/// rather than fail at save time.
class _ReadOnlySecure implements BuoySecureBackend {
  @override
  List<Map<String, Object?>> keys() => const [
    {'key': 'token', 'requireAuthentication': false},
    {'key': 'pin', 'requireAuthentication': true},
  ];

  @override
  Future<String?> get(String key) async => 'v';

  @override
  Future<void> delete(String key) async {}
}

class _WritableSecure extends _ReadOnlySecure
    implements BuoySecureWritableBackend {
  final writes = <String, String>{};

  @override
  Future<void> set(String key, String value) async => writes[key] = value;
}

StorageKeyInfo info(
  String key, {
  Object? value,
  Object? rawValue,
  String storageType = 'async',
  String? instanceId,
  String? valueType,
}) => StorageKeyInfo(
  key: key,
  value: value,
  rawValue: rawValue ?? value,
  storageType: storageType,
  instanceId: instanceId,
  valueType: valueType,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('validateStorageValue — shared_preferences is typed', () {
    test('a bool slot only takes a bool', () {
      final key = info('flag', value: true);
      expect(validateStorageValue(key, 'false'), isNull);
      expect(validateStorageValue(key, '"false"'), contains('true or false'));
      expect(validateStorageValue(key, '1'), contains('true or false'));
    });

    test('an int slot refuses a fractional number', () {
      final key = info('count', value: 3);
      expect(validateStorageValue(key, '4'), isNull);
      expect(validateStorageValue(key, '4.5'), contains('whole number'));
      expect(validateStorageValue(key, '"4"'), contains('whole number'));
    });

    test('a double slot takes any number', () {
      final key = info('ratio', value: 1.5);
      expect(validateStorageValue(key, '2'), isNull);
      expect(validateStorageValue(key, '2.25'), isNull);
      expect(validateStorageValue(key, '"2"'), contains('number'));
    });

    test('a string-list slot stays a list', () {
      final key = info('tags', value: ['a'], rawValue: ['a']);
      expect(validateStorageValue(key, '["a","b"]'), isNull);
      expect(validateStorageValue(key, '"a"'), contains('list'));
    });

    test('a string slot is free-form, including JSON of any shape', () {
      // `parseValue` already turned a JSON blob into its Map, so the raw value
      // is what says "this key lives in a String slot".
      final key = info('profile', value: {'a': 1}, rawValue: '{"a":1}');
      expect(validateStorageValue(key, '{"a":2,"b":3}'), isNull);
      expect(validateStorageValue(key, '"just text"'), isNull);
    });

    test('malformed JSON is refused before anything else looks at it', () {
      expect(
        validateStorageValue(info('k', value: 'v'), '{oops'),
        contains('Invalid JSON'),
      );
    });

    test('MMKV keeps its native type', () {
      final number = info(
        'launches',
        value: 3,
        storageType: 'mmkv',
        valueType: 'number',
      );
      expect(validateStorageValue(number, '4'), isNull);
      expect(validateStorageValue(number, '"4"'), contains('number'));

      final flag = info(
        'onboarded',
        value: true,
        storageType: 'mmkv',
        valueType: 'boolean',
      );
      expect(validateStorageValue(flag, 'true'), isNull);
      expect(validateStorageValue(flag, '"true"'), contains('true or false'));
    });
  });

  group('storageEditBlockedReason', () {
    test('every shared_preferences key is editable', () async {
      expect(await storageEditBlockedReason(info('k', value: 'v')), isNull);
    });

    test('a buffer has no contents to edit', () async {
      registerBuoyMmkvBackend(_ReadOnlyMmkv());
      final reason = await storageEditBlockedReason(
        info(
          'blob',
          storageType: 'mmkv',
          instanceId: 'mmkv.default',
          valueType: 'buffer',
        ),
      );
      expect(reason, contains('Buffer'));
    });

    test('a read-only MMKV instance is refused', () async {
      registerBuoyMmkvBackend(_ReadOnlyMmkv());
      expect(
        await storageEditBlockedReason(
          info('x', storageType: 'mmkv', instanceId: 'frozen'),
        ),
        contains('read-only'),
      );
      expect(
        await storageEditBlockedReason(
          info(
            'launches',
            storageType: 'mmkv',
            instanceId: 'mmkv.default',
            valueType: 'number',
          ),
        ),
        isNull,
      );
    });

    test('a biometric key is never written', () async {
      registerBuoySecureBackend(_WritableSecure());
      expect(
        await storageEditBlockedReason(info('pin', storageType: 'secure')),
        contains('Biometric'),
      );
      expect(
        await storageEditBlockedReason(info('token', storageType: 'secure')),
        isNull,
      );
    });

    test('a secure backend without write support says so up front', () async {
      registerBuoySecureBackend(_ReadOnlySecure());
      expect(
        await storageEditBlockedReason(info('token', storageType: 'secure')),
        contains('read-only'),
      );
    });
  });

  group('setStorageValue — the write lands in the same native slot', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'flag': true,
        'count': 3,
        'ratio': 1.5,
        'tags': ['a'],
        'profile': '{"a":1}',
        'note': 'hello',
      });
    });

    Future<Object?> read(String key) async =>
        (await SharedPreferences.getInstance()).get(key);

    test('a bool stays a bool', () async {
      await setStorageValue(info('flag', value: true), 'false');
      expect(await read('flag'), false);
    });

    test('an int stays an int', () async {
      await setStorageValue(info('count', value: 3), '4');
      expect(await read('count'), 4);
    });

    test('a double stays a double, even when the text parses as an int', () async {
      await setStorageValue(info('ratio', value: 1.5), '2');
      expect(await read('ratio'), 2.0);
    });

    test('a string list stays a list of strings', () async {
      await setStorageValue(
        info('tags', value: ['a'], rawValue: ['a']),
        '["a","b"]',
      );
      expect(await read('tags'), ['a', 'b']);
    });

    test('a JSON blob is re-serialized compactly, not double-encoded', () async {
      await setStorageValue(
        info('profile', value: {'a': 1}, rawValue: '{"a":1}'),
        '{"a":2}',
      );
      expect(await read('profile'), '{"a":2}');
    });

    test('a plain string is stored unquoted, as the app reads it', () async {
      // The editor sends `"bye"` (JSON); storing that verbatim would hand the
      // app back a string with literal quotes in it.
      await setStorageValue(info('note', value: 'hello'), jsonEncode('bye'));
      expect(await read('note'), 'bye');
    });

    test('a refused value throws instead of writing something lossy', () async {
      await expectLater(
        setStorageValue(info('flag', value: true), '"nope"'),
        throwsA(isA<StateError>()),
      );
      expect(await read('flag'), true);
    });

    test('a blocked key throws before touching the backend', () async {
      registerBuoySecureBackend(_ReadOnlySecure());
      await expectLater(
        setStorageValue(info('token', storageType: 'secure'), '"x"'),
        throwsA(isA<StateError>()),
      );
    });

    test('a writable secure backend receives the plain string', () async {
      final backend = _WritableSecure();
      registerBuoySecureBackend(backend);
      await setStorageValue(
        info('token', value: 'old', storageType: 'secure'),
        jsonEncode('new'),
      );
      expect(backend.writes['token'], 'new');
    });

    test('MMKV writes the coerced native type', () async {
      final backend = _ReadOnlyMmkv();
      registerBuoyMmkvBackend(backend);
      await setStorageValue(
        info(
          'launches',
          value: 3,
          storageType: 'mmkv',
          instanceId: 'mmkv.default',
          valueType: 'number',
        ),
        '9',
      );
      expect(backend.writes, ['mmkv.default/launches=9']);
    });
  });

  group('TreeDraft — buffered, written once', () {
    test('ops are local until commit', () async {
      final saved = <String>[];
      final draft = TreeDraft(
        liveValue: {
          'list': [1, 2],
        },
        save: (raw) async => saved.add(raw),
      );
      draft.begin();

      expect(draft.isDirty, isFalse);
      draft.apply(const JsonAppendOp(['list'], 3));
      expect(draft.isDirty, isTrue);
      // Still nothing written — that is the whole point of the buffer.
      expect(saved, isEmpty);

      expect(await draft.commit(), isTrue);
      expect(saved, ['{"list":[1,2,3]}']);
      expect(draft.isEditing, isFalse);
    });

    test('a clean draft commits without writing', () async {
      var writes = 0;
      final draft = TreeDraft(
        liveValue: {'a': 1},
        save: (_) async => writes++,
      );
      draft.begin();
      expect(await draft.commit(), isTrue);
      expect(writes, 0);
    });

    test('a refused write keeps the work on screen', () async {
      final draft = TreeDraft(
        liveValue: {'a': 1},
        save: (_) async => throw StateError('device said no'),
      );
      draft.begin();
      draft.apply(const JsonReplaceOp(['a'], 2));

      expect(await draft.commit(), isFalse);
      expect(draft.isEditing, isTrue, reason: 'edit mode must survive');
      expect(draft.isDirty, isTrue, reason: 'the draft must survive');
      expect(draft.error, 'device said no');
      expect(getAtPath(draft.value, ['a']), 2);
    });

    test('discard throws the draft away', () {
      final draft = TreeDraft(liveValue: {'a': 1});
      draft.begin();
      draft.apply(const JsonReplaceOp(['a'], 2));
      draft.discard();
      expect(draft.isEditing, isFalse);
      expect(draft.isDirty, isFalse);
      expect(getAtPath(draft.value, ['a']), 1);
    });

    test('the highlight follows ops that move or delete a node', () {
      final draft = TreeDraft(
        liveValue: {
          'list': [1, 2, 3],
        },
      );
      draft.begin();
      expect(draft.selectPath, isA<SelectionUnchanged>());

      draft.apply(const JsonMoveOp(['list', '2'], 0));
      expect(draft.selectPath.path, ['list', '0']);

      draft.apply(const JsonRemoveOp(['list', '0']));
      expect(draft.selectPath, isNot(isA<SelectionUnchanged>()));
      expect(draft.selectPath.path, isNull);

      draft.selectAt(['list', '1']);
      expect(draft.selectPath.path, ['list', '1']);
    });
  });

  group('KeyEditorController', () {
    KeyEditorController controller({
      Object? value,
      Future<void> Function(String raw)? save,
      VoidCallback? onClose,
      void Function(DiscardChoices)? confirmDiscard,
    }) => KeyEditorController(
      value: value ?? {'a': 1},
      save: save ?? (_) async {},
      onClose: onClose ?? () {},
      confirmDiscard: confirmDiscard ?? (_) {},
    );

    test('seeds the draft on construction', () {
      final editor = controller();
      expect(editor.draft.isEditing, isTrue);
      expect(editor.draft.isDirty, isFalse);
    });

    test('a boolean flips in place rather than opening the modal', () {
      final editor = controller(value: {'flag': true});
      editor.openValueEditor(['flag']);
      expect(editor.valuePath, isNull, reason: 'no modal for a boolean');
      expect(getAtPath(editor.draft.value, ['flag']), false);
    });

    test('anything else opens the modal and applies through the draft', () {
      final editor = controller(value: {'name': 'old'});
      editor.openValueEditor(['name']);
      expect(editor.valuePath, ['name']);

      editor.applyValue('new');
      expect(editor.valuePath, isNull);
      expect(getAtPath(editor.draft.value, ['name']), 'new');
    });

    test('the raw editor addresses the whole value', () {
      final editor = controller();
      editor.openRawEditor();
      expect(editor.valuePath, isEmpty);
    });

    test('closing clean just closes', () {
      var closed = false;
      var asked = false;
      controller(
        onClose: () => closed = true,
        confirmDiscard: (_) => asked = true,
      ).requestClose();
      expect(closed, isTrue);
      expect(asked, isFalse);
    });

    test('closing dirty asks first, and discarding then closes', () {
      var closed = false;
      DiscardChoices? asked;
      final editor = controller(
        onClose: () => closed = true,
        confirmDiscard: (choices) => asked = choices,
      );
      editor.draft.apply(const JsonReplaceOp(['a'], 2));

      editor.requestClose();
      expect(asked, isNotNull);
      expect(closed, isFalse, reason: 'unsaved work must not vanish silently');

      asked!.discard();
      expect(closed, isTrue);
    });

    test('a failed save keeps the editor open', () async {
      var closed = false;
      final editor = controller(
        save: (_) async => throw StateError('nope'),
        onClose: () => closed = true,
      );
      editor.draft.apply(const JsonReplaceOp(['a'], 2));

      expect(await editor.draft.commit(), isFalse);
      expect(closed, isFalse);
    });
  });
}
