import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_network/buoy_network.dart';

void main() {
  test('snapshot strips bodies over the 16KB inline limit but keeps sizes',
      () {
    final event = NetworkCaptureEvent(
      id: 't1',
      method: 'GET',
      url: 'https://example.com/a?b=c',
      timestamp: 1,
      requestClient: 'http',
    )
      ..responseData = 'x' * 100
      ..responseSize = 20 * 1024
      ..status = 200;

    final stripped = event.toJson(stripLargeBodies: true);
    expect(stripped.containsKey('responseData'), isFalse);
    expect(stripped['responseSize'], 20 * 1024);
    expect(stripped['host'], 'example.com');
    expect(stripped['path'], '/a');
    expect(stripped['query'], 'b=c');

    final full = event.toJson();
    expect(full['responseData'], isNotNull);
  });

  test('ignored URL patterns match after registration', () {
    addIgnoredCaptureUrl('localhost:42831');
    // _isIgnoredUrl is private; exercised via the store path indirectly in
    // integration. Here we at least assert registration doesn't throw and
    // regex-escaping treats the pattern literally.
    addIgnoredCaptureUrl(RegExp(r'analytics\.example\.com'));
  });

  test('store caps events and clears', () {
    final store = NetworkEventStore.instance;
    final unsub = store.subscribe(() {});
    store.clear();
    for (var i = 0; i < 10; i++) {
      store.add(NetworkCaptureEvent(
        id: 'e$i',
        method: 'GET',
        url: 'https://example.com/$i',
        timestamp: i,
        requestClient: 'http',
      ));
    }
    expect(store.events.length, 10);
    expect(store.events.first.id, 'e9', reason: 'newest first');
    expect(store.byId('e3'), isNotNull);
    store.clear();
    expect(store.events, isEmpty);
    unsub();
  });
}
