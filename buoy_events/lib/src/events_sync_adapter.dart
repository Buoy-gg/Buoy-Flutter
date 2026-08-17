/// Ports packages/events/src/sync/eventsSyncAdapter.ts.
///
/// The device-side adapter a watching Buoy Desktop / the MCP server consume.
/// `getSnapshot` carries the events + available sources (the dashboard's own
/// discovery finds nothing — the tools live on the device). `exportEvents` is
/// what MCP `get_events` calls: it drives the same Copy-Settings formatter the
/// on-device Copy button uses, keeping heavy raw payloads on the device unless
/// `includeEventData` is set.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import 'copy_settings.dart';
import 'event_export_formatter.dart';
import 'unified_event_store.dart';

// ==========================================================================
// Snapshot compaction — keep the device→broker socket healthy.
//
// Each UnifiedEvent carries its source tool's full serialized payload (network
// bodies, provider value trees, storage values) for the on-device detail view.
// The sync snapshot re-sends ALL events on every change (throttled to 200ms),
// and measured RN sessions hit 4–6MB per push — a firehose that starves the
// broker and the device. Cap the per-event payload for the WIRE only; the
// on-device modal reads the store directly and keeps full detail.
// ==========================================================================

/// Max approx bytes of one event's payload on the wire.
const int maxSyncOriginalEventBytes = 16 * 1024;

Map<String, Object?> _truncatedMarker(int approxBytes, [String? note]) => {
  '__buoyTruncated': true,
  'approxBytes': approxBytes,
  'note':
      note ??
      'Payload (≥${(approxBytes / 1024).round()}KB approx) exceeds the '
          '${maxSyncOriginalEventBytes ~/ 1024}KB sync limit and stayed on the '
          'device. Open the tool on-device (or use the source tool\'s detail '
          'action) for the full payload.',
};

/// Marker replacing per-event state trees at the sync boundary.
const Map<String, Object?> _stateTreeOmitted = {
  '__buoyOmitted': 'state-tree',
  'note':
      'prevValue/nextValue stay on the device (open the Riverpod tool or the on-device Events detail).',
};

const Map<String, Object?> _networkBodyOmitted = {
  '__buoyOmitted': 'network-body',
  'note':
      'Request/response body stays on the device (open the Network tool or the on-device Events detail).',
};

const Map<String, Object?> _networkHeadersOmitted = {
  '__buoyOmitted': 'network-headers',
  'note':
      'Request/response headers stay on the device (open the Network tool or the on-device Events detail).',
};

const Map<String, Object?> _graphqlVarsOmitted = {
  '__buoyOmitted': 'graphql-variables',
  'note':
      'GraphQL variables stay on the device (open the Network tool or the on-device Events detail).',
};

const Map<String, Object?> _storageValueOmitted = {
  '__buoyOmitted': 'storage-value',
  'note':
      'Storage value stays on the device (open the Storage tool or the on-device Events detail).',
};

const Map<String, Object?> _routeParamsOmitted = {
  '__buoyOmitted': 'route-params',
  'note':
      'Navigation params stay on the device (open the Routes tool or the on-device Events detail).',
};

/// Markers are COPIED per field rather than shared. Not for correctness any
/// more — sharing a reference is handled properly below — but because a
/// repeated reference makes the size walk report `sawRepeat`, which costs a
/// full encodability check on an event we already know is fine.
Object? _omitIfHeavy(Object? value, Map<String, Object?> marker) {
  if (value == null) return null;
  return isOverWireBudget(value, maxSyncOriginalEventBytes)
      ? {...marker}
      : value;
}

/// Replace `key` in `map` only when it is present, so compaction never invents
/// a field the source tool did not emit.
void _omitField(
  Map<String, Object?> map,
  String key,
  Map<String, Object?> marker,
) {
  if (map.containsKey(key)) map[key] = _omitIfHeavy(map[key], marker);
}

/// Events are immutable once created, so compaction is computed once per event
/// and drops out of the cache when the store evicts it. `Expando` is the weak,
/// identity-keyed cache RN gets from `WeakMap`.
final Expando<Map<String, Object?>> _compactionCache =
    Expando<Map<String, Object?>>('buoyEventsCompaction');

/// Ports RN `compactEventForSync`, applied to the Flutter event's serialized
/// `data` map (which is what RN calls `originalEvent`).
Map<String, Object?> compactEventForSync(UnifiedEvent event) {
  final cached = _compactionCache[event];
  if (cached != null) return cached;

  var candidate = Map<String, Object?>.of(event.data);

  switch (event.source) {
    // Riverpod events carry whole provider value trees — per event. Never ship
    // (or even size-walk) those: drop them before estimating, so the rest of
    // the change (provider name, category, diff summary) still makes the wire.
    case EventSourceIds.riverpod:
    case EventSourceIds.redux:
    case EventSourceIds.zustand:
    case EventSourceIds.jotai:
      for (final key in const [
        'prevValue',
        'nextValue',
        'prevState',
        'nextState',
        'partial',
      ]) {
        if (candidate.containsKey(key)) candidate[key] = {..._stateTreeOmitted};
      }

    // A 20KB body blows the 16KB cap and would truncate the WHOLE payload —
    // method/url/status never reaching the dashboard. Strip the heavy fields
    // first so the light ones survive.
    case EventSourceIds.network:
      _omitField(candidate, 'requestData', _networkBodyOmitted);
      _omitField(candidate, 'responseData', _networkBodyOmitted);
      _omitField(candidate, 'graphqlVariables', _graphqlVarsOmitted);
      _omitField(candidate, 'requestHeaders', _networkHeadersOmitted);
      _omitField(candidate, 'responseHeaders', _networkHeadersOmitted);

    // StorageEvent.toJson nests the payload under `data`.
    case EventSourceIds.storageAsync:
    case EventSourceIds.storageMmkv:
      final data = candidate['data'];
      if (data is Map) {
        final inner = Map<String, Object?>.of(data.cast<String, Object?>());
        _omitField(inner, 'value', _storageValueOmitted);
        _omitField(inner, 'prevValue', _storageValueOmitted);
        candidate['data'] = inner;
      }

    // Route events embed navigation params. A fat object blows the cap and
    // would truncate the payload — pathname never reaching the dashboard.
    case EventSourceIds.route:
      _omitField(candidate, 'params', _routeParamsOmitted);
  }

  final walk = approxJsonSize(candidate, maxSyncOriginalEventBytes);
  Map<String, Object?> result = candidate;
  if (walk.bytes > maxSyncOriginalEventBytes) {
    result = _truncatedMarker(walk.bytes);
  } else if ((walk.sawRepeat || walk.sawUnencodable) &&
      !isJsonEncodable(candidate)) {
    // Only a CONFIRMED failure truncates. The walk dedupes by identity to stay
    // O(limit), so it cannot distinguish a cycle from ordinary structural
    // sharing — and `{user, currentUser}` pointing at one object is both
    // commonplace and perfectly encodable. Treating that as cyclic threw away
    // the whole event, type and title included, for a payload that was always
    // safe to send.
    result = _truncatedMarker(
      -1,
      'Payload is not JSON-serializable (cyclic or unencodable) and stayed on '
      'the device.',
    );
  }

  _compactionCache[event] = result;
  return result;
}

/// Version 2 — matches the RN `eventsSyncAdapter`.
final eventsSyncAdapter = ToolSyncAdapter(
  version: 2,
  getSnapshot: () => {
    'events': [
      for (final e in unifiedEventStore.getEvents()) compactEventForSync(e),
    ],
    'availableSources': unifiedEventStore.getAvailableEventSources().toList(),
  },
  subscribe: (onChange) {
    // Default to all sources until the dashboard narrows via setEnabledSources.
    unifiedEventStore.ensureRemoteSourcesDefault();
    final unsub = unifiedEventStore.subscribe((_) => onChange());
    return () {
      unsub();
      unifiedEventStore.clearRemoteSources();
    };
  },
  actions: {
    'clearEvents': (_) {
      unifiedEventStore.clearEvents();
      return null;
    },
    'setEnabledSources': (params) {
      final sources = _stringList((params as Map?)?['sources']);
      unifiedEventStore.setRemoteEnabledSources(sources);
      return {'enabledSources': sources};
    },
    'exportEvents': (params) => _exportEvents(params),
  },
);

/// Ports the `exportEvents` action. Returns `{output, returned, totalAvailable,
/// includedData, format}` — the shape MCP `get_events` expects.
Map<String, Object?> _exportEvents(Object? params) {
  final p = (params as Map?) ?? const {};

  // Base = named preset (llm/errors/…) or the compact default.
  final presetName = p['preset'];
  var settings = (presetName is String && kCopyPresets.containsKey(presetName))
      ? kCopyPresets[presetName]!
      : kDefaultCopySettings;

  // Merge the caller's Copy-Settings overrides (filterSources/filterMode/…).
  final overrides = p['settings'];
  if (overrides is Map) {
    settings = settings.applyOverrides(
      {for (final e in overrides.entries) '${e.key}': e.value},
    );
  }

  final all = unifiedEventStore.getEvents(); // newest-first, capped
  final limitRaw = p['limit'];
  final limit = (limitRaw is int && limitRaw > 0) ? limitRaw : all.length;
  final events = all.length > limit ? all.sublist(0, limit) : all;

  return {
    'output': generateExport(events, settings),
    'returned': events.length,
    'totalAvailable': all.length,
    'includedData': settings.includeEventData,
    'format': _formatName(settings.format),
  };
}

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

String _formatName(ExportFormat format) => switch (format) {
      ExportFormat.markdown => 'markdown',
      ExportFormat.json => 'json',
      ExportFormat.plaintext => 'plaintext',
      ExportFormat.mermaid => 'mermaid',
    };
