/// Ports packages/storage/src/storage/stores/storageEventStore.ts and
/// utils/AsyncStorageListener.ts.
///
/// Flutter has no method-swizzling analog to RN's AsyncStorage interception,
/// and `shared_preferences` exposes no change stream. So the store monitors
/// writes two ways while capturing (intentional deviation — see storage.md):
///   1. an owned-write wrapper ([BuoyPrefs]) that emits an event when the host
///      app writes through it (parity with RN's swizzle when Buoy owns the write);
///   2. a 1000 ms poll/diff timer that snapshots all keys and synthesizes
///      `setItem`/`removeItem` events for any change made through any path.
/// An initial scan on start mirrors RN's `scanExistingState`.
///
/// Registered optional backends are monitored too: MMKV instances are
/// enumerable and cheap, so they ride the same scan + poll/diff (emitting RN's
/// `set.*`/`delete` MMKV actions); SecureStore is scanned once on start only —
/// every read hits the keychain, and `requireAuthentication` keys are never
/// read at all (RN parity: reading them fires a biometric prompt).
///
/// Buoy's own `@react_buoy*` keys are ignored by the monitor (RN parity: the
/// AsyncStorage listener ignores the tool's own keys to avoid self-trigger loops).
library;

import 'dart:async';
import 'dart:convert';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One storage event. Mirrors the RN `StorageEvent` union
/// (AsyncStorageEvent/MMKVEvent + storageType + id). `timestamp` serializes to
/// an ISO-8601 string over the wire, matching `JSON.stringify(new Date())` so
/// the desktop/MCP snapshot shape is identical.
class StorageEvent {
  StorageEvent({
    required this.id,
    required this.action,
    required this.timestamp,
    required this.storageType,
    required this.key,
    this.value,
    this.prevValue,
    this.initialScan = false,
    this.valueType,
    this.instanceId,
  });

  final String id;

  /// setItem | removeItem | clear | set.string | … (RN action strings).
  final String action;
  final DateTime timestamp;

  /// 'async' | 'mmkv' | 'secure'.
  final String storageType;
  final String key;
  final Object? value;
  final Object? prevValue;

  /// True for the synthetic events [_scanExistingState] emits for keys that
  /// already existed. These are a snapshot, not a write: the key already held
  /// this value, so there is no "before" state to diff against — which the
  /// detail view must say rather than claiming the key was created.
  final bool initialScan;

  /// MMKV native value type (string/number/boolean/buffer), when applicable.
  final String? valueType;
  final String? instanceId;

  /// Serialized event — the shape the RN adapter's `getSnapshot()` puts on the
  /// wire (Date → ISO string via JSON).
  Map<String, Object?> toJson() => {
    'id': id,
    'action': action,
    'timestamp': timestamp.toIso8601String(),
    'storageType': storageType,
    if (instanceId != null) 'instanceId': instanceId,
    'data': {
      'key': key,
      if (value != null) 'value': value,
      if (prevValue != null) 'prevValue': prevValue,
      if (initialScan) 'initialScan': true,
      if (valueType != null) 'valueType': valueType,
    },
  };
}

/// Optional secure-storage backend a host app can register so its keys appear
/// in the tool and the `secure.*` sync actions work. No native dep is pulled by
/// default. Mirrors packages/storage SecureStoreRegistry semantics.
abstract class BuoySecureBackend {
  /// Declared keys (SecureStore has no enumeration API).
  List<Map<String, Object?>> keys();
  Future<String?> get(String key);
  Future<void> delete(String key);
}

/// Opt-in write support for a secure backend, enabling the tool's value editor
/// and the `secure.set` action for those keys.
///
/// Deliberately a SEPARATE interface rather than a method on
/// [BuoySecureBackend]: hosts wire their backend up with `implements`, which
/// requires every member even when the base declaration has a body — so adding
/// `set` there would break every existing implementation. Backends that don't
/// implement this simply report that editing isn't available.
abstract class BuoySecureWritableBackend {
  /// Write a declared key, using whatever options it was stored with.
  Future<void> set(String key, String value);
}

/// Optional MMKV backend a host app can register (mirrors MMKVInstanceRegistry).
abstract class BuoyMmkvBackend {
  /// One entry per registered instance, RN `mmkv.snapshot` shape.
  List<Map<String, Object?>> snapshot();
  void set(String instanceId, String key, Object value);
  void remove(String instanceId, String key);
}

BuoySecureBackend? _secureBackend;
BuoyMmkvBackend? _mmkvBackend;

/// Register an optional secure-storage backend (e.g. a flutter_secure_storage
/// wrapper). Kept out of the default dep graph.
void registerBuoySecureBackend(BuoySecureBackend backend) =>
    _secureBackend = backend;

/// Register an optional MMKV backend.
void registerBuoyMmkvBackend(BuoyMmkvBackend backend) => _mmkvBackend = backend;

BuoySecureBackend? get buoySecureBackend => _secureBackend;
BuoyMmkvBackend? get buoyMmkvBackend => _mmkvBackend;

/// One flattened MMKV entry (an instance's key/value pair).
class MmkvEntry {
  const MmkvEntry({
    required this.instanceId,
    required this.key,
    required this.value,
    this.valueType,
  });

  final String instanceId;
  final String key;
  final Object? value;

  /// MMKV native value type — string | number | boolean | buffer.
  final String? valueType;
}

/// One registered SecureStore key, read through the backend.
class SecureEntry {
  const SecureEntry({
    required this.key,
    required this.value,
    this.keychainService,
    this.requireAuthentication = false,
  });

  final String key;

  /// Null when the key is unset — or when it is biometric-protected, in which
  /// case it is deliberately never read.
  final Object? value;
  final String? keychainService;
  final bool requireAuthentication;
}

/// Placeholder shown for `requireAuthentication` keys — reading them would fire
/// a biometric prompt, so the tool lists them without reading (RN parity).
const secureBiometricPlaceholder = '•••••• (biometric protected)';

/// Diff key for one MMKV slot (NUL separator — can't appear in either part).
String _mmkvSlot(String instanceId, String key) => '$instanceId\u0000$key';

/// RN MMKV action name for a value type (`set.string` | `set.number` | …).
String mmkvSetAction(String? valueType) => switch (valueType) {
  'number' => 'set.number',
  'boolean' => 'set.boolean',
  'buffer' => 'set.buffer',
  _ => 'set.string',
};

/// Flatten every registered MMKV instance into entries keyed by instance+key.
/// Empty when no backend is registered. Buoy's own keys are excluded.
Map<String, MmkvEntry> readBuoyMmkvEntries() {
  final result = <String, MmkvEntry>{};
  final backend = _mmkvBackend;
  // Always modifiable: the store keeps the returned map as its diff baseline
  // and patches it on owned writes.
  if (backend == null) return result;
  for (final instance in backend.snapshot()) {
    final instanceId = instance['id'] as String? ?? 'default';
    final entries = instance['entries'] as List? ?? const [];
    for (final raw in entries) {
      if (raw is! Map) continue;
      final key = raw['key'] as String?;
      if (key == null || isDevToolsStorageKey(key)) continue;
      result[_mmkvSlot(instanceId, key)] = MmkvEntry(
        instanceId: instanceId,
        key: key,
        value: raw['value'],
        valueType: raw['valueType'] as String?,
      );
    }
  }
  return result;
}

/// Read every registered SecureStore key. Biometric-protected keys are listed
/// with [secureBiometricPlaceholder] instead of being read. Empty when no
/// backend is registered.
Future<List<SecureEntry>> readBuoySecureEntries() async {
  final backend = _secureBackend;
  if (backend == null) return const [];
  final result = <SecureEntry>[];
  for (final descriptor in backend.keys()) {
    final key = descriptor['key'] as String?;
    if (key == null || isDevToolsStorageKey(key)) continue;
    final keychainService = descriptor['keychainService'] as String?;
    if (descriptor['requireAuthentication'] == true) {
      result.add(SecureEntry(
        key: key,
        value: secureBiometricPlaceholder,
        keychainService: keychainService,
        requireAuthentication: true,
      ));
      continue;
    }
    Object? value;
    try {
      value = await backend.get(key);
    } catch (_) {
      // Key unreadable (e.g. keychain state changed) — surface it as unset.
    }
    result.add(SecureEntry(
      key: key,
      value: value,
      keychainService: keychainService,
    ));
  }
  return result;
}

int _eventIdCounter = 0;
String _nextEventId() =>
    'se-${DateTime.now().millisecondsSinceEpoch}-${++_eventIdCounter}';

/// Aggregated storage event store. Extends [BaseEventStore] so it self-manages
/// the capture lifecycle (start on first subscriber, stop on last) exactly like
/// the RN store; the poll/diff monitor + initial scan run inside
/// [startCapturing]/[stopCapturing].
class StorageEventStore extends BaseEventStore<StorageEvent> {
  StorageEventStore._() : super(storeName: 'storage', maxEvents: 500);
  static final StorageEventStore instance = StorageEventStore._();

  /// Poll interval — shared_preferences has no change stream (deviation).
  static const Duration pollInterval = Duration(seconds: 1);

  Timer? _pollTimer;
  bool _capturing = false;
  bool _scanned = false;

  /// Last observed prefs snapshot (encoded per value for cheap diffing).
  Map<String, Object?> _lastSnapshot = {};

  /// Last observed MMKV snapshot, keyed by instance+key (see [_mmkvSlot]).
  Map<String, MmkvEntry> _lastMmkv = {};

  @override
  bool isCapturing() => _capturing;

  @override
  void startCapturing() {
    if (_capturing) return;
    _capturing = true;
    // Initial scan + start the poll loop. Fire-and-forget: BaseEventStore's
    // start hook is synchronous.
    unawaited(_scanExistingState());
    _pollTimer ??= Timer.periodic(pollInterval, (_) => _pollDiff());
  }

  @override
  void stopCapturing() {
    _capturing = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Whether the monitor should ignore [key] — Buoy's own dev-tool keys, to
  /// avoid self-trigger loops (RN's AsyncStorageListener.shouldIgnoreKey).
  static bool _ignoreKey(String key) => isDevToolsStorageKey(key);

  String _encode(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }

  /// Read every prefs key/value pair (dev-tool keys excluded).
  Future<Map<String, Object?>> _readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (_ignoreKey(key)) continue;
      result[key] = prefs.get(key);
    }
    return result;
  }

  /// RN `scanExistingState`: synthesize a `setItem` per existing key so the
  /// events stream reflects current state, not just post-start changes. Runs
  /// once per store lifetime.
  Future<void> _scanExistingState() async {
    if (_scanned) return;
    _scanned = true;
    final now = DateTime.now();
    final snapshot = await _readAll();
    _lastSnapshot = snapshot;
    for (final entry in snapshot.entries) {
      addEvent(StorageEvent(
        id: _nextEventId(),
        action: 'setItem',
        timestamp: now,
        storageType: 'async',
        key: entry.key,
        value: entry.value,
        initialScan: true,
      ));
    }

    // Registered MMKV instances (enumerable — also polled below).
    _lastMmkv = readBuoyMmkvEntries();
    for (final entry in _lastMmkv.values) {
      addEvent(StorageEvent(
        id: _nextEventId(),
        action: mmkvSetAction(entry.valueType),
        timestamp: now,
        storageType: 'mmkv',
        key: entry.key,
        value: entry.value,
        valueType: entry.valueType,
        instanceId: entry.instanceId,
        initialScan: true,
      ));
    }

    // Registered SecureStore keys — scanned once only (each read hits the
    // keychain), and biometric-protected keys are never read.
    for (final entry in await readBuoySecureEntries()) {
      addEvent(StorageEvent(
        id: _nextEventId(),
        action: 'setItem',
        timestamp: now,
        storageType: 'secure',
        key: entry.key,
        value: entry.value,
        instanceId: entry.keychainService,
        initialScan: true,
      ));
    }
  }

  /// Poll + diff against the previous snapshot, synthesizing add/change
  /// (`setItem`) and delete (`removeItem`) events.
  Future<void> _pollDiff() async {
    if (!_capturing) return;
    final now = DateTime.now();
    final snapshot = await _readAll();
    final old = _lastSnapshot;

    // Added / changed.
    for (final entry in snapshot.entries) {
      final key = entry.key;
      final hadKey = old.containsKey(key);
      if (!hadKey || _encode(old[key]) != _encode(entry.value)) {
        addEvent(StorageEvent(
          id: _nextEventId(),
          action: 'setItem',
          timestamp: now,
          storageType: 'async',
          key: key,
          value: entry.value,
          prevValue: hadKey ? old[key] : null,
        ));
      }
    }
    // Removed.
    for (final key in old.keys) {
      if (!snapshot.containsKey(key)) {
        addEvent(StorageEvent(
          id: _nextEventId(),
          action: 'removeItem',
          timestamp: now,
          storageType: 'async',
          key: key,
          prevValue: old[key],
        ));
      }
    }
    _lastSnapshot = snapshot;
    _pollMmkvDiff(now);
  }

  /// Poll + diff the registered MMKV instances, synthesizing RN's MMKV actions
  /// (`set.string`/`set.number`/… and `delete`).
  void _pollMmkvDiff(DateTime now) {
    if (_mmkvBackend == null) return;
    final snapshot = readBuoyMmkvEntries();
    final old = _lastMmkv;

    for (final slot in snapshot.entries) {
      final entry = slot.value;
      final prev = old[slot.key];
      if (prev == null || _encode(prev.value) != _encode(entry.value)) {
        addEvent(StorageEvent(
          id: _nextEventId(),
          action: mmkvSetAction(entry.valueType),
          timestamp: now,
          storageType: 'mmkv',
          key: entry.key,
          value: entry.value,
          prevValue: prev?.value,
          valueType: entry.valueType,
          instanceId: entry.instanceId,
        ));
      }
    }
    for (final slot in old.entries) {
      if (snapshot.containsKey(slot.key)) continue;
      addEvent(StorageEvent(
        id: _nextEventId(),
        action: 'delete',
        timestamp: now,
        storageType: 'mmkv',
        key: slot.value.key,
        prevValue: slot.value.value,
        instanceId: slot.value.instanceId,
      ));
    }
    _lastMmkv = snapshot;
  }

  /// Emit an owned-write event immediately (called by [BuoyPrefs], or by a host
  /// app's secure/MMKV backend wrapper) and refresh the diff baseline so the
  /// poll doesn't re-emit it.
  void recordOwnedWrite({
    required String action,
    required String key,
    Object? value,
    Object? prevValue,
    String storageType = 'async',
    String? valueType,
    String? instanceId,
  }) {
    if (!_capturing || _ignoreKey(key)) return;
    addEvent(StorageEvent(
      id: _nextEventId(),
      action: action,
      timestamp: DateTime.now(),
      storageType: storageType,
      key: key,
      value: value,
      prevValue: prevValue,
      valueType: valueType,
      instanceId: instanceId,
    ));
    if (storageType == 'mmkv') {
      final slot = _mmkvSlot(instanceId ?? 'default', key);
      if (value == null) {
        _lastMmkv.remove(slot);
      } else {
        _lastMmkv[slot] = MmkvEntry(
          instanceId: instanceId ?? 'default',
          key: key,
          value: value,
          valueType: valueType,
        );
      }
      return;
    }
    if (storageType != 'async') return;
    if (value == null) {
      _lastSnapshot.remove(key);
    } else {
      _lastSnapshot[key] = value;
    }
  }

  List<StorageEvent> get events => getEvents();
}

/// Owned-write facade over [SharedPreferences]. Writes go through the real
/// prefs and immediately emit a monitor event, so a value the host app writes
/// through Buoy shows up in the Events stream without waiting for the next poll
/// (parity with RN's swizzle interception for writes Buoy "owns").
class BuoyPrefs {
  const BuoyPrefs(this._prefs);

  final SharedPreferences _prefs;

  static Future<BuoyPrefs> getInstance() async =>
      BuoyPrefs(await SharedPreferences.getInstance());

  Future<bool> setString(String key, String value) =>
      _write(key, value, () => _prefs.setString(key, value));
  Future<bool> setBool(String key, bool value) =>
      _write(key, value, () => _prefs.setBool(key, value));
  Future<bool> setInt(String key, int value) =>
      _write(key, value, () => _prefs.setInt(key, value));
  Future<bool> setDouble(String key, double value) =>
      _write(key, value, () => _prefs.setDouble(key, value));
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, value, () => _prefs.setStringList(key, value));

  Future<bool> remove(String key) async {
    final prev = _prefs.get(key);
    final ok = await _prefs.remove(key);
    StorageEventStore.instance
        .recordOwnedWrite(action: 'removeItem', key: key, prevValue: prev);
    return ok;
  }

  Future<bool> _write(
    String key,
    Object value,
    Future<bool> Function() run,
  ) async {
    final prev = _prefs.get(key);
    final ok = await run();
    StorageEventStore.instance.recordOwnedWrite(
      action: 'setItem',
      key: key,
      value: value,
      prevValue: prev,
    );
    return ok;
  }
}
