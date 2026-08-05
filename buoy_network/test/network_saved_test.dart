import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_network/buoy_network.dart';

/// Pins and saves, and the identity rules that make them survivable.
///
/// The subtle part is not the toggling — it's that ids are per-runtime
/// counters, so a restored snapshot must never be confused with a live request
/// that happens to have the same id.

NetworkCaptureEvent event({
  String id = 'flt-1',
  String url = 'https://api.dev/users',
  String method = 'GET',
  int? status = 200,
  Object? responseData,
  int? responseSize,
}) => NetworkCaptureEvent(
  id: id,
  method: method,
  url: url,
  timestamp: 1,
  requestClient: 'dio',
)
  ..status = status
  ..responseData = responseData
  ..responseSize = responseSize;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NetworkSavedStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = NetworkSavedStore.instance..resetForTest();
    NetworkEventStore.instance.capturing = true;
    NetworkEventStore.instance.clear();
  });

  group('flags', () {
    test('pin and save are independent, and the record dies with both', () {
      final e = event();

      store.togglePin(e);
      expect(store.isPinned('flt-1'), isTrue);
      expect(store.isSaved('flt-1'), isFalse);
      expect(store.records, hasLength(1));

      store.toggleSave(e);
      expect(store.isPinned('flt-1'), isTrue);
      expect(store.isSaved('flt-1'), isTrue);
      // Still ONE record carrying two flags, not two records.
      expect(store.records, hasLength(1));

      store.togglePin(e);
      expect(store.records, hasLength(1), reason: 'still saved');

      store.toggleSave(e);
      expect(store.records, isEmpty, reason: 'both flags off drops it');
    });

    test('flagsForEventId finds a live id and a restored snapshot id', () {
      store.togglePin(event(id: 'flt-9'));
      expect(flagsForEventId(store.state, 'flt-9').pinned, isTrue);
      expect(flagsForEventId(store.state, 'nope').pinned, isFalse);
      expect(flagsForEventId(store.state, null).pinned, isFalse);
    });

    test('the derived view separates pinned events from saved records', () {
      store.togglePin(event(id: 'a', url: 'https://api.dev/a'));
      store.toggleSave(event(id: 'b', url: 'https://api.dev/b'));

      expect(store.state.pinnedEvents.map((e) => e.id), ['a']);
      expect(store.state.savedRecords.map((r) => r.event.id), ['b']);
      expect(store.state.pinnedLiveIds, {'a'});
      expect(store.state.savedLiveIds, {'b'});
    });
  });

  group('snapshots', () {
    test('a pin is FROZEN — the live event mutating does not change it', () {
      final live = event(responseData: 'first');
      store.togglePin(live);

      // The live event keeps streaming after the pin.
      live.responseData = 'second';
      live.status = 500;

      final pinned = store.state.pinnedEvents.single;
      expect(pinned.responseData, 'first');
      expect(pinned.status, 200);
    });

    test('syncFromLive refreshes a tracked pin so it cannot stay Pending', () {
      final live = event(status: null);
      store.togglePin(live);
      expect(store.state.pinnedEvents.single.status, isNull);

      live.status = 204;
      store.syncFromLive(live);

      expect(store.state.pinnedEvents.single.status, 204);
    });

    test('syncFromLive ignores events nothing is tracking', () {
      store.togglePin(event(id: 'a'));
      // Must not throw, must not add anything.
      store.syncFromLive(event(id: 'other'));
      expect(store.records, hasLength(1));
    });

    test('an oversized body is truncated with a visible marker', () {
      store.togglePin(event(responseData: 'x' * (20 * 1024)));
      final record = store.records.single;
      expect(record.bodyTruncated, isTrue);
      expect(record.event.responseData, contains('truncated by Buoy'));
    });
  });

  group('caps', () {
    test('pins stop at maxPinned and say why', () {
      for (var i = 0; i < maxPinned; i++) {
        expect(store.togglePin(event(id: 'p$i')).succeeded, isTrue);
      }
      final refused = store.togglePin(event(id: 'over'));
      expect(refused.succeeded, isFalse);
      expect(refused.reason, SavedToggleFailure.pinCap);
      expect(store.state.pinnedEvents, hasLength(maxPinned));
    });

    test('saves stop at maxSaved and say why', () {
      for (var i = 0; i < maxSaved; i++) {
        expect(store.toggleSave(event(id: 's$i')).succeeded, isTrue);
      }
      // RN refuses at the ceiling rather than silently dropping the oldest —
      // eviction only exists for a list restored from storage that already
      // exceeds it.
      final refused = store.toggleSave(event(id: 'over'));
      expect(refused.succeeded, isFalse);
      expect(refused.reason, SavedToggleFailure.savedCap);
      expect(store.state.savedRecords, hasLength(maxSaved));
    });

    test('unsaving one makes room again', () {
      for (var i = 0; i < maxSaved; i++) {
        store.toggleSave(event(id: 's$i'));
      }
      store.toggleSave(event(id: 's0'));
      expect(store.toggleSave(event(id: 'over')).succeeded, isTrue);
    });

    test('a junk event is refused rather than persisted', () {
      // `id`/`url` are what the row dereferences without guarding; a record
      // that fails there would crash the list on every launch, forever.
      final bad = NetworkCaptureEvent(
        id: '',
        method: 'GET',
        url: '',
        timestamp: 0,
        requestClient: 'http',
      );
      final result = store.togglePin(bad);
      expect(result.succeeded, isFalse);
      expect(result.reason, SavedToggleFailure.invalidEvent);
      expect(store.records, isEmpty);
    });
  });

  group('bulk actions', () {
    test('clearSaved keeps pinned-only records', () {
      store.togglePin(event(id: 'p'));
      store.toggleSave(event(id: 's'));
      store.clearSaved();

      expect(store.state.savedRecords, isEmpty);
      expect(store.state.pinnedEvents.map((e) => e.id), ['p']);
    });

    test('clearPinned keeps saved-only records', () {
      store.togglePin(event(id: 'p'));
      store.toggleSave(event(id: 's'));
      store.clearPinned();

      expect(store.state.pinnedEvents, isEmpty);
      expect(store.state.savedRecords.map((r) => r.liveId), ['s']);
    });

    test('a record flagged BOTH survives clearSaved as a pin', () {
      final e = event(id: 'both');
      store.togglePin(e);
      store.toggleSave(e);
      store.clearSaved();

      expect(store.records, hasLength(1));
      expect(store.records.single.pinned, isTrue);
      expect(store.records.single.saved, isFalse);
    });

    test('remove drops a record by key whatever its flags', () {
      store.togglePin(event(id: 'a'));
      store.remove(store.records.single.key);
      expect(store.records, isEmpty);
    });
  });

  group('splitPinned', () {
    test('pins are hoisted and de-duplicated out of the rest', () {
      final live = [event(id: 'a'), event(id: 'b'), event(id: 'c')];
      final split = splitPinned(live, [live[1]], {'b'});

      expect(split.pinned.map((e) => e.id), ['b']);
      // 'b' must not render twice.
      expect(split.rest.map((e) => e.id), ['a', 'c']);
    });

    test('no pins is a pass-through, not a copy', () {
      final live = [event(id: 'a')];
      final split = splitPinned(live, const [], const {});
      expect(identical(split.rest, live), isTrue);
      expect(split.pinned, isEmpty);
    });

    test('a pin from an earlier session stays visible but does not dedupe', () {
      // Restored snapshots carry no live id, so nothing is filtered out of the
      // live list — which is right: they are different requests.
      final live = [event(id: 'a')];
      final restored = event(id: 'saved:key1');
      final split = splitPinned(live, [restored], const {});

      expect(split.pinned.map((e) => e.id), ['saved:key1']);
      expect(split.rest.map((e) => e.id), ['a']);
    });
  });

  group('selectSavedEvents', () {
    test('search matches url, method and status', () {
      store.toggleSave(event(id: 'a', url: 'https://api.dev/users'));
      store.toggleSave(
        event(id: 'b', url: 'https://api.dev/posts', method: 'POST', status: 404),
      );
      final saved = store.state.savedRecords;

      expect(selectSavedEvents(saved, ''), hasLength(2));
      expect(selectSavedEvents(saved, 'users').single.id, 'a');
      expect(selectSavedEvents(saved, 'post'), hasLength(1));
      expect(selectSavedEvents(saved, '404').single.id, 'b');
      expect(selectSavedEvents(saved, 'nothing'), isEmpty);
    });
  });

  group('sync actions', () {
    Object? call(String action, [Object? params]) =>
        networkSyncAdapter.actions[action]!(params);

    test('the adapter exposes RN\'s pin/save action names', () {
      for (final name in const [
        'setPinned',
        'setSaved',
        'removeSavedRecord',
        'clearSavedRequests',
        'clearPinnedRequests',
      ]) {
        expect(
          networkSyncAdapter.actions.containsKey(name),
          isTrue,
          reason: 'missing sync action `$name`',
        );
      }
    });

    test('setPinned resolves a live event and is idempotent', () {
      final e = event(id: 'flt-1');
      NetworkEventStore.instance.add(e);

      expect((call('setPinned', {'id': 'flt-1', 'pinned': true})! as Map)['ok'],
          isTrue);
      expect(store.isPinned('flt-1'), isTrue);

      // Asking for the state it is already in must not toggle it back off.
      call('setPinned', {'id': 'flt-1', 'pinned': true});
      expect(store.isPinned('flt-1'), isTrue);

      call('setPinned', {'id': 'flt-1', 'pinned': false});
      expect(store.isPinned('flt-1'), isFalse);
    });

    test('setSaved resolves through the snapshot once the live event is gone', () {
      // The whole point of a snapshot: the request outlives the stream.
      store.togglePin(event(id: 'flt-7'));
      NetworkEventStore.instance.clear();
      expect(NetworkEventStore.instance.byId('flt-7'), isNull);

      final result = call('setSaved', {'id': 'flt-7', 'saved': true})! as Map;
      expect(result['ok'], isTrue);
      expect(store.isSaved('flt-7'), isTrue);
    });

    test('the snapshot carries saved records alongside events', () {
      store.togglePin(event(id: 'a'));
      final snapshot = networkSyncAdapter.getSnapshot() as Map;
      expect(snapshot.containsKey('saved'), isTrue);
      expect(snapshot['saved'], hasLength(1));
    });

    test('an oversized saved body is stripped from the snapshot', () {
      store.togglePin(
        event(responseData: 'y' * 5000, responseSize: 20 * 1024),
      );
      final saved = (networkSyncAdapter.getSnapshot() as Map)['saved']! as List;
      final event0 = (saved.single as Map)['event']! as Map;
      expect(event0.containsKey('responseData'), isFalse);
      expect(event0['responseSize'], 20 * 1024);
    });

    test('clear actions mirror the store', () {
      store.togglePin(event(id: 'p'));
      store.toggleSave(event(id: 's'));

      call('clearSavedRequests');
      expect(store.state.savedRecords, isEmpty);
      call('clearPinnedRequests');
      expect(store.state.pinnedEvents, isEmpty);
    });
  });
}
