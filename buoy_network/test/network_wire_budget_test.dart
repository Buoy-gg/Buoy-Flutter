/// Ports the v5 half of
/// packages/network/src/network/sync/__tests__/networkSyncAdapter.test.ts.
///
/// v4 stripped bodies using ONLY the cached `requestSize`/`responseSize`
/// proxy, and signalled a withheld body by leaving the field absent — which
/// the dashboard cannot tell from "there was no body". v5 fixes both, and adds
/// a total snapshot budget so a burst of individually-legal bodies degrades
/// the tail instead of the emit layer dropping the whole panel.
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_network/buoy_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

NetworkCaptureEvent _event(
  String id, {
  Object? responseData,
  int? responseSize,
  Object? requestData,
  int? requestSize,
  Map<String, String> responseHeaders = const {},
}) {
  final event = NetworkCaptureEvent(
    id: id,
    method: 'GET',
    url: 'https://api.example.com/$id',
    timestamp: 1755000000000,
    requestClient: 'http',
  );
  event.status = 200;
  event.responseData = responseData;
  event.responseSize = responseSize;
  event.requestData = requestData;
  event.requestSize = requestSize;
  event.responseHeaders = responseHeaders;
  return event;
}

List<Map<String, Object?>> _events() {
  final snapshot = networkSyncAdapter.getSnapshot()! as Map;
  return (snapshot['events']! as List).cast<Map<String, Object?>>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetworkEventStore.instance.capturing = true;
    NetworkEventStore.instance.clear();
  });

  test('a small body stays inline and is not flagged', () {
    NetworkEventStore.instance.add(
      _event('a', responseData: '{"ok":true}', responseSize: 11),
    );
    final wire = _events().single;
    expect(wire['responseData'], '{"ok":true}');
    expect(wire.containsKey('responseBodyOmitted'), isFalse);
  });

  test('an oversized body is withheld AND flagged', () {
    final big = 'x' * (snapshotBodyInlineLimit + 1);
    NetworkEventStore.instance.add(
      _event('big', responseData: big, responseSize: big.length),
    );
    final wire = _events().single;
    expect(wire.containsKey('responseData'), isFalse);
    // The flag is the point: without it a withheld body is indistinguishable
    // from a request that simply had none, so the dashboard never fetches.
    expect(wire['responseBodyOmitted'], isTrue);
    // ...and the size stays HONEST rather than being doctored down.
    expect(wire['responseSize'], big.length);
  });

  test('a fat body with a WRONG reported size is still caught', () {
    // The v4 hole: the capture layer failed to measure the body, so the size
    // proxy read 0 and the body rode every snapshot uncapped.
    final big = 'x' * (snapshotBodyInlineLimit + 1);
    NetworkEventStore.instance.add(
      _event('lying', responseData: big, responseSize: 0),
    );
    final wire = _events().single;
    expect(wire.containsKey('responseData'), isFalse);
    expect(wire['responseBodyOmitted'], isTrue);
  });

  test('request bodies get the same treatment', () {
    final big = 'y' * (snapshotBodyInlineLimit + 1);
    NetworkEventStore.instance.add(
      _event('req', requestData: big, requestSize: 0),
    );
    final wire = _events().single;
    expect(wire.containsKey('requestData'), isFalse);
    expect(wire['requestBodyOmitted'], isTrue);
  });

  test('an oversized header value is truncated, keeping the key', () {
    NetworkEventStore.instance.add(
      _event('h', responseHeaders: {'set-cookie': 'c' * 4096, 'etag': 'w/"1"'}),
    );
    final wire = _events().single;
    final headers = (wire['responseHeaders']! as Map).cast<String, String>();
    expect(headers.containsKey('set-cookie'), isTrue);
    expect(headers['set-cookie']!.length, lessThan(200));
    expect(headers['set-cookie'], contains('more]'));
    // Untouched headers survive verbatim.
    expect(headers['etag'], 'w/"1"');
    expect(wire['headersOmitted'], isTrue);
  });

  test('degrades the tail instead of dropping the whole snapshot', () {
    // 500 responses of 9KB are each individually under the inline limit and
    // still total ~4.5MB — over the emit layer's 2MB, which drops the panel.
    final body = 'v' * (9 * 1024);
    for (var i = 0; i < 500; i++) {
      NetworkEventStore.instance.add(
        _event('e$i', responseData: body, responseSize: body.length),
      );
    }

    final events = _events();
    expect(events, hasLength(500));
    expect(jsonEncode(events).length, lessThan(maxSnapshotEmitBytes));
    expect(
      approxJsonSize(events, maxSnapshotEmitBytes).bytes,
      lessThan(maxSnapshotEmitBytes),
    );

    final inline = events.where((e) => e.containsKey('responseData')).toList();
    expect(inline, isNotEmpty);
    expect(inline.length, lessThan(500));

    // Every degraded event still says so, and still carries its metadata —
    // method/url/status are what make the list usable at all.
    final degraded = events.firstWhere(
      (e) => !e.containsKey('responseData'),
    );
    expect(degraded['responseBodyOmitted'], isTrue);
    expect(degraded['method'], 'GET');
    expect(degraded['status'], 200);
    expect(degraded['url'], isA<String>());
  });

  test('getCaptureStatus answers "why is the list empty?"', () {
    final status = networkSyncAdapter.actions['getCaptureStatus']!(null)!
        as Map<String, Object?>;
    expect(status.containsKey('capturing'), isTrue);
    expect(status.containsKey('subscribers'), isTrue);
    expect(status.containsKey('interceptorInstalled'), isTrue);
    expect(status['eventCount'], 0);

    NetworkEventStore.instance.add(_event('one'));
    final after = networkSyncAdapter.actions['getCaptureStatus']!(null)!
        as Map<String, Object?>;
    expect(after['eventCount'], 1);
  });

  test('getEventBody still returns the withheld body in full', () {
    final big = 'x' * (snapshotBodyInlineLimit + 1);
    NetworkEventStore.instance.add(
      _event('fetch-me', responseData: big, responseSize: big.length),
    );
    // The snapshot withheld it...
    expect(_events().single.containsKey('responseData'), isFalse);
    // ...and this is the channel that gets it back.
    final body = networkSyncAdapter.actions['getEventBody']!({
      'id': 'fetch-me',
    })! as Map<String, Object?>;
    expect(body['responseData'], big);
  });
}
