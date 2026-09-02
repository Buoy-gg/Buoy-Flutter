// Pins the RN "Events Power Toggle Fix": the on-device consumer's source refs
// go through ONE ledger, so re-declaring never stacks refs the power toggle
// can't release, and turning capture off releases exactly what is held.
import 'package:buoy_events/buoy_events.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var subscribes = 0;
  var unsubscribes = 0;

  setUp(() {
    subscribes = 0;
    unsubscribes = 0;
    unifiedEventStore.clearEvents();
    eventSourceRegistry.register(EventSourceAdapter(
      id: 'network',
      name: 'FakeNet',
      eventSources: const [EventSourceIds.network],
      subscribe: (_) {
        subscribes++;
        return () => unsubscribes++;
      },
    ));
  });

  tearDown(() => unifiedEventStore.setLocalEnabledSources(const []));

  test('re-declaring the same sources is idempotent (no ref ratchet)', () {
    unifiedEventStore.setLocalEnabledSources(const [EventSourceIds.network]);
    unifiedEventStore.setLocalEnabledSources(const [EventSourceIds.network]);
    unifiedEventStore.setLocalEnabledSources(const [EventSourceIds.network]);
    expect(subscribes, 1);
    expect(unifiedEventStore.isDiscoverySubscribed('network'), isTrue);

    // Power OFF: declares nothing → the single ref is released and the source
    // is torn down. (The old per-call-site pairs left extra refs behind here.)
    unifiedEventStore.setLocalEnabledSources(const []);
    expect(unsubscribes, 1);
    expect(unifiedEventStore.isDiscoverySubscribed('network'), isFalse);
  });

  test('a watching dashboard keeps its own ref through the local toggle', () {
    unifiedEventStore.setRemoteEnabledSources(const [EventSourceIds.network]);
    unifiedEventStore.setLocalEnabledSources(const [EventSourceIds.network]);
    expect(subscribes, 1, reason: 'one real subscription, two refs');

    unifiedEventStore.setLocalEnabledSources(const []);
    expect(unsubscribes, 0, reason: 'the remote ref keeps the source alive');
    expect(unifiedEventStore.isDiscoverySubscribed('network'), isTrue);

    unifiedEventStore.clearRemoteSources();
    expect(unsubscribes, 1);
  });
}
