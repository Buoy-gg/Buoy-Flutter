// Pins the RN timeline rule: the Events tool's network source must not hand
// a new subscriber traffic from before it existed (the boot buffer flushes
// INSIDE store.subscribe, after the source seeded its dedupe map), while an
// update to a row already emitted still flows.
import 'package:buoy_network/buoy_network.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

NetworkCaptureEvent _event(String id, int ts) => NetworkCaptureEvent(
  id: id,
  method: 'GET',
  url: 'https://api.example.com/$id',
  timestamp: ts,
  requestClient: 'http',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetworkEventStore.instance.capturing = false;
    NetworkEventStore.instance.clear();
    registerBuoyNetwork(installHttpOverrides: false);
  });

  tearDown(() => NetworkEventStore.instance.capturing = false);

  test('boot-buffered requests do not land as live timeline rows', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Fired before anyone subscribed → parked in the boot buffer.
    NetworkEventStore.instance.add(_event('boot-1', now - 5000));
    NetworkEventStore.instance.add(_event('boot-2', now - 4000));

    final source = eventSourceRegistry.byId('network')!;
    final seen = <String>[];
    final unsub = source.subscribe((e) => seen.add(e.data['id'] as String));
    expect(seen, isEmpty, reason: 'history is the Network tool\'s, not the timeline\'s');

    // A request after subscribing is live.
    NetworkEventStore.instance.add(_event('live-1', now + 1000));
    expect(seen, ['live-1']);

    // Its response updates the same row — still flows (not "new").
    final live = NetworkEventStore.instance.events.firstWhere((e) => e.id == 'live-1');
    live.status = 200;
    NetworkEventStore.instance.update(live);
    expect(seen, ['live-1', 'live-1']);
    unsub();
  });
}
