/// Ports packages/shared/src/stores/BaseEventStore.ts (+ utils/subscribable.ts
/// and utils/subscriberCountNotifier.ts).
///
/// Ring-buffer event store base with TanStack-Query-style self-managing
/// lifecycle: capture auto-starts when the first subscriber joins and auto-stops
/// when the last leaves. Two subscription shapes — array listeners (full list on
/// each change) and per-event callbacks — plus a global subscriber-count signal
/// the debugging UI (events tool) listens to. Subclasses implement
/// [startCapturing]/[stopCapturing]/[isCapturing].
library;

/// Global notifier for subscriber-count changes across all event stores. Ports
/// subscriberCountNotifier.ts — the UI subscribes once and refreshes counts
/// instantly instead of polling. Lives here (not in a tool) to avoid cycles.
class SubscriberCountNotifier {
  final Set<void Function(String storeName)> _listeners = {};

  /// Subscribe to subscriber-count changes; returns an unsubscribe function.
  void Function() subscribe(void Function(String storeName) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Notify all listeners that [storeName]'s subscriber count changed.
  void notify(String storeName) {
    for (final listener in List.of(_listeners)) {
      try {
        listener(storeName);
      } catch (_) {
        // Ignore listener errors (RN parity).
      }
    }
  }
}

/// Singleton instance (RN `subscriberCountNotifier`).
final subscriberCountNotifier = SubscriberCountNotifier();

/// Convenience wrapper (RN `subscribeToSubscriberCountChanges`).
void Function() subscribeToSubscriberCountChanges(
  void Function(String storeName) listener,
) =>
    subscriberCountNotifier.subscribe(listener);

/// Convenience wrapper (RN `notifySubscriberCountChange`).
void notifySubscriberCountChange(String storeName) =>
    subscriberCountNotifier.notify(storeName);

/// Callback receiving the full events array (RN `ArrayListener`).
typedef ArrayListener<TEvent> = void Function(List<TEvent> events);

/// Callback receiving a single event as it occurs (RN `EventCallback`).
typedef EventCallback<TEvent> = void Function(TEvent event);

/// Abstract base for event stores. Subclasses implement [startCapturing],
/// [stopCapturing], and [isCapturing]; the base wires the subscription
/// lifecycle, the ring buffer, and the subscriber-count signal.
abstract class BaseEventStore<TEvent> {
  BaseEventStore({int maxEvents = 500, required this.storeName})
      : _maxEvents = maxEvents;

  List<TEvent> _events = <TEvent>[];
  final Set<EventCallback<TEvent>> _listeners = {};
  final Set<ArrayListener<TEvent>> _arrayListeners = {};
  final Set<void Function()> _clearListeners = {};
  int _maxEvents;

  /// Store name used for subscriber-count notifications (RN `storeName`).
  final String storeName;
  bool _captureSuppressed = false;

  // ── Abstract ──────────────────────────────────────────────────────────

  /// Begin listening to the underlying source. Auto-called on first subscriber.
  void startCapturing();

  /// Stop listening to the underlying source. Auto-called on last unsubscribe.
  void stopCapturing();

  /// Whether the store is actively capturing.
  bool isCapturing();

  // ── Subscription ──────────────────────────────────────────────────────

  int _getTotalSubscriberCount() => _listeners.length + _arrayListeners.length;

  /// Subscribe to the full events array; fires immediately with the current
  /// list and on every change. Starts capture on the first subscriber. Returns
  /// an unsubscribe function.
  void Function() subscribeToEvents(ArrayListener<TEvent> listener) {
    final wasEmpty = _getTotalSubscriberCount() == 0;
    _arrayListeners.add(listener);
    if (wasEmpty && !_captureSuppressed) startCapturing();
    notifySubscriberCountChange(storeName);
    listener(getEvents());
    return () {
      _arrayListeners.remove(listener);
      if (_getTotalSubscriberCount() == 0) stopCapturing();
      notifySubscriberCountChange(storeName);
    };
  }

  /// Subscribe to individual events as they occur. Starts capture on the first
  /// subscriber. Returns an unsubscribe function.
  void Function() onEvent(EventCallback<TEvent> callback) {
    _listeners.add(callback);
    if (_getTotalSubscriberCount() == 1 && !_captureSuppressed) {
      startCapturing();
    }
    notifySubscriberCountChange(storeName);
    return () {
      _listeners.remove(callback);
      if (_getTotalSubscriberCount() == 0) stopCapturing();
      notifySubscriberCountChange(storeName);
    };
  }

  // ── Event management ──────────────────────────────────────────────────

  /// Add an event (newest first), capped at `maxEvents`. Call from subclasses.
  void addEvent(TEvent event) {
    _events = [event, ..._events];
    if (_events.length > _maxEvents) {
      _events = _events.sublist(0, _maxEvents);
    }
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
    _notifyArrayListeners();
  }

  void _notifyArrayListeners() {
    final events = getEvents();
    for (final listener in List.of(_arrayListeners)) {
      try {
        listener(events);
      } catch (_) {
        // Ignore listener errors (RN parity).
      }
    }
  }

  /// All events, newest first.
  List<TEvent> getEvents() => _events;

  int getEventCount() => _events.length;

  /// Clear all events and fire clear listeners.
  void clearEvents() {
    _events = <TEvent>[];
    _notifyArrayListeners();
    for (final listener in List.of(_clearListeners)) {
      try {
        listener();
      } catch (_) {
        // Ignore listener errors (RN parity).
      }
    }
  }

  /// Listen for [clearEvents] calls (remote mirror mode forwards a dashboard
  /// clear to the synced device). Returns an unsubscribe function.
  void Function() onClear(void Function() listener) {
    _clearListeners.add(listener);
    return () => _clearListeners.remove(listener);
  }

  // ── Remote mirror mode ────────────────────────────────────────────────

  /// Suppress the auto start/stop lifecycle (dashboard mirror: events arrive via
  /// [replaceEvents], local interceptors must never start).
  void disableCapture() {
    _captureSuppressed = true;
    if (isCapturing()) stopCapturing();
  }

  /// Replace the whole event list (deduped by id) and notify array listeners.
  void replaceEvents(List<TEvent> events) {
    final deduped = _dedupeById(events);
    _events = deduped.length > _maxEvents
        ? deduped.sublist(0, _maxEvents)
        : deduped;
    _notifyArrayListeners();
  }

  /// Drop events sharing an `id` with an earlier (newer) event; events without
  /// an `id` pass through. Reads `.id` dynamically for RN parity (works for Map
  /// events or typed events exposing an `id` getter).
  List<TEvent> _dedupeById(List<TEvent> events) {
    final seen = <Object?>{};
    final result = <TEvent>[];
    for (final event in events) {
      Object? id;
      try {
        if (event is Map) {
          id = event['id'];
        } else {
          id = (event as dynamic).id;
        }
      } catch (_) {
        id = null;
      }
      if (id == null) {
        result.add(event);
        continue;
      }
      if (seen.contains(id)) continue;
      seen.add(id);
      result.add(event);
    }
    return result;
  }

  /// Set the max number of retained events, trimming if needed.
  void setMaxEvents(int max) {
    _maxEvents = max;
    if (_events.length > max) {
      _events = _events.sublist(0, max);
      _notifyArrayListeners();
    }
  }

  // ── Debugging ─────────────────────────────────────────────────────────

  /// Current subscriber counts (RN `getSubscriberCounts`).
  ({int eventCallbacks, int arrayListeners, int total}) getSubscriberCounts() =>
      (
        eventCallbacks: _listeners.length,
        arrayListeners: _arrayListeners.length,
        total: _getTotalSubscriberCount(),
      );
}
