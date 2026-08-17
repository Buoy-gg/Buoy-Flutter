/// Ports packages/storage/src/storage/sync/__tests__/storageSyncAdapter.test.ts.
///
/// The wire-form and budget cases are the point. A storage snapshot is rebuilt
/// ~5x/sec while a dashboard watches, and the failure modes are silent: an
/// oversized value either janks the UI isolate or pushes the snapshot past the
/// emit budget, which drops the WHOLE panel and just looks like a stale
/// dashboard. Each test below pins one of those.
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_storage/src/storage_capture.dart';
import 'package:buoy_storage/src/storage_sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

StorageEvent _asyncEvent(
  String id, {
  Object? value,
  Object? prevValue,
  String key = '',
  String type = 'async',
}) => StorageEvent(
  id: id,
  action: 'setItem',
  timestamp: DateTime.utc(2026, 8, 12, 12),
  storageType: type,
  key: key.isEmpty ? '@app/$id' : key,
  value: value,
  prevValue: prevValue,
);

List<Map<String, Object?>> _snapshot() =>
    (storageSyncAdapter.getSnapshot()! as List).cast<Map<String, Object?>>();

Map<String, Object?>? _dataOf(Map<String, Object?> event) =>
    event['data'] as Map<String, Object?>?;

Map<String, Object?>? _byId(List<Map<String, Object?>> events, String id) {
  for (final e in events) {
    if (e['id'] == id) return e;
  }
  return null;
}

void main() {
  tearDown(() => StorageEventStore.instance.replaceEvents([]));

  test('exposes version 3 and the listed actions', () {
    expect(storageSyncAdapter.version, 3);
    expect(
      storageSyncAdapter.actions.keys,
      containsAll(<String>[
        'clearEvents',
        'getEventDetail',
        'clearAppStorage',
        'timeTravel.undo',
        'timeTravel.jump',
        'mmkv.snapshot',
        'mmkv.get',
        'secure.snapshot',
      ]),
    );
  });

  test("snapshots a JSON list and strips Buoy's own keys", () {
    StorageEventStore.instance.replaceEvents([
      _asyncEvent('app', value: 'v', key: '@app/theme'),
      _asyncEvent('buoy', value: 'v', key: '@react_buoy_network_modal'),
    ]);

    final snapshot = _snapshot();
    expect(snapshot, hasLength(1));
    expect(_dataOf(snapshot.first)?['key'], '@app/theme');
  });

  test('keeps small values inline and strips oversized ones', () {
    final large = 'x' * (snapshotValueInlineLimit + 1);
    StorageEventStore.instance.replaceEvents([
      _asyncEvent('se-small', value: 'on', prevValue: 'off', key: 'flag'),
      _asyncEvent('se-large', value: large, prevValue: large, key: 'blob'),
    ]);

    final snapshot = _snapshot();
    final small = _byId(snapshot, 'se-small');
    final big = _byId(snapshot, 'se-large');

    expect(_dataOf(small!)?['value'], 'on');
    expect(_dataOf(small)?['prevValue'], 'off');
    expect(_dataOf(big!)?['value'], valueOnDevice);
    expect(_dataOf(big)?['prevValue'], valueOnDevice);
    // Metadata survives — a degraded value must never cost the key.
    expect(_dataOf(big)?['key'], 'blob');
    expect(jsonEncode(snapshot).length, lessThan(64 * 1024));

    // ...and the real value is still reachable on demand.
    final detail =
        storageSyncAdapter.actions['getEventDetail']!({'id': 'se-large'})
            as Map<String, Object?>;
    expect(detail['found'], isTrue);
    expect(detail['id'], 'se-large');
    final event = detail['event']! as Map<String, Object?>;
    expect(_dataOf(event)?['value'], large);
    expect(_dataOf(event)?['prevValue'], large);
  });

  test('does not drop a burst of large setItems under the emit budget', () {
    final large = 'x' * (20 * 1024);
    StorageEventStore.instance.replaceEvents([
      for (var i = 0; i < 80; i++)
        _asyncEvent('se-$i', value: large, prevValue: large),
    ]);

    final snapshot = _snapshot();
    expect(snapshot, hasLength(80));
    expect(_dataOf(snapshot.first)?['value'], valueOnDevice);
    expect(jsonEncode(snapshot).length, lessThan(maxSnapshotEmitBytes));
  });

  test('degrades the oldest events instead of dropping the whole snapshot', () {
    // 500 writes of a 9KB value are each individually under the inline limit
    // and still total ~4.7MB — over the emit layer's 2MB, which drops the
    // WHOLE panel. Newest keep their values; the tail degrades.
    StorageEventStore.instance.replaceEvents([
      for (var i = 0; i < 500; i++) _asyncEvent('e$i', value: 'v' * (9 * 1024)),
    ]);

    final snapshot = _snapshot();
    expect(snapshot, hasLength(500));
    expect(jsonEncode(snapshot).length, lessThan(maxSnapshotEmitBytes));

    final inline = snapshot
        .where((e) => _dataOf(e)?['value'] is String)
        .toList();
    expect(inline, isNotEmpty);
    expect(inline.length, lessThan(500));
    // Newest-first: the detail a developer is looking at is the detail kept.
    expect(_dataOf(snapshot.first)?['value'], isA<String>());
    expect(_dataOf(snapshot[499])?['value'], valueOnDevice);
    // Metadata survives on every event, degraded or not.
    expect(_dataOf(snapshot[499])?['key'], '@app/e499');
    expect(snapshot[499]['action'], 'setItem');
  });

  test('reuses the wire form of an unchanged event across snapshots', () {
    // Events are immutable in the store, so re-deriving them every tick is
    // pure waste — for storage that means re-walking megabytes per tick.
    StorageEventStore.instance.replaceEvents([
      _asyncEvent('a', value: 'small'),
      _asyncEvent('b', value: 'y' * (snapshotValueInlineLimit + 1)),
    ]);

    final first = _snapshot();
    final second = _snapshot();
    expect(identical(second[0], first[0]), isTrue);
    expect(identical(second[1], first[1]), isTrue);
  });

  test('still withholds a SMALL cyclic value', () {
    // Under every size limit, but `jsonEncode` throws on it — and an
    // exception out of getSnapshot takes the whole panel down.
    final cyclic = <String, Object?>{'name': 'root'};
    cyclic['self'] = cyclic;
    StorageEventStore.instance.replaceEvents([
      _asyncEvent('cyc', value: cyclic),
    ]);

    final snapshot = _snapshot();
    expect(_dataOf(snapshot.first)?['value'], valueOnDevice);
    expect(() => jsonEncode(snapshot), returnsNormally);
  });

  test('ALLOWS structural sharing, which is not a cycle', () {
    // The events-adapter regression, guarded here too: `{user, currentUser}`
    // pointing at one map is commonplace and encodes fine.
    final shared = {'id': 1};
    StorageEventStore.instance.replaceEvents([
      _asyncEvent('shared', value: {'user': shared, 'currentUser': shared}),
    ]);

    final value = _dataOf(_snapshot().first)?['value']! as Map<String, Object?>;
    expect(value['user'], shared);
    expect(value['currentUser'], shared);
  });

  test('never grafts a value field onto an event that had none', () {
    // `toJson` omits null value/prevValue. A blind wire-form assignment would
    // invent `value: null` fields the RN wire form does not have, and the
    // desktop detail pane renders "null" rather than an absent row.
    StorageEventStore.instance.replaceEvents([
      _asyncEvent('rm', key: 'gone'),
    ]);

    final data = _dataOf(_snapshot().first)!;
    expect(data.containsKey('value'), isFalse);
    expect(data.containsKey('prevValue'), isFalse);
    expect(data['key'], 'gone');
  });

  test('getEventDetail reports a missing or unknown id', () {
    final missing =
        storageSyncAdapter.actions['getEventDetail']!(<String, Object?>{})
            as Map<String, Object?>;
    expect(missing['found'], isFalse);
    expect(missing['reason'], 'missing id');

    final unknown =
        storageSyncAdapter.actions['getEventDetail']!({'id': 'nope'})
            as Map<String, Object?>;
    expect(unknown['found'], isFalse);
    expect(unknown['reason'], 'unknown id');
  });

  test('a snapshot of every event still fits the emit budget', () {
    // The end-to-end promise: whatever the store holds, the emit layer's
    // choke-point guard must never have to drop it.
    StorageEventStore.instance.replaceEvents([
      for (var i = 0; i < 500; i++)
        _asyncEvent(
          'big$i',
          value: 'v' * (40 * 1024),
          prevValue: 'p' * (40 * 1024),
        ),
    ]);

    final walk = approxJsonSize(_snapshot(), maxSnapshotEmitBytes);
    expect(walk.bytes, lessThan(maxSnapshotEmitBytes));
  });
}
