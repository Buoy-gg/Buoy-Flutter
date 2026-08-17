/// Ports packages/storage/src/storage/sync/storageSyncAdapter.ts and
/// utils/clearAllStorage.ts.
///
/// Field-for-field mirror of the RN adapter (version 3, same action names and
/// payload shapes) so Buoy Desktop panels and the MCP server work with zero
/// changes. Subscribing starts the capture lifecycle (including the initial key
/// scan), so storage events are only recorded while a dashboard is watching.
///
/// Read paths strip Buoy's OWN devtool keys (@react_buoy*, @buoy*, buoy-*) at
/// the source so no sync client ever sees them as app data — authoritative, not
/// UI-only, matching the RN adapter.
///
/// v2: oversized / unencodable event values are replaced with
/// [valueOnDevice]. Dashboards fetch them via `getEventDetail`.
/// v3: a total snapshot budget, so a burst of individually-legal values
/// degrades the oldest events instead of the emit layer dropping the panel.
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

/// Sentinel used in WIRE-FORM snapshots in place of oversized values.
/// Storage events, MMKV browse dumps, and SecureStore dumps all reuse this
/// marker. Dashboards fetch the real payload via `getEventDetail` / `mmkv.get`
/// / `secure.get`. Byte-identical to the RN constant — the desktop panel
/// matches on `__buoyValueOnDevice`.
const Map<String, Object?> valueOnDevice = {
  '__buoyValueOnDevice': true,
  'note':
      'Value stays on the device — fetched on demand via getEventDetail / mmkv.get / secure.get.',
};

/// Max approx bytes of one storage value on the list snapshot.
const int snapshotValueInlineLimit = 16 * 1024;

/// Total inline budget for one snapshot's event list, held under the emit
/// layer's 2MB so a snapshot is never DROPPED (a drop leaves the whole panel
/// stale). Per-value caps alone don't get there: the store keeps 500 events, so
/// 500 writes of an individually-legal 9KB value still total ~4.7MB. Newest
/// events keep their values inline; once the budget is spent, older ones
/// degrade to metadata + fetch-on-demand.
///
/// 1.25 * 1024 * 1024, spelled as an int because Dart const arithmetic on
/// doubles would make this a double.
const int snapshotEventsBudget = 1310720;

const int maxEventDetailBytes = 8 * 1024 * 1024;

Object? _toWireValue(Object? value) {
  if (value == null) return value;
  return isOverWireBudget(value, snapshotValueInlineLimit)
      ? valueOnDevice
      : value;
}

Object? _capDetailValue(Object? value) {
  if (value == null) return value;
  if (!isOverWireBudget(value, maxEventDetailBytes)) return value;
  return isJsonEncodable(value)
      ? {
          '__buoyTruncated': true,
          'note':
              'Exceeds the ${maxEventDetailBytes ~/ (1024 * 1024)}MB detail limit — inspect it on-device.',
        }
      : valueOnDevice;
}

/// Apply `map` to every payload field an event carries, on the JSON form.
///
/// RN deviation: the RN helper returns a `StorageEvent` and preserves object
/// identity when nothing changed. Here the wire form is built straight from
/// [StorageEvent.toJson] — reusing it is what keeps the field shape in lockstep
/// — and identity is moot because the payload crosses a socket either way.
///
/// RN also maps `pairs`/`prevPairs` for multiSet/multiRemove batches. The
/// Flutter capture polls shared_preferences and has no batch event, so
/// [StorageEvent] carries no such fields and there is nothing to map.
Map<String, Object?> _mapEventValues(
  StorageEvent event,
  Object? Function(Object?) map,
) {
  final json = event.toJson();
  final data = Map<String, Object?>.from(json['data']! as Map);
  // `toJson` omits null value/prevValue, so `containsKey` is the test — a
  // blind assignment would invent fields the RN wire form does not have.
  if (data.containsKey('value')) data['value'] = map(data['value']);
  if (data.containsKey('prevValue')) {
    data['prevValue'] = map(data['prevValue']);
  }
  json['data'] = data;
  return json;
}

/// One event's wire form plus its measured cost, so the budget pass is free.
class _WireEvent {
  const _WireEvent(this.json, this.bytes);
  final Map<String, Object?> json;
  final int bytes;
}

/// Per-event wire caches. The store never mutates an event in place, so keying
/// on identity is correct and self-invalidating. Without it every value is
/// re-measured on all ~5 snapshots per second for as long as it stays in the
/// list, which for storage means re-walking megabytes of strings per tick.
///
/// `Expando` is Dart's weak, identity-keyed map — the `WeakMap` the RN version
/// uses. Entries die with their event, so this cannot grow unbounded.
final Expando<_WireEvent> _wireCache = Expando<_WireEvent>('buoyStorageWire');
final Expando<_WireEvent> _strippedCache = Expando<_WireEvent>(
  'buoyStorageWireStripped',
);

_WireEvent _wireFor(StorageEvent event) {
  final cached = _wireCache[event];
  if (cached != null) return cached;
  _WireEvent entry;
  try {
    final wire = _mapEventValues(event, _toWireValue);
    entry = _WireEvent(wire, approxJsonSize(wire, snapshotEventsBudget).bytes);
  } catch (_) {
    // A hostile value can blow up the walk itself. Degrading this ONE event
    // beats letting getSnapshot throw and taking the whole panel with it.
    entry = _WireEvent(_mapEventValues(event, (_) => valueOnDevice), 1024);
  }
  _wireCache[event] = entry;
  return entry;
}

/// Metadata-only form for the tail of the list once the budget is spent.
_WireEvent _strippedFor(StorageEvent event) {
  final cached = _strippedCache[event];
  if (cached != null) return cached;
  final wire = _mapEventValues(
    event,
    (v) => v == null ? null : valueOnDevice,
  );
  final entry = _WireEvent(
    wire,
    approxJsonSize(wire, snapshotEventsBudget).bytes,
  );
  _strippedCache[event] = entry;
  return entry;
}

/// Spend the snapshot budget newest-first. The store keeps events newest-first,
/// so the developer keeps full detail on what they are actually looking at and
/// the tail degrades rather than the whole panel being dropped.
List<Map<String, Object?>> fitEventsToBudget(List<StorageEvent> events) {
  final out = <Map<String, Object?>>[];
  var spent = 0;
  for (final event in events) {
    final full = _wireFor(event);
    if (spent + full.bytes <= snapshotEventsBudget) {
      out.add(full.json);
      spent += full.bytes;
    } else {
      final lean = _strippedFor(event);
      out.add(lean.json);
      spent += lean.bytes;
    }
  }
  return out;
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
  // v3: a total snapshot budget, so a burst of individually-legal values
  // degrades the oldest events instead of the emit layer dropping the panel.
  version: 3,
  // Strip Buoy's own devtool keys at the source.
  getSnapshot: () => fitEventsToBudget([
    for (final e in StorageEventStore.instance.events)
      if (!isDevToolsStorageKey(e.key)) e,
  ]),
  subscribe: (onChange) =>
      StorageEventStore.instance.subscribeToEvents((_) => onChange()),
  actions: {
    'clearEvents': (_) {
      StorageEventStore.instance.clearEvents();
      return null;
    },

    /// On-demand detail: one event's real value/prevValue.
    /// The per-snapshot stream stays payload-light; this is the explicit,
    /// size-guarded channel for the detail pane (and for time-travel undo,
    /// which needs `prevValue`).
    'getEventDetail': (params) {
      final id = _asMap(params)?['id'] as String?;
      if (id == null) return {'found': false, 'reason': 'missing id'};
      final event = _eventById(StorageEventStore.instance.events, id);
      if (event == null) return {'found': false, 'reason': 'unknown id'};
      return {
        'found': true,
        'id': id,
        'event': _mapEventValues(event, _capDetailValue),
      };
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
    // Entry values go through the same inline cap as event values: the
    // dashboard POLLS this, so one oversized string would be re-sent on every
    // refresh. `mmkv.get` is the on-demand channel for the real value.
    'mmkv.snapshot': (_) => [
      for (final instance in buoyMmkvBackend?.snapshot() ?? const [])
        {
          ...instance,
          if (instance['entries'] is List)
            'entries': [
              for (final entry in instance['entries']! as List)
                if (entry is Map)
                  {
                    ...entry.cast<String, Object?>(),
                    'value': _toWireValue(entry['value']),
                  }
                else
                  entry,
            ],
        },
    ],

    /// On-demand MMKV value. `mmkv.snapshot` omits oversized strings so a
    /// browse poll cannot blow the action-result budget; this is the
    /// size-guarded channel for one key.
    'mmkv.get': (params) {
      final map = _asMap(params);
      final instanceId = map?['instanceId'] as String?;
      final key = map?['key'] as String?;
      if (instanceId == null || key == null) {
        return {'found': false, 'reason': 'missing instanceId/key'};
      }
      for (final instance in buoyMmkvBackend?.snapshot() ?? const []) {
        if (instance['id'] != instanceId) continue;
        final entries = instance['entries'];
        if (entries is! List) break;
        for (final entry in entries) {
          if (entry is! Map || entry['key'] != key) continue;
          return {
            'found': true,
            'instanceId': instanceId,
            'key': key,
            'value': _capDetailValue(entry['value']),
            'valueType': entry['valueType'],
          };
        }
        break;
      }
      return {'found': false, 'reason': 'unknown instance'};
    },
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
          // Wire shape is `string | null` (RN parity), never the placeholder —
          // except that an oversized value degrades to the VALUE_ON_DEVICE
          // marker, which the dashboard resolves through `secure.get`.
          'value': entry.requireAuthentication
              ? null
              : _toWireValue(entry.value?.toString()),
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
