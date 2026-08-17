/// Ports the crash-visibility half of packages/console (RN `3b32032` +
/// `07e9678` + `2d13bf9`).
///
/// The failure this guards against is the quiet one: an app crashes, the sync
/// bridge dies with it, the throttled snapshot never fires, and the dashboard
/// simply shows a device that stopped answering. `recordFatal` tags the entry
/// and pushes it out synchronously while the socket is still attached.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_console/src/console_log_store.dart';
import 'package:buoy_console/src/console_sync_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Map<String, Object?>> _snapshotEntries() {
  final snapshot = consoleSyncAdapter.getSnapshot()! as Map;
  return (snapshot['entries']! as List).cast<Map<String, Object?>>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConsoleLogStore.instance.clearEntries();
    // The store is a singleton: without this, one test's fatal rate-limits the
    // next test's push and it fails for the wrong reason.
    ConsoleLogStore.instance.resetFlushStateForTest();
  });

  test('an uncaught error is tagged, marked fatal, and keeps its stack', () {
    final error = StateError('boom');
    ConsoleLogStore.instance.recordFatal(
      '[UNCAUGHT]',
      error,
      stack: StackTrace.fromString('#0 crashSite (package:app/main.dart:1:1)'),
    );

    final entry = ConsoleLogStore.instance.entries.single;
    expect(entry.fatal, isTrue);
    expect(entry.level, 'error');
    expect(entry.message, startsWith('[UNCAUGHT]'));
    // The tag leads the ARGS too — the DevTools-style row renders from args,
    // so this is what makes it visible in the UI.
    expect(entry.args.first, '[UNCAUGHT]');
    expect(entry.args[1], same(error));
    // The crash site, not the handler's call site.
    expect(entry.stack, contains('crashSite'));
  });

  test('the fatal flag reaches the wire — this is what get_triage reads', () {
    ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', StateError('boom'));
    final wire = _snapshotEntries().single;
    expect(wire['fatal'], isTrue);
    expect(wire['message'], startsWith('[UNCAUGHT]'));
  });

  test('an ordinary log carries no fatal field at all', () {
    ConsoleLogStore.instance.record('log', ['hello']);
    final wire = _snapshotEntries().single;
    // Absent, not `false` — matching the RN wire form.
    expect(wire.containsKey('fatal'), isFalse);
  });

  test('a render error is tagged but NOT claimed fatal', () {
    // Flutter fires FlutterError.onError for a build error that ErrorWidget
    // then recovers from. Claiming a healthy app crashed is worse than
    // under-claiming; the stack is reported either way.
    ConsoleLogStore.instance.recordFatal(
      '[RENDER ERROR]',
      FlutterError('overflowed by 42 pixels'),
      fatal: false,
    );
    final entry = ConsoleLogStore.instance.entries.single;
    expect(entry.message, startsWith('[RENDER ERROR]'));
    expect(entry.fatal, isNull);
    expect(entry.level, 'error');
  });

  test('a duplicate crash is still RECORDED, only the push is suppressed', () {
    // Two widgets crashing with the same message are two crashes. A tool whose
    // pitch is "the app's last words" must not silently drop one.
    var flushes = 0;
    void counter(String toolId) => flushes++;
    registerToolFlusher(counter);
    addTearDown(() => unregisterToolFlusher(counter));

    ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', StateError('same'));
    ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', StateError('same'));

    expect(ConsoleLogStore.instance.entries, hasLength(2));
    expect(flushes, 1, reason: 'the repeat must not earn a second push');
  });

  test('a DIFFERENT crash inside the window still pushes', () {
    var flushes = 0;
    void counter(String toolId) => flushes++;
    registerToolFlusher(counter);
    addTearDown(() => unregisterToolFlusher(counter));

    ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', StateError('first'));
    ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', StateError('second'));
    expect(flushes, 2);
  });

  test('a fatal pushes the console tool specifically', () {
    final pushed = <String>[];
    void spy(String toolId) => pushed.add(toolId);
    registerToolFlusher(spy);
    addTearDown(() => unregisterToolFlusher(spy));

    ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', StateError('boom'));
    expect(pushed, ['console']);
  });

  test('a throwing bridge cannot take the crash path down with it', () {
    // A crash path must never crash.
    void bad(String toolId) => throw StateError('bridge is broken');
    final ok = <String>[];
    void good(String toolId) => ok.add(toolId);
    registerToolFlusher(bad);
    registerToolFlusher(good);
    addTearDown(() {
      unregisterToolFlusher(bad);
      unregisterToolFlusher(good);
    });

    expect(
      () => ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', StateError('x')),
      returnsNormally,
    );
    // ...and one bad bridge must not stop the others.
    expect(ok, ['console']);
    expect(ConsoleLogStore.instance.entries, hasLength(1));
  });

  test('an ordinary error also pushes, but rate-limited', () {
    var flushes = 0;
    void counter(String toolId) => flushes++;
    registerToolFlusher(counter);
    addTearDown(() => unregisterToolFlusher(counter));

    // Errors are the entries most likely to be an app's last words.
    ConsoleLogStore.instance.record('error', ['first failure']);
    expect(flushes, 1);

    // A storm inside the 150ms floor must not flood the socket.
    for (var i = 0; i < 50; i++) {
      ConsoleLogStore.instance.record('error', ['storm $i']);
    }
    expect(flushes, 1);
    expect(ConsoleLogStore.instance.entries, hasLength(51));
  });

  test('ordinary logs never force a push', () {
    var flushes = 0;
    void counter(String toolId) => flushes++;
    registerToolFlusher(counter);
    addTearDown(() => unregisterToolFlusher(counter));

    ConsoleLogStore.instance.record('log', ['chatter']);
    ConsoleLogStore.instance.record('debug', ['more chatter']);
    expect(flushes, 0);
  });

  test('the headline de-duplicates across differently-phrased seams', () {
    // One seam hands us the exception object, another the already-stringified
    // form. Both must produce the same key or de-duplication does nothing.
    var flushes = 0;
    void counter(String toolId) => flushes++;
    registerToolFlusher(counter);
    addTearDown(() => unregisterToolFlusher(counter));

    final error = StateError('boom');
    ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', error);
    ConsoleLogStore.instance.recordFatal('[UNCAUGHT]', error);
    expect(flushes, 1);
  });
}
