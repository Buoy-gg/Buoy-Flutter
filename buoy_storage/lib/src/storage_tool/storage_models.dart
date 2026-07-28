/// Ports packages/storage/src/storage/types.ts (StorageKeyInfo) and the
/// `StorageKeyConversation` shape from StorageModalWithTabs.tsx.
library;

import '../storage_capture.dart';
import 'storage_value_type.dart';

/// One storage key row in the browser. Flutter's default backend is
/// shared_preferences (all keys `optional_present`, `async`); the status/
/// category fields keep RN parity for a future required-key config.
class StorageKeyInfo {
  StorageKeyInfo({
    required this.key,
    required this.value,
    this.storageType = 'async',
    this.status = 'optional_present',
    this.category = 'optional',
    this.instanceId,
  });

  final String key;
  final Object? value;
  final String storageType;

  /// required_present | required_missing | required_wrong_value |
  /// required_wrong_type | optional_present.
  final String status;

  /// required | optional.
  final String category;
  final String? instanceId;
}

/// One key's event history (RN `StorageKeyConversation`).
class StorageConversation {
  StorageConversation({
    required this.key,
    required this.events,
    required this.lastEvent,
    required this.totalOperations,
    required this.currentValue,
    required this.valueType,
    required this.storageTypes,
  });

  final String key;

  /// Newest-first (as the store holds them).
  final List<StorageEvent> events;
  final StorageEvent lastEvent;
  final int totalOperations;
  final Object? currentValue;
  final String valueType;
  final Set<String> storageTypes;
}

/// Group events by key into conversations, honoring enabled storage types and
/// ignored key patterns (RN `conversations` memo in StorageModalWithTabs).
/// Returns newest-first by last event timestamp.
List<StorageConversation> buildConversations(
  List<StorageEvent> events, {
  required Set<String> ignoredPatterns,
  required Set<String> enabledStorageTypes,
}) {
  final map = <String, _MutableConversation>{};
  for (final event in events) {
    final key = event.key;
    if (key.isEmpty) continue;
    if (!enabledStorageTypes.contains(event.storageType)) continue;
    if (ignoredPatterns.any(key.contains)) continue;

    final existing = map[key];
    if (existing == null) {
      map[key] = _MutableConversation(
        key: key,
        lastEvent: event,
        events: [event],
        currentValue: event.value,
        storageTypes: {event.storageType},
      );
    } else {
      existing.events.add(event);
      existing.storageTypes.add(event.storageType);
      if (event.timestamp.isAfter(existing.lastEvent.timestamp)) {
        existing.lastEvent = event;
        existing.currentValue = event.value;
      }
    }
  }

  final result = map.values
      .map((c) => StorageConversation(
            key: c.key,
            events: c.events,
            lastEvent: c.lastEvent,
            totalOperations: c.events.length,
            currentValue: c.currentValue,
            valueType: getValueType(c.currentValue),
            storageTypes: c.storageTypes,
          ))
      .toList()
    ..sort(
      (a, b) => b.lastEvent.timestamp.compareTo(a.lastEvent.timestamp),
    );
  return result;
}

/// Filter events for the Events tab stream (RN `filteredEvents` memo).
List<StorageEvent> filterStorageEvents(
  List<StorageEvent> events, {
  required Set<String> ignoredPatterns,
  required Set<String> enabledStorageTypes,
}) {
  return [
    for (final e in events)
      if (e.key.isNotEmpty &&
          enabledStorageTypes.contains(e.storageType) &&
          !ignoredPatterns.any(e.key.contains))
        e,
  ];
}

class _MutableConversation {
  _MutableConversation({
    required this.key,
    required this.lastEvent,
    required this.events,
    required this.currentValue,
    required this.storageTypes,
  });

  final String key;
  StorageEvent lastEvent;
  final List<StorageEvent> events;
  Object? currentValue;
  final Set<String> storageTypes;
}
