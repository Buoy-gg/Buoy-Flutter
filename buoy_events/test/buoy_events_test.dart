import 'dart:convert';

import 'package:buoy_events/buoy_events.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter_test/flutter_test.dart';

UnifiedEvent ev({
  required String id,
  required String source,
  required int ts,
  required String title,
  String subtitle = '',
  EventStatus status = EventStatus.neutral,
  Map<String, Object?>? data,
}) {
  return UnifiedEvent(
    id: id,
    source: source,
    timestamp: ts,
    title: title,
    subtitle: subtitle,
    status: status,
    originalEvent: null,
    data: data ?? const {},
  );
}

void main() {
  group('filterEvents', () {
    final events = [
      ev(id: 'n1', source: EventSourceIds.network, ts: 1, title: 'GET /a', status: EventStatus.success),
      ev(id: 's1', source: EventSourceIds.storageAsync, ts: 2, title: 'Set Item', status: EventStatus.success),
      ev(id: 'r1', source: EventSourceIds.route, ts: 3, title: '/home', status: EventStatus.error),
    ];

    test('by status', () {
      final only = filterEvents(
        events,
        kDefaultCopySettings.copyWith(filterMode: ExportFilterMode.errors),
      );
      expect(only.map((e) => e.id), ['r1']);
    });

    test('by source (granular)', () {
      final only = filterEvents(
        events,
        kDefaultCopySettings.copyWith(filterSources: [EventSourceIds.network]),
      );
      expect(only.map((e) => e.id), ['n1']);
    });
  });

  group('generateExport', () {
    final events = [
      ev(id: 'n1', source: EventSourceIds.network, ts: 1000, title: 'GET /pokemon', subtitle: '200 · 12ms · api.co', status: EventStatus.success),
      ev(id: 'r1', source: EventSourceIds.route, ts: 2000, title: '/pokemon', subtitle: 'navigation', status: EventStatus.neutral),
    ];

    test('markdown includes summary + source labels + status icons', () {
      final out = generateExport(events, kDefaultCopySettings);
      expect(out, contains('## Event Flow'));
      expect(out, contains('**Network**'));
      expect(out, contains('**Route**'));
      expect(out, contains('✅')); // success icon
      expect(out, contains('GET /pokemon'));
      // Oldest-first timeline: network (ts 1000) before route (ts 2000).
      expect(out.indexOf('GET /pokemon'), lessThan(out.indexOf('/pokemon\n')
          .clamp(0, out.length)));
    });

    test('json is valid and carries summary + events', () {
      final settings = kCopyPresets['json']!;
      final out = generateExport(events, settings);
      final decoded = jsonDecode(out) as Map<String, Object?>;
      expect(decoded.containsKey('events'), isTrue);
      final list = decoded['events'] as List;
      expect(list.length, 2);
      expect((list.first as Map)['source'], EventSourceIds.network);
    });

    test('plaintext honors minimal preset (no source label)', () {
      final out = generateExport(events, kCopyPresets['minimal']!);
      // minimal: includeSource false → no "Network:" label, but title present.
      expect(out, contains('GET /pokemon'));
      expect(out, isNot(contains('Network:')));
    });

    test('mermaid emits a sequenceDiagram with API participant', () {
      final out = generateExport(events, kCopyPresets['mermaid']!);
      expect(out, startsWith('sequenceDiagram'));
      expect(out, contains('participant API'));
    });
  });

  group('UnifiedEventStore merge', () {
    late UnifiedEventEmit emit;

    setUp(() {
      unifiedEventStore.clearEvents();
      // Register a fake source and capture its emit callback.
      eventSourceRegistry.register(EventSourceAdapter(
        id: 'network', // maps to EventSourceIds.network via discovery id
        name: 'FakeNet',
        eventSources: const [EventSourceIds.network],
        subscribe: (e) {
          emit = e;
          return () {};
        },
      ));
      unifiedEventStore.subscribeToSource('network');
    });

    tearDown(() {
      unifiedEventStore.unsubscribeFromSource('network');
      unifiedEventStore.clearEvents();
    });

    test('newest-first ordering', () {
      emit(ev(id: 'u1', source: EventSourceIds.network, ts: 1, title: 'a', data: {'id': 'a'}));
      emit(ev(id: 'u2', source: EventSourceIds.network, ts: 2, title: 'b', data: {'id': 'b'}));
      final events = unifiedEventStore.getEvents();
      expect(events.map((e) => e.title), ['b', 'a']);
    });

    test('network response updates the same row in place (by data.id)', () {
      emit(ev(id: 'u1', source: EventSourceIds.network, ts: 1, title: 'pending', status: EventStatus.pending, data: {'id': 'req-1'}));
      expect(unifiedEventStore.getEventCount(), 1);
      // Same network id → in-place update, not a new row.
      emit(ev(id: 'u2', source: EventSourceIds.network, ts: 1, title: 'done', status: EventStatus.success, data: {'id': 'req-1'}));
      final events = unifiedEventStore.getEvents();
      expect(events.length, 1);
      expect(events.first.title, 'done');
      expect(events.first.id, 'u1'); // keeps the original unified id
    });
  });

  group('ignored-pattern filtering (shared network/events store)', () {
    // Mirrors EventsModal._isNetworkIgnored: a network event whose url matches
    // any IgnoredPattern is hidden from BOTH the events timeline and the network
    // tool (one shared store, both directions).
    bool isNetworkIgnored(UnifiedEvent e, List<IgnoredPattern> patterns) {
      if (e.source != EventSourceIds.network) return false;
      if (patterns.isEmpty) return false;
      final url = '${e.data['url'] ?? ''}';
      return patterns.any((p) => urlMatchesIgnoredPattern(url, p));
    }

    final events = [
      ev(id: 'n1', source: EventSourceIds.network, ts: 1, title: 'GET pokeapi', data: {'url': 'https://pokeapi.co/api/v2/pokemon/1'}),
      ev(id: 'n2', source: EventSourceIds.network, ts: 2, title: 'GET other', data: {'url': 'https://example.com/x'}),
      ev(id: 'r1', source: EventSourceIds.route, ts: 3, title: '/home', data: {'pathname': '/home'}),
    ];

    test('contains-mode pattern hides matching network events only', () {
      final patterns = [
        const IgnoredPattern('pokeapi.co', IgnoredPatternMatchMode.contains),
      ];
      final visible =
          events.where((e) => !isNetworkIgnored(e, patterns)).map((e) => e.id);
      // pokeapi network event gone; the other network + the route stay.
      expect(visible, ['n2', 'r1']);
    });

    test('un-ignoring restores the events (empty patterns → all visible)', () {
      final visible =
          events.where((e) => !isNetworkIgnored(e, const [])).map((e) => e.id);
      expect(visible, ['n1', 'n2', 'r1']);
    });

    test('a non-network event is never hidden by a network pattern', () {
      final patterns = [
        const IgnoredPattern('/home', IgnoredPatternMatchMode.exact),
      ];
      // The route event's url field is absent; only network sources are gated.
      expect(isNetworkIgnored(events[2], patterns), isFalse);
    });
  });

  group('exportEvents adapter action (MCP wire shape)', () {
    setUp(() => unifiedEventStore.clearEvents());

    test('returns {output, returned, totalAvailable, includedData, format}', () {
      final action = eventsSyncAdapter.actions['exportEvents']!;
      final result = action({'limit': 25}) as Map<String, Object?>;
      expect(result.keys, containsAll(
          ['output', 'returned', 'totalAvailable', 'includedData', 'format']));
      expect(result['format'], 'markdown');
      expect(result['includedData'], false);
    });

    test('preset + settings overrides flow through', () {
      final action = eventsSyncAdapter.actions['exportEvents']!;
      final result = action({
        'preset': 'json',
        'settings': {'includeEventData': true, 'format': 'json'},
      }) as Map<String, Object?>;
      expect(result['format'], 'json');
      expect(result['includedData'], true);
    });

    test('adapter is version 2 with the three RN actions', () {
      expect(eventsSyncAdapter.version, 2);
      expect(eventsSyncAdapter.actions.keys,
          containsAll(['clearEvents', 'setEnabledSources', 'exportEvents']));
    });
  });
}
