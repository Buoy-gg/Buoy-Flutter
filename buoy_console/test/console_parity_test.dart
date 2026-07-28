import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_console/src/console_log_store.dart';
import 'package:buoy_console/src/console_capture.dart';
import 'package:buoy_console/src/sanitize.dart';
import 'package:buoy_console/src/devtools/console_filter.dart';
import 'package:buoy_console/src/devtools/console_format.dart';
import 'package:buoy_console/src/devtools/console_messages.dart';
import 'package:buoy_console/src/devtools/console_origin.dart';

ConsoleLogEntry _entry(
  int id,
  String method,
  String message, {
  String? level,
}) =>
    ConsoleLogEntry(
      id: id,
      method: method,
      level: level ?? levelForMethod(method),
      args: [message],
      message: message,
      timestamp: 1000 + id,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConsoleLogStore.instance.resetForTest();
  });

  group('level mapping (RN METHOD_LEVEL)', () {
    test('print→log→info, debugPrint→debug→verbose, error→error', () {
      expect(levelForMethod('log'), 'info');
      expect(levelForMethod('debug'), 'verbose');
      expect(levelForMethod('error'), 'error');
      expect(levelForMethod('warn'), 'warning');
      expect(levelForMethod('info'), 'info');
      expect(levelForMethod('unknown'), 'info');
    });
  });

  group('store ring buffer', () {
    test('entries are chronological (oldest first, newest last)', () {
      final store = ConsoleLogStore.instance;
      store.record('log', ['a']);
      store.record('log', ['b']);
      store.record('log', ['c']);
      expect(store.entries.map((e) => e.message).toList(), ['a', 'b', 'c']);
    });

    test('caps at kConsoleMaxEntries, dropping the oldest', () {
      final store = ConsoleLogStore.instance;
      for (var i = 0; i < kConsoleMaxEntries + 25; i++) {
        store.record('log', ['line $i']);
      }
      expect(store.entries.length, kConsoleMaxEntries);
      // Oldest 25 dropped; newest retained at the end.
      expect(store.entries.first.message, 'line 25');
      expect(store.entries.last.message, 'line ${kConsoleMaxEntries + 24}');
    });

    test('monotonic ids increase per record', () {
      final store = ConsoleLogStore.instance;
      store.record('log', ['a']);
      store.record('log', ['b']);
      expect(store.entries[0].id, 1);
      expect(store.entries[1].id, 2);
    });

    test('clearEntries empties the buffer', () async {
      final store = ConsoleLogStore.instance;
      store.record('log', ['a']);
      store.clearEntries();
      expect(store.entries, isEmpty);
    });
  });

  group('toJson wire shape (RN field names)', () {
    test('carries id/method/level/args/message/timestamp + sanitized args', () {
      final entry = ConsoleLogEntry(
        id: 7,
        method: 'error',
        level: 'error',
        args: ['boom', {'a': 1}],
        message: 'boom {a:1}',
        timestamp: 123456,
        stack: 'frame0\nframe1',
        origin: const LogOrigin(functionName: 'build', callSite: 'main.dart:10'),
      );
      final json = entry.toJson();
      expect(json['id'], 7);
      expect(json['method'], 'error');
      expect(json['level'], 'error');
      expect(json['message'], 'boom {a:1}');
      expect(json['timestamp'], 123456);
      expect(json['stack'], 'frame0\nframe1');
      expect((json['args'] as List)[0], 'boom');
      expect((json['args'] as List)[1], {'a': 1});
      expect(
        (json['origin'] as Map)['functionName'],
        'build',
      );
      // Timestamp stays a number (ms epoch) — parity with RN's number field.
      expect(json['timestamp'], isA<int>());
    });
  });

  group('sanitizeArgs (RN sanitize.ts limits)', () {
    test('primitives pass through; non-finite → String', () {
      expect(sanitizeArgs(['s', 1, true, null]), ['s', 1, true, null]);
      expect(sanitizeArgs([double.infinity]), ['Infinity']);
      expect(sanitizeArgs([double.nan]), ['NaN']);
    });

    test('arrays truncate at MAX_ARRAY (100) with an overflow marker', () {
      final big = List<int>.generate(150, (i) => i);
      final out = sanitizeArgs([big]).first as List;
      expect(out.length, 101); // 100 items + 1 marker
      expect(out.last, '… 50 more');
    });

    test('maps truncate at MAX_KEYS (100)', () {
      final map = {for (var i = 0; i < 150; i++) 'k$i': i};
      final out = sanitizeArgs([map]).first as Map;
      expect(out.length, 100);
    });

    test('depth beyond MAX_DEPTH (6) collapses to a placeholder', () {
      Object nest(int d) => d == 0 ? 'leaf' : {'n': nest(d - 1)};
      final out = sanitizeArgs([nest(8)]).first;
      // Walk to depth 6 → placeholder.
      var cur = out;
      for (var i = 0; i < 6; i++) {
        cur = (cur as Map)['n'];
      }
      expect(cur, '{…}');
    });

    test('circular references break with [Circular]', () {
      final a = <String, Object?>{};
      a['self'] = a;
      final out = sanitizeArgs([a]).first as Map;
      expect(out['self'], '[Circular]');
    });
  });

  group('consoleFilter (RN ConsoleFilter)', () {
    test('default levels hide verbose', () {
      expect(defaultLevels['verbose'], isFalse);
      expect(defaultLevels['info'], isTrue);
      expect(defaultLevels['error'], isTrue);
    });

    test('levelMenuSummary matches DevTools text', () {
      expect(levelMenuSummary(allLevels), 'All levels');
      expect(levelMenuSummary(defaultLevels), 'Default levels');
      expect(
        levelMenuSummary(const LevelsMask(
          verbose: false,
          info: false,
          warning: false,
          error: true,
        )),
        'Errors only',
      );
      expect(
        levelMenuSummary(const LevelsMask(
          verbose: false,
          info: false,
          warning: false,
          error: false,
        )),
        'Hide all',
      );
      expect(
        levelMenuSummary(const LevelsMask(
          verbose: true,
          info: false,
          warning: true,
          error: false,
        )),
        'Custom levels',
      );
    });

    test('parseFilterQuery: substring, negation, regex, key:value', () {
      final parsed = parseFilterQuery('foo -bar /ba.+/ url:x');
      expect(parsed.length, 4);
      expect(parsed[0].text, 'foo');
      expect(parsed[0].negative, isFalse);
      expect(parsed[1].text, 'bar');
      expect(parsed[1].negative, isTrue);
      expect(parsed[2].regex, isNotNull);
      expect(parsed[3].key, 'url');
      expect(parsed[3].text, 'x');
    });

    test('shouldBeVisible applies level mask + text AND filters', () {
      final e = _entry(1, 'log', 'hello world');
      expect(shouldBeVisible(e, allLevels, parseFilterQuery('hello')), isTrue);
      expect(shouldBeVisible(e, allLevels, parseFilterQuery('-hello')), isFalse);
      expect(shouldBeVisible(e, allLevels, parseFilterQuery('nope')), isFalse);
      // verbose hidden under default levels.
      final v = _entry(2, 'debug', 'verbose line');
      expect(shouldBeVisible(v, defaultLevels, const []), isFalse);
      expect(shouldBeVisible(v, allLevels, const []), isTrue);
    });
  });

  group('consoleFormat (RN ConsoleFormat)', () {
    test('plain string arg → single string token', () {
      final tokens = formatConsoleMessage(['hello']);
      expect(tokens.length, 1);
      expect((tokens.first as StringToken).value, 'hello');
    });

    test('%s / %d / %i / %f substitutions', () {
      final tokens = formatConsoleMessage(['%s = %d (%f)', 'x', 3.9, 2.5]);
      final text =
          tokens.whereType<StringToken>().map((t) => t.value).join();
      expect(text, 'x = 3 (2.5)');
    });

    test('%% is a literal percent', () {
      final tokens = formatConsoleMessage(['100%% done']);
      expect((tokens.first as StringToken).value, '100% done');
    });

    test('%o / %O produce a ValueToken', () {
      final tokens = formatConsoleMessage([
        'obj %o',
        {'a': 1},
      ]);
      expect(tokens.whereType<ValueToken>().length, 1);
    });

    test('%c applies a CSS style to following text', () {
      final tokens =
          formatConsoleMessage(['%cred', 'color: red; font-weight: bold']);
      final styled = tokens.whereType<StringToken>().firstWhere(
            (t) => t.value == 'red',
          );
      expect(styled.style?.fontWeight, FontWeight.bold);
    });

    test('trailing non-string args are appended as value tokens', () {
      final tokens = formatConsoleMessage([
        'x',
        {'a': 1},
      ]);
      expect(tokens.whereType<ValueToken>().length, 1);
    });
  });

  group('origin (RN origin.ts)', () {
    test('bracketGlyph maps runs to lnav glyphs', () {
      expect(bracketGlyph(Bracket.top), '┌');
      expect(bracketGlyph(Bracket.mid), '│');
      expect(bracketGlyph(Bracket.bottom), '└');
      expect(bracketGlyph(Bracket.single), '─');
    });

    test('sourceKey/sourceLabel fall back across signals', () {
      const o = LogOrigin(functionName: 'build', callSite: 'main.dart:10');
      expect(sourceKey(o, GroupDimension.function), 'build');
      expect(sourceLabel(o, GroupDimension.function), 'build');
      expect(sourceKey(null, GroupDimension.function), '—unknown—');
      expect(sourceKey(o, GroupDimension.off), isNull);
    });

    test('parseOrigin extracts function + call site from a Dart stack', () {
      final stack = StackTrace.fromString(
        '#0      ConsoleLogStore.record (package:buoy_console/src/console_log_store.dart:170:5)\n'
        '#1      BuoyConsole.install.<anonymous closure> (package:buoy_console/src/console_capture.dart:60:9)\n'
        '#2      MyWidget.build (package:example/main.dart:42:7)\n',
      );
      final origin = parseOrigin(stack);
      expect(origin, isNotNull);
      expect(origin!.functionName, 'MyWidget.build');
      expect(origin.file, 'main.dart');
      expect(origin.line, 42);
      expect(origin.callSite, 'main.dart:42');
    });

    test('colorForKey is stable per key', () {
      expect(colorForKey('a'), isA<Color>());
      expect(colorForKey('a'), colorForKey('a'));
    });
  });

  group('buildDisplayRows (RN useConsoleMessages)', () {
    BuildOptions opts({
      bool timestamps = false,
      LevelsMask mask = allLevels,
      String query = '',
      LayoutMode layout = LayoutMode.chrono,
    }) =>
        BuildOptions(
          levelsMask: mask,
          query: query,
          showTimestamps: timestamps,
          collapsedOverrides: const {},
          groupDimension: GroupDimension.off,
          layoutMode: layout,
          clusterExpanded: const {},
        );

    test('consecutive identical messages collapse into a repeat count', () {
      final entries = [
        _entry(1, 'log', 'same'),
        _entry(2, 'log', 'same'),
        _entry(3, 'log', 'same'),
        _entry(4, 'log', 'other'),
      ];
      final result = buildDisplayRows(entries, opts());
      expect(result.rows.length, 2);
      expect(result.rows.first.repeatCount, 3);
      expect(result.rows.last.repeatCount, 1);
    });

    test('repeat collapse is disabled when timestamps are shown', () {
      final entries = [
        _entry(1, 'log', 'same'),
        _entry(2, 'log', 'same'),
      ];
      final result = buildDisplayRows(entries, opts(timestamps: true));
      expect(result.rows.length, 2);
    });

    test('level filter hides rows and counts them', () {
      final entries = [
        _entry(1, 'log', 'info line'),
        _entry(2, 'debug', 'verbose line'),
      ];
      final result = buildDisplayRows(entries, opts(mask: defaultLevels));
      expect(result.rows.length, 1);
      expect(result.hiddenCount, 1);
      expect(result.levelCounts['verbose'], 1);
      expect(result.levelCounts['info'], 1);
    });

    test('console.group nesting collapses child rows', () {
      final entries = [
        _entry(1, 'groupCollapsed', 'Group'),
        _entry(2, 'log', 'child a'),
        _entry(3, 'log', 'child b'),
        _entry(4, 'groupEnd', ''),
        _entry(5, 'log', 'after'),
      ];
      final result = buildDisplayRows(entries, opts());
      // Header + "after" visible; children hidden under the collapsed group.
      expect(result.rows.map((r) => r.entry.message).toList(),
          ['Group', 'after']);
      expect(result.rows.first.isGroupHeader, isTrue);
      expect(result.rows.first.groupCollapsed, isTrue);
    });

    test('grouped/cluster layout collapses large same-source clusters', () {
      final entries = [
        for (var i = 0; i < 8; i++)
          ConsoleLogEntry(
            id: i + 1,
            method: 'log',
            level: 'info',
            args: ['line $i'],
            message: 'line $i',
            timestamp: 1000 + i,
            origin: const LogOrigin(functionName: 'hotLoop'),
          ),
      ];
      final result = buildDisplayRows(
        entries,
        BuildOptions(
          levelsMask: allLevels,
          query: '',
          showTimestamps: false,
          collapsedOverrides: const {},
          groupDimension: GroupDimension.function,
          layoutMode: LayoutMode.cluster,
          clusterExpanded: const {},
        ),
      );
      // 8 > threshold (5) → one collapsed cluster header row.
      expect(result.rows.length, 1);
      expect(result.rows.first.clusterHeader, isNotNull);
      expect(result.rows.first.clusterHeader!.count, 8);
    });
  });

  group('preserve log persistence', () {
    test('setPreserveLog persists the flag and saved buffer', () async {
      final store = ConsoleLogStore.instance;
      store.record('log', ['keep me']);
      store.setPreserveLog(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('@react_buoy_console_preserve'), 'true');
      expect(prefs.getString('@react_buoy_console_buffer'), isNotNull);
    });

    test('initPersistence restores a saved buffer when preserve is on',
        () async {
      SharedPreferences.setMockInitialValues({
        '@react_buoy_console_preserve': 'true',
        '@react_buoy_console_buffer':
            '[{"id":5,"method":"log","level":"info","args":["restored"],'
                '"message":"restored","timestamp":999}]',
      });
      final store = ConsoleLogStore.instance;
      await store.initPersistence();
      expect(store.entries.length, 1);
      expect(store.entries.first.message, 'restored');
      // nextId advances past the restored id.
      store.record('log', ['new']);
      expect(store.entries.last.id, greaterThan(5));
    });

    test('initPersistence drops a stale buffer when preserve is off', () async {
      SharedPreferences.setMockInitialValues({
        '@react_buoy_console_preserve': 'false',
        '@react_buoy_console_buffer': '[{"id":1,"method":"log"}]',
      });
      final store = ConsoleLogStore.instance;
      await store.initPersistence();
      expect(store.entries, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('@react_buoy_console_buffer'), isNull);
    });
  });

  group('capture double-guard (debugPrint)', () {
    test('a debugPrint yields exactly one debug entry (not debug + log)',
        () async {
      final store = ConsoleLogStore.instance;
      BuoyConsole.install();
      // Let initPersistence settle.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final before = store.entries.length;
      debugPrint('guard-check line');
      final added = store.entries.skip(before).toList();
      expect(added.length, 1);
      expect(added.first.method, 'debug');
      expect(added.first.level, 'verbose');
      expect(added.first.message, 'guard-check line');
    });
  });
}
