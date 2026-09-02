// Pins the RN timeline rule: the store's boot scan synthesizes a `setItem`
// per key already on disk (for the STORAGE tool's state views); the Events
// timeline must not report those as writes that happened.
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:buoy_storage/buoy_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageEventStore.instance.replaceEvents([]);
    registerBuoyStorage();
  });
  tearDown(() => StorageEventStore.instance.replaceEvents([]));

  test('initial-scan synthetics are not timeline events; real writes are', () {
    final source = eventSourceRegistry.byId('storage')!;
    final seen = <String>[];
    final unsub = source.subscribe((e) => seen.add(e.title));

    StorageEventStore.instance.addEvent(StorageEvent(
      id: 's1',
      action: 'setItem',
      timestamp: DateTime.now(),
      storageType: 'async',
      key: '@app/existing',
      value: '1',
      initialScan: true,
    ));
    expect(seen, isEmpty);

    StorageEventStore.instance.addEvent(StorageEvent(
      id: 's2',
      action: 'setItem',
      timestamp: DateTime.now(),
      storageType: 'async',
      key: '@app/written',
      value: '2',
    ));
    expect(seen, hasLength(1));
    unsub();
  });
}
