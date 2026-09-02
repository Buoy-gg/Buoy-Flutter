/// Ports packages/events/src/stores/unifiedEventStore.ts (the on-device subset).
///
/// The singleton aggregator. It captures nothing itself — it subscribes to the
/// [EventSourceAdapter]s in buoy_shared_ui's [eventSourceRegistry] and merges
/// their [UnifiedEvent]s into one chronological (newest-first) list. Source
/// subscriptions are ref-counted so the on-device modal and a watching desktop
/// dashboard each request sources independently and capture stops only when the
/// last consumer drops a source.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

/// RN `MAX_EVENTS`.
const int _maxEvents = 200;

/// High-frequency sources `subscribeToAll` must skip (RN
/// `SUBSCRIBE_ALL_EXCLUDED_SOURCE_IDS`). "render" isn't a Flutter source yet,
/// but the guard is kept for parity.
const Set<String> _subscribeAllExcluded = {'render'};

/// Maps a granular [EventSourceIds] to its parent discovery id (RN
/// `EVENT_SOURCE_TO_DISCOVERY_ID`).
const Map<String, String> eventSourceToDiscoveryId = {
  EventSourceIds.storageAsync: 'storage',
  EventSourceIds.storageMmkv: 'storage',
  EventSourceIds.redux: 'redux',
  EventSourceIds.network: 'network',
  EventSourceIds.reactQuery: 'react-query',
  EventSourceIds.reactQueryQuery: 'react-query',
  EventSourceIds.reactQueryMutation: 'react-query',
  EventSourceIds.route: 'route-events',
  EventSourceIds.zustand: 'zustand',
  EventSourceIds.jotai: 'jotai',
  EventSourceIds.render: 'render',
};

class _SourceSub {
  _SourceSub(this.unsubscribe);
  void Function() unsubscribe;
  int refCount = 1;
}

/// Ports `UnifiedEventStore`.
class UnifiedEventStore {
  UnifiedEventStore._();
  static final UnifiedEventStore instance = UnifiedEventStore._();

  List<UnifiedEvent> _events = [];
  final Set<void Function(List<UnifiedEvent>)> _listeners = {};
  final Set<String> _activeSources = {};

  /// Ref-counted subscriptions keyed by discovery id.
  final Map<String, _SourceSub> _sourceSubs = {};

  /// Discovery ids the remote (dashboard) consumer currently wants.
  final Set<String> _remoteDiscoveryIds = {};

  /// Network event id → unified event id, for in-place response updates.
  final Map<String, String> _networkIdMap = {};

  // ── Availability ──────────────────────────────────────────────────────────

  /// RN `getAvailableEventSources` — union of registered adapters' sources.
  Set<String> getAvailableEventSources() =>
      eventSourceRegistry.availableEventSources;

  // ── Source subscriptions (ref-counted) ────────────────────────────────────

  /// Subscribe to a discovery id via its registered adapter. Ref-counts.
  void subscribeToSource(String discoveryId) {
    final existing = _sourceSubs[discoveryId];
    if (existing != null) {
      existing.refCount++;
      return;
    }
    final adapter = eventSourceRegistry.byId(discoveryId);
    if (adapter == null) return;
    final sub = _SourceSub(() {});
    _sourceSubs[discoveryId] = sub;
    sub.unsubscribe = adapter.subscribe(_addEvent);
  }

  /// Drop one ref; real teardown on the last.
  void unsubscribeFromSource(String discoveryId) {
    final sub = _sourceSubs[discoveryId];
    if (sub == null) return;
    sub.refCount--;
    if (sub.refCount <= 0) {
      sub.unsubscribe();
      _sourceSubs.remove(discoveryId);
    }
  }

  bool isDiscoverySubscribed(String discoveryId) =>
      _sourceSubs.containsKey(discoveryId);

  /// RN `subscribeToAll` — every discovered source except the excluded ones.
  void subscribeToAll() {
    for (final adapter in eventSourceRegistry.adapters) {
      if (_subscribeAllExcluded.contains(adapter.id)) continue;
      subscribeToSource(adapter.id);
    }
  }

  // ── Event management ──────────────────────────────────────────────────────

  void _addEvent(UnifiedEvent event) {
    // Network update-in-place: a response/error mutates the same request row.
    if (event.source == EventSourceIds.network) {
      final netId = event.data['id'];
      if (netId is String) {
        final existingUnifiedId = _networkIdMap[netId];
        if (existingUnifiedId != null) {
          final index = _events.indexWhere((e) => e.id == existingUnifiedId);
          if (index >= 0) {
            event.id = existingUnifiedId; // keep same unified id
            _events = [
              ..._events.sublist(0, index),
              event,
              ..._events.sublist(index + 1),
            ];
            _notify();
            return;
          }
        }
        _networkIdMap[netId] = event.id;
      }
    }

    _events = [event, ..._events];
    if (_events.length > _maxEvents) {
      _events = _events.sublist(0, _maxEvents);
    }
    _activeSources.add(event.source);
    _notify();
  }

  /// All events, newest-first (optionally filtered by enabled sources).
  List<UnifiedEvent> getEvents([Set<String>? enabledSources]) {
    if (enabledSources == null || enabledSources.isEmpty) return _events;
    return _events.where((e) => enabledSources.contains(e.source)).toList();
  }

  int getEventCount() => _events.length;

  /// Count of events per granular source (RN `getSourceCounts`).
  Map<String, int> getSourceCounts() {
    final counts = <String, int>{
      EventSourceIds.storageAsync: 0,
      EventSourceIds.storageMmkv: 0,
      EventSourceIds.redux: 0,
      EventSourceIds.network: 0,
      EventSourceIds.reactQuery: 0,
      EventSourceIds.reactQueryQuery: 0,
      EventSourceIds.reactQueryMutation: 0,
      EventSourceIds.route: 0,
      EventSourceIds.zustand: 0,
      EventSourceIds.jotai: 0,
      EventSourceIds.render: 0,
    };
    for (final e in _events) {
      counts[e.source] = (counts[e.source] ?? 0) + 1;
    }
    return counts;
  }

  void clearEvents() {
    _events = [];
    _activeSources.clear();
    _networkIdMap.clear();
    _notify();
  }

  /// Subscribe to store changes; fires immediately with the current events.
  void Function() subscribe(void Function(List<UnifiedEvent>) listener) {
    _listeners.add(listener);
    listener(_events);
    return () => _listeners.remove(listener);
  }

  void _notify() {
    final events = _events;
    for (final listener in List.of(_listeners)) {
      listener(events);
    }
  }

  // ── Remote (dashboard) consumer channel ───────────────────────────────────

  /// RN `setRemoteEnabledSources` — narrow which sources the device captures for
  /// the dashboard. Diffed against the previous remote set; ref-counting keeps
  /// the on-device modal's own subscriptions intact.
  void setRemoteEnabledSources(List<String> sources) {
    final nextIds = <String>{};
    for (final src in sources) {
      final id = eventSourceToDiscoveryId[src];
      if (id != null) nextIds.add(id);
    }
    final prevIds = Set<String>.from(_remoteDiscoveryIds);
    _remoteDiscoveryIds
      ..clear()
      ..addAll(nextIds);

    for (final id in nextIds) {
      if (!prevIds.contains(id)) subscribeToSource(id);
    }
    for (final id in prevIds) {
      if (!nextIds.contains(id)) unsubscribeFromSource(id);
    }
  }

  /// RN `setLocalEnabledSources` — the ON-DEVICE consumer (the Events modal)
  /// declares which sources it wants captured: its enabled sources while
  /// capture is on, `[]` while it is off. Diffed against a ledger so repeated
  /// declarations are idempotent — remounting the tool, restoring state
  /// twice, or enabling two display sources that share a discovery source
  /// never stacks refs the power toggle can't release. (The old imperative
  /// subscribe/unsubscribe pairs acquired a fresh ref per call site; a
  /// closed-and-reopened tool could keep capturing with capture "off".)
  /// Ref-counting still keeps a watching dashboard's subscriptions alive
  /// independently.
  void setLocalEnabledSources(Iterable<String> sources) {
    final nextIds = <String>{};
    for (final src in sources) {
      final id = eventSourceToDiscoveryId[src];
      if (id != null) nextIds.add(id);
    }
    final prevIds = Set<String>.from(_localDiscoveryIds);
    _localDiscoveryIds
      ..clear()
      ..addAll(nextIds);
    for (final id in nextIds) {
      if (!prevIds.contains(id)) subscribeToSource(id);
    }
    for (final id in prevIds) {
      if (!nextIds.contains(id)) unsubscribeFromSource(id);
    }
  }

  final Set<String> _localDiscoveryIds = {};

  /// RN `ensureRemoteSourcesDefault` — default to all sources when a dashboard
  /// starts watching, unless it already declared a selection.
  void ensureRemoteSourcesDefault() {
    if (_remoteDiscoveryIds.isEmpty) {
      for (final adapter in eventSourceRegistry.adapters) {
        if (_subscribeAllExcluded.contains(adapter.id)) continue;
        _remoteDiscoveryIds.add(adapter.id);
        subscribeToSource(adapter.id);
      }
    }
  }

  /// RN `clearRemoteSources` — release the remote consumer's source refs.
  void clearRemoteSources() {
    for (final id in _remoteDiscoveryIds) {
      unsubscribeFromSource(id);
    }
    _remoteDiscoveryIds.clear();
  }
}

/// Singleton (RN `unifiedEventStore`).
final unifiedEventStore = UnifiedEventStore.instance;
