// Ports RN's `interceptorLive` recipe (networkListener.startListening): a
// runtime that re-assigns the global hook over Buoy's must not leave capture
// dead for the session. Here the hook is `HttpOverrides.global`.
import 'dart:io';

import 'package:buoy_network/buoy_network.dart';
import 'package:buoy_network/src/network_capture.dart';
import 'package:flutter_test/flutter_test.dart';

class _SomeoneElsesOverrides extends HttpOverrides {}

void main() {
  tearDown(() => HttpOverrides.global = null);

  test('a later HttpOverrides.global assignment is repaired on subscribe', () {
    BuoyHttpOverrides.install();
    expect(NetworkEventStore.interceptionLive, isTrue);

    // The clobber: app code installs its own overrides AFTER Buoy.
    HttpOverrides.global = _SomeoneElsesOverrides();
    expect(NetworkEventStore.interceptionLive, isFalse);

    // Not capturing → must NOT install anything (mirror-mode rule).
    NetworkEventStore.instance.ensureInterception();
    expect(NetworkEventStore.interceptionLive, isFalse);

    // A consumer subscribes → repaired, and the clobberer is chained under us.
    final unsub = NetworkEventStore.instance.subscribe(() {});
    expect(NetworkEventStore.interceptionLive, isTrue);
    expect(
      (HttpOverrides.current as BuoyHttpOverrides).previous,
      isA<_SomeoneElsesOverrides>(),
    );
    unsub();
  });

  test('getSnapshot piggybacks the health check while a watch is open', () {
    BuoyHttpOverrides.install();
    final unsub = networkSyncAdapter.subscribe(() {});
    HttpOverrides.global = _SomeoneElsesOverrides();
    expect(NetworkEventStore.interceptionLive, isFalse);
    networkSyncAdapter.getSnapshot();
    expect(NetworkEventStore.interceptionLive, isTrue);
    final status =
        networkSyncAdapter.actions['getCaptureStatus']!(null) as Map<String, Object?>;
    expect(status['interceptorLive'], isTrue);
    unsub();
  });
}
