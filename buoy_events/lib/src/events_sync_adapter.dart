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

import 'copy_settings.dart';
import 'event_export_formatter.dart';
import 'unified_event_store.dart';

/// Version 2 — matches the RN `eventsSyncAdapter`.
final eventsSyncAdapter = ToolSyncAdapter(
  version: 2,
  getSnapshot: () => {
    'events': [for (final e in unifiedEventStore.getEvents()) e.data],
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
