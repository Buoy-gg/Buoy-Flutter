/// Ports packages/storage/src/storage/utils/storageTimeTravelUtils.ts —
/// UNDO / JUMP for async (shared_preferences) storage events.
///
/// The Dart event model carries a single `key`/`value`/`prevValue` per event
/// (the poll/diff monitor never synthesizes RN's multi*/mergeItem/clear shapes),
/// so only the single-key branches of the RN switch are ported. Restores are
/// deliberately NOT capture-paused (RN parity): each write emits an event via
/// [StorageEventStore.recordOwnedWrite] so the change is visible and history
/// stays honest — a write emits an event, and an event never triggers a write.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_capture.dart';

/// Whether [undoOperation] can restore this event (RN `canUndo`). MMKV/secure
/// events are not undoable — the UI never offers actions for them.
bool canUndo(StorageEvent event) {
  if (event.storageType != 'async') return false;
  return switch (event.action) {
    'setItem' || 'mergeItem' || 'removeItem' => event.key.isNotEmpty,
    _ => false,
  };
}

/// Undo a single storage operation by restoring the value captured before it
/// (RN `undoOperation`). A `setItem` whose key didn't exist before removes it.
Future<void> undoOperation(StorageEvent event) async {
  if (!canUndo(event)) return;
  switch (event.action) {
    case 'setItem':
    case 'mergeItem':
      await _restore(event.key, event.prevValue);
    case 'removeItem':
      if (event.prevValue != null) await _restore(event.key, event.prevValue);
  }
}

/// Reconstruct storage as of `events[targetIndex]` by replaying the timeline
/// into a state map, then reconciling ONLY the keys the timeline governs —
/// including keys created after the target, which are removed rather than left
/// behind. Buoy's own `@react_buoy*` keys are never touched (RN `jumpToState`).
///
/// [events] must be async events in chronological order (oldest first).
Future<void> jumpToState(List<StorageEvent> events, int targetIndex) async {
  if (targetIndex < 0 || targetIndex >= events.length) {
    throw RangeError('Invalid event index: $targetIndex');
  }

  final stateMap = <String, Object?>{};
  for (var i = 0; i <= targetIndex; i++) {
    final event = events[i];
    switch (event.action) {
      case 'setItem':
      case 'mergeItem':
        if (event.value != null) stateMap[event.key] = event.value;
      case 'removeItem':
        stateMap[event.key] = null;
      case 'clear':
        stateMap.clear();
    }
  }

  final governedKeys = <String>{for (final event in events) event.key};
  for (final key in governedKeys) {
    // Buoy's own settings are never app state to travel through.
    if (isDevToolsStorageKey(key)) continue;
    await _restore(key, stateMap[key]);
  }
}

/// Write (or remove, when [value] is null) one prefs key and emit the matching
/// owned-write event so the restore shows up in the stream immediately.
Future<void> _restore(String key, Object? value) async {
  final prefs = await SharedPreferences.getInstance();
  final prev = prefs.get(key);
  if (value == null) {
    await prefs.remove(key);
    StorageEventStore.instance.recordOwnedWrite(
      action: 'removeItem',
      key: key,
      prevValue: prev,
    );
    return;
  }
  await _setTyped(prefs, key, value);
  StorageEventStore.instance.recordOwnedWrite(
    action: 'setItem',
    key: key,
    value: value,
    prevValue: prev,
  );
}

/// Prefs values are typed; the event captured the live value, so dispatch on
/// its runtime type (String falls through to the `'$value'` write unchanged).
Future<void> _setTyped(SharedPreferences prefs, String key, Object value) async {
  if (value is bool) {
    await prefs.setBool(key, value);
  } else if (value is int) {
    await prefs.setInt(key, value);
  } else if (value is double) {
    await prefs.setDouble(key, value);
  } else if (value is List) {
    await prefs.setStringList(key, value.cast<String>());
  } else {
    await prefs.setString(key, '$value');
  }
}
