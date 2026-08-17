/// Ports packages/network `6c95492` — boot-time request capture.
///
/// The bug: capture starts with the first subscriber (modal open, dashboard
/// watch, MCP watch), which is long after startup requests have fired. Those
/// were dropped outright, so `get_network_requests` answered "No requests
/// captured" for a screen that had visibly loaded its data.
library;

import 'package:buoy_network/buoy_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

NetworkCaptureEvent _event(String id) => NetworkCaptureEvent(
  id: id,
  method: 'GET',
  url: 'https://api.example.com/$id',
  timestamp: 1755000000000,
  requestClient: 'http',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetworkEventStore.instance.capturing = false;
    NetworkEventStore.instance.clear();
  });

  tearDown(() => NetworkEventStore.instance.capturing = false);

  test('requests fired before anyone subscribes survive to the first read', () {
    NetworkEventStore.instance.add(_event('boot-1'));
    NetworkEventStore.instance.add(_event('boot-2'));
    // Nothing is visible yet — capture has not started.
    expect(NetworkEventStore.instance.events, isEmpty);

    final unsub = NetworkEventStore.instance.subscribe(() {});
    addTearDown(unsub);

    final ids = NetworkEventStore.instance.events.map((e) => e.id).toList();
    expect(ids, containsAll(<String>['boot-1', 'boot-2']));
  });

  test('flushed boot requests keep newest-first order', () {
    NetworkEventStore.instance.add(_event('oldest'));
    NetworkEventStore.instance.add(_event('newest'));
    final unsub = NetworkEventStore.instance.subscribe(() {});
    addTearDown(unsub);

    expect(NetworkEventStore.instance.events.first.id, 'newest');
    expect(NetworkEventStore.instance.events.last.id, 'oldest');
  });

  test('a response that lands while buffered is already filled in', () {
    // The buffer holds the SAME instance the interceptor mutates, so a request
    // that completed before anyone subscribed arrives complete.
    final event = _event('completed-while-buffered');
    NetworkEventStore.instance.add(event);
    event.status = 200;
    event.responseData = '{"ok":true}';

    final unsub = NetworkEventStore.instance.subscribe(() {});
    addTearDown(unsub);

    final flushed = NetworkEventStore.instance.events.single;
    expect(flushed.status, 200);
    expect(flushed.responseData, '{"ok":true}');
  });

  test('the buffer is bounded — a busy boot cannot grow without limit', () {
    for (var i = 0; i < 500; i++) {
      NetworkEventStore.instance.add(_event('e$i'));
    }
    final unsub = NetworkEventStore.instance.subscribe(() {});
    addTearDown(unsub);

    final events = NetworkEventStore.instance.events;
    expect(events.length, lessThanOrEqualTo(100));
    // Oldest dropped first, so the most recent boot traffic is what survives.
    expect(events.first.id, 'e499');
  });

  test('nothing is flushed if nothing ever subscribes', () {
    NetworkEventStore.instance.add(_event('never-seen'));
    expect(NetworkEventStore.instance.events, isEmpty);
    // An explicit capture-off state must never gain events it didn't ask for.
    final snapshot = networkSyncAdapter.getSnapshot()! as Map;
    expect(snapshot['events'], isEmpty);
  });

  test('clear drops the boot buffer too', () {
    NetworkEventStore.instance.add(_event('pre-clear'));
    NetworkEventStore.instance.clear();

    final unsub = NetworkEventStore.instance.subscribe(() {});
    addTearDown(unsub);
    // "Clear" has to mean the list stays empty, not that a later subscribe
    // resurrects pre-clear traffic.
    expect(NetworkEventStore.instance.events, isEmpty);
  });

  test('unsubscribing and resubscribing does not replay the live list', () {
    final unsub = NetworkEventStore.instance.subscribe(() {});
    NetworkEventStore.instance.add(_event('live'));
    unsub();

    final again = NetworkEventStore.instance.subscribe(() {});
    addTearDown(again);
    expect(NetworkEventStore.instance.events.map((e) => e.id), ['live']);
  });
}
