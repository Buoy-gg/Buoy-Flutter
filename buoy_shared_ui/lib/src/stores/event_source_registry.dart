/// The Dart stand-in for `@buoy-gg/events`' `autoDiscoverEventSources.ts`.
///
/// RN discovers event sources at runtime with optional `require()` of each tool
/// package. Dart has no optional require, so instead each source tool registers
/// an [EventSourceAdapter] here at its own `registerBuoyX()` time (see
/// buoy_network/storage/routes `register.dart`). The events tool (buoy_events)
/// reads this registry and depends on nothing tool-specific — preserving RN's
/// "install a tool and it appears in the timeline" optional-source model.
///
/// The shared [UnifiedEvent] shape mirrors RN's `packages/events/src/types`.
library;

import 'package:flutter/widgets.dart';

/// Status for color-coding a timeline row (RN `EventStatus`).
enum EventStatus { success, error, pending, neutral }

/// The granular event-source identifiers (RN `EventSource`). All 11 RN values
/// are kept for MCP source-name parity and future tools even though only
/// `storage-async`/`storage-mmkv`, `network`, and `route` are wired on Flutter.
class EventSourceIds {
  static const storageAsync = 'storage-async';
  static const storageMmkv = 'storage-mmkv';
  static const redux = 'redux';
  static const network = 'network';
  static const reactQuery = 'react-query';
  static const reactQueryQuery = 'react-query-query';
  static const reactQueryMutation = 'react-query-mutation';
  static const route = 'route';
  static const render = 'render';
  static const zustand = 'zustand';
  static const jotai = 'jotai';

  /// Riverpod — a Flutter-only state source (no RN equivalent). NOT the
  /// reserved `jotai` id: `get_events` should honestly report `riverpod`, and
  /// the timeline is generic (rowBuilder/detailBuilder + data map), so a new id
  /// lights it up with zero desktop changes.
  static const riverpod = 'riverpod';
}

/// One row in the unified timeline (RN `UnifiedEvent`).
///
/// [originalEvent] is the tool's TYPED source object, fed to that tool's own
/// [EventSourceAdapter.rowBuilder]/[EventSourceAdapter.detailBuilder]. [data] is
/// the tool's serialized `toJson()` map — RN's `originalEvent` plain-object
/// shape — consumed by the exporter and MCP `get_events`. Keeping them separate
/// lets buoy_events stay free of every tool's widget/model types.
class UnifiedEvent {
  UnifiedEvent({
    required this.id,
    required this.source,
    required this.timestamp,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.originalEvent,
    required this.data,
    this.correlationId,
    this.sequenceInGroup,
  });

  /// Source-prefixed unique id. Mutable so the store can rewrite a network
  /// event's id to its earlier unified id on an in-place update (RN parity).
  String id;

  /// One of [EventSourceIds].
  final String source;

  /// Unix ms.
  final int timestamp;
  final String title;
  final String subtitle;
  final EventStatus status;

  /// Typed source object for display builders.
  final Object? originalEvent;

  /// Serialized (`toJson`) map for the exporter / MCP.
  final Map<String, Object?> data;

  final String? correlationId;
  final int? sequenceInGroup;
}

/// Emit callback an adapter's [EventSourceAdapter.subscribe] calls per event.
typedef UnifiedEventEmit = void Function(UnifiedEvent event);

/// Builds the compact list row for a source's event (RN's per-source
/// `NetworkEventItemCompact` / `StorageEventCard` / `RouteEventItemCompact`).
typedef EventRowBuilder = Widget Function(
  BuildContext context,
  UnifiedEvent event,
  VoidCallback onPress,
);

/// Builds the detail view for a source's event (RN's per-source
/// `NetworkEventDetailView` / `StorageEventDetailContent` / `RouteEventDetail`).
typedef EventDetailBuilder = Widget Function(
  BuildContext context,
  UnifiedEvent event,
  void Function(String pathname)? onNavigate,
);

/// A discovered event source (RN `DiscoveredEventSource`), contributed by a tool.
class EventSourceAdapter {
  const EventSourceAdapter({
    required this.id,
    required this.name,
    required this.eventSources,
    required this.subscribe,
    this.rowBuilder,
    this.detailBuilder,
    this.subscriberCount,
  });

  /// Discovery id (RN `DiscoveredEventSource.id`): `storage`, `network`,
  /// `route-events`.
  final String id;

  /// Display name.
  final String name;

  /// The [EventSourceIds] this source emits (one source can map to several,
  /// e.g. storage → async + mmkv).
  final List<String> eventSources;

  /// Subscribe to the tool's store; each raw event → [UnifiedEventEmit].
  /// Returns an unsubscribe function.
  final void Function() Function(UnifiedEventEmit emit) subscribe;

  /// Optional custom row / detail builders (fall back to CompactRow/DataViewer).
  final EventRowBuilder? rowBuilder;
  final EventDetailBuilder? detailBuilder;

  /// Optional subscriber-count getter for the filter badge (RN
  /// `getSubscriberCounts`). Null → the source has no tracking (no left count).
  final int? Function()? subscriberCount;
}

/// Registry every source tool populates; buoy_events consumes it. Singleton so
/// registration order (tool register → events read) is decoupled.
class EventSourceRegistry {
  EventSourceRegistry._();

  final Map<String, EventSourceAdapter> _adapters = {};
  final Set<void Function()> _listeners = {};

  /// Register a source. Idempotent by [EventSourceAdapter.id] (RN dedupe).
  void register(EventSourceAdapter adapter) {
    if (_adapters.containsKey(adapter.id)) return;
    _adapters[adapter.id] = adapter;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  List<EventSourceAdapter> get adapters => _adapters.values.toList();

  EventSourceAdapter? byId(String id) => _adapters[id];

  /// All [EventSourceIds] currently available (union across adapters).
  Set<String> get availableEventSources => {
        for (final a in _adapters.values) ...a.eventSources,
      };

  /// Notified when an adapter registers (the events modal refreshes its
  /// discovered-source list). Returns an unsubscribe.
  void Function() onChange(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// The singleton (RN `getCachedDiscovery` cache).
final eventSourceRegistry = EventSourceRegistry._();
