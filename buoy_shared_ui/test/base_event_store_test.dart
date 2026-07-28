import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

/// A minimal concrete store for exercising BaseEventStore. `startCapturing` /
/// `stopCapturing` just flip a flag so lifecycle transitions are observable.
class _TestStore extends BaseEventStore<Map<String, Object?>> {
  _TestStore({super.maxEvents, super.storeName = 'test'});

  bool capturing = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  void startCapturing() {
    capturing = true;
    startCount++;
  }

  @override
  void stopCapturing() {
    capturing = false;
    stopCount++;
  }

  @override
  bool isCapturing() => capturing;
}

void main() {
  group('BaseEventStore', () {
    test('addEvent stores newest-first', () {
      final store = _TestStore();
      store.addEvent({'id': 1});
      store.addEvent({'id': 2});
      store.addEvent({'id': 3});
      expect(store.getEvents().map((e) => e['id']).toList(), [3, 2, 1]);
      expect(store.getEventCount(), 3);
    });

    test('caps at maxEvents, dropping the oldest', () {
      final store = _TestStore(maxEvents: 3);
      for (var i = 1; i <= 5; i++) {
        store.addEvent({'id': i});
      }
      // Newest-first, only the last 3 ids retained.
      expect(store.getEvents().map((e) => e['id']).toList(), [5, 4, 3]);
      expect(store.getEventCount(), 3);
    });

    test('first onEvent subscriber starts capture, last unsubscribe stops it',
        () {
      final store = _TestStore();
      expect(store.isCapturing(), isFalse);
      final off1 = store.onEvent((_) {});
      expect(store.isCapturing(), isTrue);
      expect(store.startCount, 1);
      final off2 = store.onEvent((_) {});
      // Still one start (already capturing).
      expect(store.startCount, 1);
      off1();
      expect(store.isCapturing(), isTrue); // one subscriber remains
      off2();
      expect(store.isCapturing(), isFalse);
      expect(store.stopCount, 1);
    });

    test('subscribeToEvents fires immediately and on each change', () {
      final store = _TestStore();
      final seen = <int>[];
      final off = store.subscribeToEvents((events) => seen.add(events.length));
      expect(seen, [0]); // immediate call with current (empty) list
      store.addEvent({'id': 1});
      store.addEvent({'id': 2});
      expect(seen, [0, 1, 2]);
      off();
    });

    test('subscriber-count notifier fires on subscribe and unsubscribe', () {
      final store = _TestStore(storeName: 'notif');
      final hits = <String>[];
      final offNotify =
          subscribeToSubscriberCountChanges((name) => hits.add(name));
      final off = store.onEvent((_) {});
      expect(hits, ['notif']); // subscribe
      off();
      expect(hits, ['notif', 'notif']); // unsubscribe
      offNotify();
    });

    test('getSubscriberCounts tracks both listener kinds', () {
      final store = _TestStore();
      final a = store.onEvent((_) {});
      final b = store.subscribeToEvents((_) {});
      final counts = store.getSubscriberCounts();
      expect(counts.eventCallbacks, 1);
      expect(counts.arrayListeners, 1);
      expect(counts.total, 2);
      a();
      b();
    });

    test('clearEvents empties the buffer and fires clear listeners', () {
      final store = _TestStore();
      store.addEvent({'id': 1});
      var cleared = false;
      final off = store.onClear(() => cleared = true);
      store.clearEvents();
      expect(store.getEventCount(), 0);
      expect(cleared, isTrue);
      off();
    });

    test('disableCapture suppresses auto-start; replaceEvents dedupes by id',
        () {
      final store = _TestStore();
      store.disableCapture();
      final off = store.onEvent((_) {});
      // Capture must NOT start in mirror mode.
      expect(store.isCapturing(), isFalse);
      expect(store.startCount, 0);
      store.replaceEvents([
        {'id': 1},
        {'id': 2},
        {'id': 1}, // duplicate id dropped
        {'id': 3},
      ]);
      expect(store.getEvents().map((e) => e['id']).toList(), [1, 2, 3]);
      off();
    });

    test('setMaxEvents trims an over-long buffer', () {
      final store = _TestStore(maxEvents: 10);
      for (var i = 0; i < 8; i++) {
        store.addEvent({'id': i});
      }
      store.setMaxEvents(3);
      expect(store.getEventCount(), 3);
    });
  });
}
