/// Ports packages/storage/src/storage/sync/storageSyncAdapter.ts and
/// utils/clearAllStorage.ts.
///
/// Field-for-field mirror of the RN adapter (version 1, same action names and
/// payload shapes) so Buoy Desktop panels and the MCP server work with zero
/// changes. Subscribing starts the capture lifecycle (including the initial key
/// scan), so storage events are only recorded while a dashboard is watching.
///
/// Read paths strip Buoy's OWN devtool keys (@react_buoy*, @buoy*, buoy-*) at
/// the source so no sync client ever sees them as app data — authoritative, not
/// UI-only, matching the RN adapter.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_capture.dart';
import 'storage_tool/storage_time_travel.dart';

Map<String, Object?>? _asMap(Object? params) {
  if (params is Map<String, Object?>) return params;
  if (params is Map) return params.cast<String, Object?>();
  return null;
}

String? _key(Object? params) => _asMap(params)?['key'] as String?;

/// Refuse writes to an instance the app registered read-only (RN parity — see
/// `assertMMKVWritable` in storageSyncAdapter.ts). The flag has always been in
/// the snapshot; nothing enforced it until the tool could edit values.
void _assertMmkvWritable(String instanceId) {
  final instances = buoyMmkvBackend?.snapshot() ?? const [];
  for (final instance in instances) {
    if (instance['id'] == instanceId && instance['readOnly'] == true) {
      throw StateError('MMKV instance "$instanceId" is registered read-only');
    }
  }
}

/// First event whose `id` matches, or null (avoids a package:collection dep).
StorageEvent? _eventById(Iterable<StorageEvent> events, String id) {
  for (final event in events) {
    if (event.id == id) return event;
  }
  return null;
}

/// Remove all app keys, preserving dev-tool settings (RN `clearAllAppStorage`).
Future<void> clearAppStorage() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys()) {
    if (!isDevToolsStorageKey(key)) await prefs.remove(key);
  }
}

/// The storage tool's sync adapter — mirrors storageSyncAdapter.ts.
final storageSyncAdapter = ToolSyncAdapter(
  version: 1,
  // Strip Buoy's own devtool keys at the source.
  getSnapshot: () => [
    for (final e in StorageEventStore.instance.events)
      if (!isDevToolsStorageKey(e.key)) e.toJson(),
  ],
  subscribe: (onChange) =>
      StorageEventStore.instance.subscribeToEvents((_) => onChange()),
  actions: {
    'clearEvents': (_) {
      StorageEventStore.instance.clearEvents();
      return null;
    },
    'clearAppStorage': (_) => clearAppStorage(),

    // ── Time travel (same code path as the modal's UNDO / JUMP buttons) ──
    // The UI swallows failures silently; these THROW so a caller (desktop, MCP)
    // gets the actual reason back instead of a no-op. Mirrors the RN adapter.

    /// Undo one event, addressed by the `id` the store assigned it.
    'timeTravel.undo': (params) async {
      final id = _asMap(params)?['id'] as String?;
      if (id == null) {
        throw ArgumentError('timeTravel.undo requires an event `id`');
      }
      final event = _eventById(StorageEventStore.instance.events, id);
      if (event == null) throw StateError('No storage event with id "$id"');
      if (event.storageType == 'mmkv') {
        throw StateError('Time travel supports AsyncStorage events only');
      }
      if (!canUndo(event)) {
        throw StateError(
          'Event "$id" (${event.action}) has no previous value captured, '
          'so it cannot be undone',
        );
      }
      await undoOperation(event);
      return {'undone': true, 'action': event.action, 'key': event.key};
    },

    /// Jump storage back to the state as of one event. `scope: "key"` (default)
    /// replays only that key's history, matching the modal's JUMP button;
    /// `scope: "all"` replays every captured AsyncStorage event.
    'timeTravel.jump': (params) async {
      final map = _asMap(params);
      final id = map?['id'] as String?;
      final scope = (map?['scope'] as String?) ?? 'key';
      if (id == null) {
        throw ArgumentError('timeTravel.jump requires an event `id`');
      }

      // Oldest-first, the order jumpToState replays in (getEvents is newest-first).
      final all = [
        for (final e in StorageEventStore.instance.events)
          if (e.storageType != 'mmkv') e,
      ].reversed.toList();

      final target = _eventById(all, id);
      if (target == null) throw StateError('No AsyncStorage event with id "$id"');

      final timeline = scope == 'all'
          ? all
          : [for (final e in all) if (e.key == target.key) e];
      final index = timeline.indexWhere((e) => e.id == id);
      if (index == -1) throw StateError('Event "$id" is not in the timeline');

      await jumpToState(timeline, index);
      return {
        'jumped': true,
        'scope': scope,
        'replayed': index + 1,
        'of': timeline.length,
        'key': target.key,
      };
    },

    // ── Remote shared_preferences proxy (desktop browse/edit mode) ──
    // Read paths filter out Buoy's own devtool keys so they're never exposed.
    'async.getAllKeys': (_) async {
      final prefs = await SharedPreferences.getInstance();
      return [
        for (final k in prefs.getKeys())
          if (!isDevToolsStorageKey(k)) k,
      ];
    },
    'async.multiGet': (params) async {
      final prefs = await SharedPreferences.getInstance();
      final keys = (_asMap(params)?['keys'] as List?)?.cast<String>() ?? const [];
      return [
        for (final k in keys)
          if (!isDevToolsStorageKey(k)) [k, prefs.get(k)],
      ];
    },
    'async.getItem': (params) async {
      final key = _key(params);
      if (key == null || isDevToolsStorageKey(key)) return null;
      final prefs = await SharedPreferences.getInstance();
      return prefs.get(key);
    },
    'async.setItem': (params) async {
      final map = _asMap(params);
      final key = map?['key'] as String?;
      if (key == null) return null;
      final prev = (await SharedPreferences.getInstance()).get(key);
      // Route through BuoyPrefs so the write surfaces immediately in the stream.
      final prefs = await BuoyPrefs.getInstance();
      final value = map?['value'];
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.map((e) => '$e').toList());
      } else {
        await prefs.setString(key, value?.toString() ?? '');
      }
      return prev;
    },
    'async.removeItem': (params) async {
      final key = _key(params);
      if (key == null) return null;
      await (await BuoyPrefs.getInstance()).remove(key);
      return null;
    },
    'async.multiRemove': (params) async {
      final keys = (_asMap(params)?['keys'] as List?)?.cast<String>() ?? const [];
      final prefs = await BuoyPrefs.getInstance();
      for (final k in keys) {
        await prefs.remove(k);
      }
      return null;
    },
    'async.multiSet': (params) async {
      final pairs = (_asMap(params)?['pairs'] as List?) ?? const [];
      final prefs = await BuoyPrefs.getInstance();
      for (final pair in pairs) {
        if (pair is List && pair.length >= 2 && pair[0] is String) {
          await prefs.setString(pair[0] as String, '${pair[1]}');
        }
      }
      return null;
    },
    'async.clear': (_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      return null;
    },

    // ── Remote MMKV proxy (registered backend or empty) ──
    'mmkv.snapshot': (_) => buoyMmkvBackend?.snapshot() ?? const [],
    'mmkv.set': (params) {
      final map = _asMap(params);
      final id = map?['instanceId'] as String?;
      final key = map?['key'] as String?;
      final value = map?['value'];
      if (id != null && key != null && value != null) {
        _assertMmkvWritable(id);
        buoyMmkvBackend?.set(id, key, value);
      }
      return null;
    },
    'mmkv.remove': (params) {
      final map = _asMap(params);
      final id = map?['instanceId'] as String?;
      final key = map?['key'] as String?;
      if (id != null && key != null) {
        _assertMmkvWritable(id);
        buoyMmkvBackend?.remove(id, key);
      }
      return null;
    },

    // ── Remote SecureStore proxy (registered backend or empty) ──
    'secure.keys': (_) => buoySecureBackend?.keys() ?? const [],
    // Every registered key WITH its value in one round trip. The dashboard
    // polls this — the keychain has no change feed, so a secure write produces
    // no event and nothing else would ever pull the dashboard forward.
    // Biometric-protected keys are listed but never read (that would prompt).
    'secure.snapshot': (_) async => [
      for (final entry in await readBuoySecureEntries())
        {
          'key': entry.key,
          'keychainService': entry.keychainService,
          'requireAuthentication': entry.requireAuthentication,
          // Wire shape is `string | null` (RN parity), never the placeholder.
          'value': entry.requireAuthentication ? null : entry.value?.toString(),
        },
    ],
    'secure.get': (params) async {
      final key = _key(params);
      if (key == null) return null;
      return buoySecureBackend?.get(key);
    },
    // Write a declared key. The backend owns the options the value was stored
    // with, exactly like the RN registry does — see BuoySecureBackend.set.
    'secure.set': (params) async {
      final map = _asMap(params);
      final key = map?['key'] as String?;
      final value = map?['value'] as String?;
      if (key == null || value == null) return null;
      final backend = buoySecureBackend;
      if (backend is! BuoySecureWritableBackend) {
        throw StateError(
          'The registered secure backend does not support writes '
          '(implement BuoySecureWritableBackend to enable editing)',
        );
      }
      await (backend as BuoySecureWritableBackend).set(key, value);
      return null;
    },
    'secure.delete': (params) async {
      final key = _key(params);
      if (key == null) return null;
      await buoySecureBackend?.delete(key);
      return null;
    },
  },
);
