/// Ports packages/storage/src/storage/utils/setStorageValue.ts.
///
/// Writing a storage value back, in one place. Each backend writes differently,
/// and a second copy of that fan-out is how one backend quietly starts
/// corrupting values.
///
/// The hard part is NOT the write, it's the types:
///
/// - **shared_preferences** is natively typed (bool / int / double / String /
///   List&lt;String&gt;), where RN's AsyncStorage is string-only. That is the one
///   real deviation from the RN original: RN preserves the *JSON-string*
///   convention because it has nothing else to preserve, while here the write
///   must land back in the SAME native slot the key already occupies — writing
///   `"true"` over a `setBool` key would make `getBool` throw for the app. The
///   original type is therefore read straight from prefs at write time, which
///   is the same rule `async.setItem` in the sync adapter already follows.
/// - **MMKV** is natively typed too (string / number / boolean / buffer), so
///   the original type is restored from `valueType`. Buffers can't round-trip
///   at all — the snapshot only ever carried a byte-length placeholder.
/// - **SecureStore** stores strings, and biometric-protected keys are never
///   touched (writing needs the same auth prompt reading does).
///
/// Pro gating and confirmation are deliberately NOT here; they belong to the UI
/// that has the user's attention. This assumes the caller already asked.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../storage_capture.dart';
import 'storage_models.dart';

/// Why a key can't be edited, or null when it can. UI uses this both to hide
/// the edit affordance and to explain itself, rather than failing at save time.
Future<String?> storageEditBlockedReason(StorageKeyInfo storageKey) async {
  if (storageKey.storageType == 'mmkv') {
    if (storageKey.valueType == 'buffer') {
      return 'Buffer values can\'t be edited — the tool only ever sees their '
          'byte length, not their contents.';
    }
    final backend = buoyMmkvBackend;
    if (backend == null) return 'No MMKV backend is registered.';
    final instanceId = storageKey.instanceId ?? 'default';
    for (final instance in backend.snapshot()) {
      if (instance['id'] == instanceId && instance['readOnly'] == true) {
        return 'MMKV instance "$instanceId" is registered read-only.';
      }
    }
  }

  if (storageKey.storageType == 'secure') {
    final backend = buoySecureBackend;
    if (backend == null) return 'No SecureStore backend is registered.';
    for (final descriptor in backend.keys()) {
      if (descriptor['key'] == storageKey.key &&
          descriptor['requireAuthentication'] == true) {
        return 'Biometric-protected keys can\'t be edited — writing one would '
            'fire an auth prompt.';
      }
    }
    if (backend is! BuoySecureWritableBackend) {
      return 'The registered secure backend is read-only (implement '
          'BuoySecureWritableBackend to enable editing).';
    }
  }

  return null;
}

/// Validate [raw] for this key WITHOUT writing. Returns an error message, or
/// null when the text is acceptable. The editor calls this before saving.
///
/// [raw] is always JSON — every caller serializes the edited value — so the
/// checks read the DECODED shape rather than the text, which is what makes
/// "must stay a number" mean the same thing here as in the value modal.
String? validateStorageValue(StorageKeyInfo storageKey, String raw) {
  final Object? next;
  try {
    next = jsonDecode(raw);
  } catch (e) {
    return 'Invalid JSON — $e';
  }

  if (storageKey.storageType == 'mmkv') {
    return switch (_mmkvTargetType(storageKey)) {
      'number' when next is! num =>
        'Must be a number — this MMKV key is stored as a number.',
      'boolean' when next is! bool =>
        'Must be true or false — this MMKV key is stored as a boolean.',
      _ => null,
    };
  }

  // shared_preferences is typed: a key written with setBool has to stay a bool,
  // and the type the app reads it back with is not ours to change.
  if (storageKey.storageType == 'async') {
    return switch (storageKey.rawValue) {
      bool _ when next is! bool =>
        'Must be true or false — this key is stored as a boolean.',
      int _ when next is! int => 'Must be a whole number — this key is stored '
          'as an int.',
      double _ when next is! num =>
        'Must be a number — this key is stored as a double.',
      List _ when next is! List =>
        'Must be a list — this key is stored as a string list.',
      _ => null,
    };
  }

  return null;
}

/// The value as a STRUCTURE, for the tree editor to apply ops against, or null
/// when it isn't a container (scalars go through the plain value editor).
///
/// The browser already un-stringifies with `parseValue`, so this is a shape
/// check rather than RN's re-parse — the same job [structuredStorageValue] does
/// there, minus the work already done upstream.
Object? structuredStorageValue(StorageKeyInfo storageKey) {
  final value = storageKey.value;
  return value is Map || value is List ? value : null;
}

/// Write [raw] (a JSON-serialized value) to whichever backend holds this key,
/// restoring the value's original type. Throws — rather than writing something
/// lossy — when the key isn't editable or the value doesn't fit the type.
/// Callers surface that.
Future<void> setStorageValue(StorageKeyInfo storageKey, String raw) async {
  final blocked = await storageEditBlockedReason(storageKey);
  if (blocked != null) throw StateError(blocked);

  final invalid = validateStorageValue(storageKey, raw);
  if (invalid != null) throw StateError(invalid);

  final next = jsonDecode(raw);

  switch (storageKey.storageType) {
    case 'async':
      final prefs = await BuoyPrefs.getInstance();
      // The slot the key already occupies decides the setter — see the library
      // docstring. Read live rather than trusting the row, which is a snapshot.
      final current = (await SharedPreferences.getInstance()).get(
        storageKey.key,
      );
      switch (current) {
        case bool _:
          await prefs.setBool(storageKey.key, next as bool);
        case int _:
          await prefs.setInt(storageKey.key, next as int);
        case double _:
          await prefs.setDouble(storageKey.key, (next as num).toDouble());
        case List _:
          await prefs.setStringList(storageKey.key, [
            for (final item in next as List) _asPrefsString(item),
          ]);
        default:
          await prefs.setString(storageKey.key, _asPrefsString(next));
      }
      return;

    case 'secure':
      final backend = buoySecureBackend;
      if (backend is! BuoySecureWritableBackend) {
        throw StateError(
          'The registered secure backend does not support writes '
          '(implement BuoySecureWritableBackend to enable editing).',
        );
      }
      await (backend as BuoySecureWritableBackend).set(
        storageKey.key,
        _asPrefsString(next),
      );
      return;

    case 'mmkv':
      final backend = buoyMmkvBackend;
      final instanceId = storageKey.instanceId ?? 'default';
      if (backend == null) {
        throw StateError('MMKV instance "$instanceId" is not registered.');
      }
      backend.set(instanceId, storageKey.key, _coerceMmkv(storageKey, next));
      return;

    default:
      throw StateError('Unsupported storage type "${storageKey.storageType}"');
  }
}

/// The text form of an edited value for a string-valued slot: a container is
/// re-serialized compactly — matching what the app itself would have written —
/// and a plain string is stored as itself rather than as a quoted JSON string,
/// which is what the app reads back with `getString`.
String _asPrefsString(Object? value) {
  if (value is String) return value;
  if (value == null) return '';
  if (value is Map || value is List) return jsonEncode(value);
  return '$value';
}

/// The MMKV native type to write back, defaulting to the current Dart type.
String _mmkvTargetType(StorageKeyInfo storageKey) {
  final declared = storageKey.valueType;
  if (declared != null) return declared;
  if (storageKey.value is num) return 'number';
  if (storageKey.value is bool) return 'boolean';
  return 'string';
}

Object _coerceMmkv(StorageKeyInfo storageKey, Object? next) =>
    switch (_mmkvTargetType(storageKey)) {
      'number' => next is num ? next : num.tryParse('$next') ?? 0,
      'boolean' => next is bool ? next : '$next'.trim().toLowerCase() == 'true',
      _ => _asPrefsString(next),
    };
