/// Ports packages/network/src/network/utils/networkSavedStore.ts — pinned and
/// saved network requests.
///
/// The live [NetworkEventStore] is volatile by design: it caps at 500 events
/// and `clear()` wipes it. So "pin this failure so I don't lose it" cannot be
/// an id pointing into that store — it has to be a SNAPSHOT that outlives the
/// stream. This store owns those snapshots and persists them.
///
/// Two independent flags per record:
///   - `pinned` — hoisted into the PINNED section at the top of the list,
///     unaffected by search/filters.
///   - `saved`  — kept in the Saved screen, out of the live stream.
/// A record exists while either flag is true and is dropped when both go false,
/// so all four states fall out without special cases.
///
/// IDENTITY WARNING: ids are minted from a per-runtime counter, so after a
/// restart `flt-…-1` is a DIFFERENT request. Records are keyed on a generated
/// [SavedNetworkRecord.key], carry the [sessionId] that captured them, and only
/// trust `liveId` while that session is the current one. Snapshots restored
/// from an earlier session get their event id rewritten to `saved:<key>` so a
/// restored pin can never resolve to an unrelated live request.
///
/// Deviation from RN: no remote-mirror mode (the Flutter tool never runs on the
/// desktop) and no free-tier gate (`licenseKey` is only forwarded to the
/// broker), matching the rest of this port.
library;

import 'dart:async';
import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../network_capture.dart';

/// Identifies THIS runtime. Records from other sessions can't trust `liveId`.
final String sessionId =
    '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_'
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36).substring(3)}';

/// Pins render un-virtualized above the list, so the count stays bounded.
const int maxPinned = 25;

/// Upper bound on the persisted favorites list (oldest unpinned evicted).
const int maxSaved = 50;

/// Per-body cap on a snapshot.
const int _bodyLimit = 16 * 1024;

/// Total body bytes kept across ALL records.
///
/// shared_preferences is a single plist/XML blob, so an unbounded pin list
/// would grow the whole file. Bodies are dropped oldest-first, pins last; the
/// record itself always survives.
const int _totalBodyBudget = 512 * 1024;

/// Why a toggle didn't take effect, so the UI can explain itself.
enum SavedToggleFailure { pinCap, savedCap, invalidEvent }

class SavedToggleResult {
  const SavedToggleResult.ok(this.active)
    : succeeded = true,
      reason = null;
  const SavedToggleResult.failed(this.reason)
    : succeeded = false,
      active = false;

  final bool succeeded;
  final bool active;
  final SavedToggleFailure? reason;
}

class SavedNetworkRecord {
  SavedNetworkRecord({
    required this.key,
    required this.event,
    required this.pinned,
    required this.saved,
    required this.savedAt,
    required this.recordSessionId,
    required this.liveId,
    this.bodyTruncated = false,
  });

  /// Stable across app launches — unlike `event.id`.
  final String key;

  /// Frozen snapshot; bodies may be truncated (see [bodyTruncated]).
  NetworkCaptureEvent event;
  bool pinned;
  bool saved;
  final int savedAt;

  /// Runtime that captured the request.
  final String recordSessionId;

  /// `event.id` within [recordSessionId] — meaningless in any other session.
  final String liveId;

  /// A request/response body was too large to keep in full.
  bool bodyTruncated;

  Map<String, Object?> toJson() => {
    'key': key,
    'event': event.toJson(),
    'pinned': pinned,
    'saved': saved,
    'savedAt': savedAt,
    'sessionId': recordSessionId,
    'liveId': liveId,
    if (bodyTruncated) 'bodyTruncated': true,
  };
}

/// The derived view, rebuilt once per mutation.
class NetworkSavedState {
  const NetworkSavedState({
    required this.records,
    required this.pinnedEvents,
    required this.savedRecords,
    required this.pinnedLiveIds,
    required this.savedLiveIds,
  });

  const NetworkSavedState.empty()
    : records = const [],
      pinnedEvents = const [],
      savedRecords = const [],
      pinnedLiveIds = const {},
      savedLiveIds = const {};

  final List<SavedNetworkRecord> records;

  /// Pinned snapshots, newest first — what the PINNED section renders.
  final List<NetworkCaptureEvent> pinnedEvents;

  /// Saved records, newest first — what the Saved screen renders.
  final List<SavedNetworkRecord> savedRecords;

  /// Live ids pinned IN THIS SESSION (row glyphs + list dedupe).
  final Set<String> pinnedLiveIds;

  /// Live ids saved IN THIS SESSION (row glyphs).
  final Set<String> savedLiveIds;
}

/// Read an event's flags out of a state snapshot.
///
/// Two lookups because an event id means two different things: a live request
/// matches by `liveId` (the fast Set path), while a snapshot restored from an
/// earlier session carries the namespaced `saved:<key>` id and has to be found
/// among the records.
({bool pinned, bool saved}) flagsForEventId(
  NetworkSavedState state,
  String? eventId,
) {
  if (eventId == null) return (pinned: false, saved: false);
  final pinned = state.pinnedLiveIds.contains(eventId);
  final saved = state.savedLiveIds.contains(eventId);
  if (pinned || saved) return (pinned: pinned, saved: saved);
  for (final record in state.records) {
    if (record.event.id == eventId) {
      return (pinned: record.pinned, saved: record.saved);
    }
  }
  return (pinned: false, saved: false);
}

/// Is this actually an event we can store and re-render later?
///
/// This store WRITES TO DISK, which turns "accept whatever you're handed" into
/// a permanent failure: a bad value becomes a record, the record is persisted,
/// and every render of the pinned strip throws on it — a crash loop that
/// survives restarts. `id` and `url` are what the row and detail views
/// dereference without guarding, so they are the bar for admission.
bool _isStorableEvent(Object? value) =>
    value is NetworkCaptureEvent && value.id.isNotEmpty && value.url.isNotEmpty;

class NetworkSavedStore {
  NetworkSavedStore._();
  static final NetworkSavedStore instance = NetworkSavedStore._();

  final BuoyStorage _storage = BuoyStorage();
  final List<void Function()> _listeners = [];

  List<SavedNetworkRecord> _records = [];
  NetworkSavedState _state = const NetworkSavedState.empty();

  /// Live ids tracked in THIS session. [syncFromLive] runs on every captured
  /// response, so the hot path has to be a Set membership test.
  Set<String> _trackedLiveIds = {};

  bool _loaded = false;
  bool _dirty = false;
  Future<void>? _loadFuture;
  Timer? _persistTimer;
  int _keyCounter = 0;

  NetworkSavedState get state => _state;
  List<SavedNetworkRecord> get records => List.unmodifiable(_records);

  bool isPinned(String liveId) => _state.pinnedLiveIds.contains(liveId);
  bool isSaved(String liveId) => _state.savedLiveIds.contains(liveId);

  void Function() subscribe(void Function() onChange) {
    _listeners.add(onChange);
    unawaited(ensureLoaded());
    return () => _listeners.remove(onChange);
  }

  /// Resolve an event the live store no longer has — a pin whose request was
  /// cleared or aged out, or a snapshot restored from an earlier session.
  NetworkCaptureEvent? getEventById(String id) {
    for (final record in _records) {
      if (record.event.id == id) return record.event;
    }
    return null;
  }

  /// Keep a tracked snapshot current while its request is still in flight —
  /// pinning a pending request would otherwise freeze it as "Pending" forever.
  /// Called for every response/error, so the no-op path is one Set check.
  void syncFromLive(NetworkCaptureEvent event) {
    if (_trackedLiveIds.isEmpty) return;
    if (!_trackedLiveIds.contains(event.id)) return;
    final index = _records.indexWhere(
      (record) =>
          record.recordSessionId == sessionId && record.liveId == event.id,
    );
    if (index == -1) return;
    final frozen = _snapshot(event);
    _records[index].event = frozen.event;
    _records[index].bodyTruncated = frozen.truncated;
    _commit(_records);
  }

  SavedToggleResult togglePin(NetworkCaptureEvent event) =>
      _setFlag(event, pinned: true);

  SavedToggleResult toggleSave(NetworkCaptureEvent event) =>
      _setFlag(event, pinned: false);

  /// Drop a record outright, whatever its flags.
  void remove(String key) {
    if (!_records.any((record) => record.key == key)) return;
    _commit(_records.where((record) => record.key != key).toList());
  }

  /// Empty the favorites list; pinned-only records stay pinned.
  void clearSaved() {
    if (!_records.any((record) => record.saved)) return;
    final next = _records.where((record) => record.pinned).toList();
    for (final record in next) {
      record.saved = false;
    }
    _commit(next);
  }

  /// Unpin everything; saved-only records stay saved.
  void clearPinned() {
    if (!_records.any((record) => record.pinned)) return;
    final next = _records.where((record) => record.saved).toList();
    for (final record in next) {
      record.pinned = false;
    }
    _commit(next);
  }

  SavedToggleResult _setFlag(
    NetworkCaptureEvent event, {
    required bool pinned,
  }) {
    // Gate every write on a real event — see [_isStorableEvent]. Rejecting here
    // is what keeps a bad caller from becoming persisted, crash-looping state.
    if (!_isStorableEvent(event)) {
      return const SavedToggleResult.failed(SavedToggleFailure.invalidEvent);
    }

    final existing = _findRecordFor(event);

    if (existing != null) {
      final next = pinned ? !existing.pinned : !existing.saved;
      if (next && !_hasRoomFor(pinned: pinned, exceptKey: existing.key)) {
        return SavedToggleResult.failed(
          pinned ? SavedToggleFailure.pinCap : SavedToggleFailure.savedCap,
        );
      }
      if (pinned) {
        existing.pinned = next;
      } else {
        existing.saved = next;
      }
      _commit(
        existing.pinned || existing.saved
            ? _records
            : _records.where((record) => record.key != existing.key).toList(),
      );
      return SavedToggleResult.ok(next);
    }

    if (!_hasRoomFor(pinned: pinned, exceptKey: null)) {
      return SavedToggleResult.failed(
        pinned ? SavedToggleFailure.pinCap : SavedToggleFailure.savedCap,
      );
    }

    final frozen = _snapshot(event);
    final record = SavedNetworkRecord(
      key: '${sessionId}_${++_keyCounter}',
      event: frozen.event,
      pinned: pinned,
      saved: !pinned,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      recordSessionId: sessionId,
      liveId: event.id,
      bodyTruncated: frozen.truncated,
    );
    _commit(_evictIfNeeded([record, ..._records]));
    return const SavedToggleResult.ok(true);
  }

  /// Match an event to its record: by live id within this session, or by the
  /// namespaced snapshot id when the row being toggled IS a restored snapshot.
  SavedNetworkRecord? _findRecordFor(NetworkCaptureEvent event) {
    for (final record in _records) {
      if (record.event.id == event.id) return record;
      if (record.recordSessionId == sessionId && record.liveId == event.id) {
        return record;
      }
    }
    return null;
  }

  bool _hasRoomFor({required bool pinned, required String? exceptKey}) {
    final limit = pinned ? maxPinned : maxSaved;
    var count = 0;
    for (final record in _records) {
      if ((pinned ? record.pinned : record.saved) && record.key != exceptKey) {
        count++;
      }
    }
    return count < limit;
  }

  /// Trim the oldest UNPINNED saves once the list outgrows [maxSaved].
  List<SavedNetworkRecord> _evictIfNeeded(List<SavedNetworkRecord> records) {
    final saved = records.where((record) => record.saved).toList();
    if (saved.length <= maxSaved) return records;
    final evictable = saved.where((record) => !record.pinned).toList()
      ..sort((a, b) => a.savedAt.compareTo(b.savedAt));
    final drop = evictable.take(saved.length - maxSaved).map((r) => r.key);
    if (drop.isEmpty) return records;
    final dropped = drop.toSet();
    return records.where((record) => !dropped.contains(record.key)).toList();
  }

  // ── Snapshots + budget ─────────────────────────────────────────────────────

  ({NetworkCaptureEvent event, bool truncated}) _snapshot(
    NetworkCaptureEvent event,
  ) {
    final request = _truncate(event.requestData);
    final response = _truncate(event.responseData);
    final copy = _cloneEvent(event)
      ..requestData = request.value
      ..responseData = response.value;
    return (
      event: copy,
      truncated: request.truncated || response.truncated,
    );
  }

  ({Object? value, bool truncated}) _truncate(Object? data) {
    if (data == null) return (value: null, truncated: false);
    if (data is String) {
      if (data.length <= _bodyLimit) return (value: data, truncated: false);
      return (
        value:
            '${data.substring(0, _bodyLimit)}\n\n… truncated by Buoy '
            '(body exceeded $_bodyLimit bytes)',
        truncated: true,
      );
    }
    try {
      final serialized = jsonEncode(data);
      if (serialized.length <= _bodyLimit) {
        return (value: data, truncated: false);
      }
      return (
        value:
            '${serialized.substring(0, _bodyLimit)}\n\n… truncated by Buoy '
            '(body exceeded $_bodyLimit bytes)',
        truncated: true,
      );
    } catch (_) {
      // Unserializable — it can't be persisted anyway.
      return (value: '[unserializable body]', truncated: true);
    }
  }

  int _bodyBytes(NetworkCaptureEvent event) {
    var total = 0;
    if (event.requestData != null) {
      total += (event.requestSize ?? 0).clamp(0, _bodyLimit);
    }
    if (event.responseData != null) {
      total += (event.responseSize ?? 0).clamp(0, _bodyLimit);
    }
    return total;
  }

  /// Enforce [_totalBodyBudget] by stripping bodies from the least important
  /// records first (oldest, unpinned). The record itself — URL, status,
  /// headers, timings, the error — always survives; only the payload goes.
  List<SavedNetworkRecord> _applyBodyBudget(List<SavedNetworkRecord> records) {
    var total = 0;
    for (final record in records) {
      total += _bodyBytes(record.event);
    }
    if (total <= _totalBodyBudget) return records;

    final priority = List.of(records)
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.savedAt.compareTo(a.savedAt);
      });

    final stripped = <String>{};
    var kept = 0;
    for (final record in priority) {
      final size = _bodyBytes(record.event);
      if (kept + size <= _totalBodyBudget) {
        kept += size;
      } else {
        stripped.add(record.key);
      }
    }
    if (stripped.isEmpty) return records;

    for (final record in records) {
      if (!stripped.contains(record.key)) continue;
      record.event
        ..requestData = null
        ..responseData = null;
      record.bodyTruncated = true;
    }
    return records;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final stored = await _storage.loadJson(
        devToolsStorageKeys.network.saved(),
      );
      // A pin may have raced this read — never overwrite user intent.
      if (stored != null && !_dirty) {
        _records = _parseRecords(stored['records']);
        _rebuild();
      }
    } catch (_) {
      // Corrupt or unreadable — start empty rather than crashing the tool.
    } finally {
      _loaded = true;
      _emit();
    }
  }

  List<SavedNetworkRecord> _parseRecords(Object? raw) {
    if (raw is! List) return [];
    final parsed = <SavedNetworkRecord>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final key = entry['key'];
      if (key is! String) continue;
      if (entry['pinned'] != true && entry['saved'] != true) continue;
      // The restored snapshot's id is a stale per-runtime counter, so it is
      // rewritten to one that can never collide with a live request.
      final event = _eventFromJson(entry['event'], idOverride: 'saved:$key');
      // Not just "is an object" — a record whose event can't be rendered would
      // crash the list on every launch, and storage is forever. Drop it.
      if (event == null) continue;
      parsed.add(
        SavedNetworkRecord(
          key: key,
          event: event,
          pinned: entry['pinned'] == true,
          saved: entry['saved'] == true,
          savedAt: entry['savedAt'] is num
              ? (entry['savedAt'] as num).toInt()
              : 0,
          recordSessionId: entry['sessionId'] is String
              ? entry['sessionId'] as String
              : 'unknown',
          liveId: entry['liveId'] is String ? entry['liveId'] as String : '',
          bodyTruncated: entry['bodyTruncated'] == true,
        ),
      );
    }
    return parsed;
  }

  void _commit(List<SavedNetworkRecord> next) {
    _dirty = true;
    // The budget is applied at COMMIT, not at persist, so what the UI shows is
    // exactly what survives a reload — no silently-vanishing bodies.
    _records = _applyBodyBudget(next);
    _rebuild();
    _emit();
    _persist();
  }

  /// Rebuild the derived view once per mutation.
  void _rebuild() {
    final pinnedEvents = <NetworkCaptureEvent>[];
    final savedRecords = <SavedNetworkRecord>[];
    final pinnedLiveIds = <String>{};
    final savedLiveIds = <String>{};
    final tracked = <String>{};

    for (final record in _records) {
      if (record.pinned) pinnedEvents.add(record.event);
      if (record.saved) savedRecords.add(record);
      if (record.recordSessionId != sessionId || record.liveId.isEmpty) {
        continue;
      }
      tracked.add(record.liveId);
      if (record.pinned) pinnedLiveIds.add(record.liveId);
      if (record.saved) savedLiveIds.add(record.liveId);
    }

    _trackedLiveIds = tracked;
    _state = NetworkSavedState(
      records: _records,
      pinnedEvents: pinnedEvents,
      savedRecords: savedRecords,
      pinnedLiveIds: pinnedLiveIds,
      savedLiveIds: savedLiveIds,
    );
  }

  void _emit() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 500), () {
      _persistTimer = null;
      unawaited(_writeNow());
    });
  }

  Future<void> _writeNow() async {
    try {
      await _storage.saveJson(devToolsStorageKeys.network.saved(), {
        'records': [for (final record in _records) record.toJson()],
      });
    } catch (_) {
      // Best-effort; records remain in memory for this session.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _records = [];
    _state = const NetworkSavedState.empty();
    _trackedLiveIds = {};
    _loaded = true;
    _dirty = false;
    _loadFuture = null;
    _listeners.clear();
  }
}

// ── Event (de)serialization ──────────────────────────────────────────────────

/// A record keeps its OWN copy of the event: the live one keeps mutating as the
/// response streams in, and a pin is supposed to be frozen.
NetworkCaptureEvent _cloneEvent(NetworkCaptureEvent event) =>
    NetworkCaptureEvent(
        id: event.id,
        method: event.method,
        url: event.url,
        timestamp: event.timestamp,
        requestClient: event.requestClient,
        requestHeaders: Map.of(event.requestHeaders),
      )
      ..responseHeaders = Map.of(event.responseHeaders)
      ..status = event.status
      ..statusText = event.statusText
      ..requestData = event.requestData
      ..responseData = event.responseData
      ..requestSize = event.requestSize
      ..responseSize = event.responseSize
      ..duration = event.duration
      ..error = event.error
      ..responseType = event.responseType
      ..operationName = event.operationName
      ..graphqlVariables = event.graphqlVariables
      ..override = event.override;

NetworkCaptureEvent? _eventFromJson(Object? raw, {String? idOverride}) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final url = raw['url'];
  if (id is! String || id.isEmpty) return null;
  if (url is! String || url.isEmpty) return null;

  Map<String, String> headers(Object? value) => value is Map
      ? {
          for (final entry in value.entries)
            entry.key.toString(): '${entry.value}',
        }
      : const {};

  return NetworkCaptureEvent(
      id: idOverride ?? id,
      method: raw['method'] is String ? raw['method'] as String : 'GET',
      url: url,
      timestamp: raw['timestamp'] is num
          ? (raw['timestamp'] as num).toInt()
          : 0,
      requestClient: raw['requestClient'] is String
          ? raw['requestClient'] as String
          : 'http',
      requestHeaders: headers(raw['requestHeaders']),
    )
    ..responseHeaders = headers(raw['responseHeaders'])
    ..status = raw['status'] is num ? (raw['status'] as num).toInt() : null
    ..statusText = raw['statusText'] as String?
    ..requestData = raw['requestData']
    ..responseData = raw['responseData']
    ..requestSize = raw['requestSize'] is num
        ? (raw['requestSize'] as num).toInt()
        : null
    ..responseSize = raw['responseSize'] is num
        ? (raw['responseSize'] as num).toInt()
        : null
    ..duration = raw['duration'] is num
        ? (raw['duration'] as num).toInt()
        : null
    ..error = raw['error'] as String?
    ..responseType = raw['responseType'] as String?
    ..operationName = raw['operationName'] as String?;
}
