/// Ports packages/events/src/utils/eventExportFormatter.ts.
///
/// Generates the markdown / json / plaintext / mermaid exports the on-device
/// Copy button and — critically — MCP `get_events` (via the `exportEvents`
/// action) produce. Operates on [UnifiedEvent.data] (the serialized `toJson`
/// map — RN's `originalEvent` plain-object shape).
library;

import 'dart:convert';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import 'copy_settings.dart';

const _statusIcons = {
  'success': '✅',
  'pending': '⏳',
  'error': '❌',
  'neutral': '➖',
};

const _statusIconsAscii = {
  'success': '[OK]',
  'pending': '[...]',
  'error': '[ERR]',
  'neutral': '[-]',
};

const _sourceLabels = {
  'storage-async': 'Storage',
  'storage-mmkv': 'MMKV',
  'redux': 'Redux',
  'network': 'Network',
  'react-query': 'Query',
  'react-query-query': 'Query',
  'react-query-mutation': 'Mutation',
  'route': 'Route',
  'zustand': 'Zustand',
  'jotai': 'Jotai',
  'render': 'Render',
};

String _statusKey(EventStatus s) => switch (s) {
      EventStatus.success => 'success',
      EventStatus.error => 'error',
      EventStatus.pending => 'pending',
      EventStatus.neutral => 'neutral',
    };

String _sourceLabel(String source) => _sourceLabels[source] ?? source;

// ── Summary ──────────────────────────────────────────────────────────────────

/// Ports `ExportSummary`.
class ExportSummary {
  ExportSummary();
  int totalEvents = 0;
  int success = 0;
  int pending = 0;
  int error = 0;
  int neutral = 0;
  int durationMs = 0;
  final Set<String> sources = {};
}

/// Ports `getExportSummary`.
ExportSummary getExportSummary(List<UnifiedEvent> events) {
  final summary = ExportSummary()..totalEvents = events.length;
  if (events.isEmpty) return summary;

  var minTs = 1 << 62;
  var maxTs = -(1 << 62);
  for (final e in events) {
    switch (e.status) {
      case EventStatus.success:
        summary.success++;
      case EventStatus.error:
        summary.error++;
      case EventStatus.pending:
        summary.pending++;
      case EventStatus.neutral:
        summary.neutral++;
    }
    summary.sources.add(e.source);
    if (e.timestamp < minTs) minTs = e.timestamp;
    if (e.timestamp > maxTs) maxTs = e.timestamp;
  }
  summary.durationMs = maxTs - minTs;
  return summary;
}

/// Ports `filterEvents`.
List<UnifiedEvent> filterEvents(
  List<UnifiedEvent> events,
  EventsCopySettings settings,
) {
  var filtered = [...events];
  if (settings.filterMode != ExportFilterMode.all) {
    filtered = filtered.where((e) {
      switch (settings.filterMode) {
        case ExportFilterMode.errors:
          return e.status == EventStatus.error;
        case ExportFilterMode.success:
          return e.status == EventStatus.success;
        case ExportFilterMode.pending:
          return e.status == EventStatus.pending;
        case ExportFilterMode.all:
          return true;
      }
    }).toList();
  }
  if (settings.filterSources.isNotEmpty) {
    final set = settings.filterSources.toSet();
    filtered = filtered.where((e) => set.contains(e.source)).toList();
  }
  return filtered;
}

// ── Smart parsing / stripping ────────────────────────────────────────────────

Object? _tryParseJson(Object? value) {
  if (value is! String) return value;
  final trimmed = value.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return value;
  try {
    return jsonDecode(value);
  } catch (_) {
    return value;
  }
}

Object? _deepParseJsonStrings(Object? obj) {
  if (obj == null) return obj;
  if (obj is String) return _tryParseJson(obj);
  if (obj is List) return obj.map(_deepParseJsonStrings).toList();
  if (obj is Map) {
    return {
      for (final entry in obj.entries)
        '${entry.key}': _deepParseJsonStrings(entry.value),
    };
  }
  return obj;
}

const _verboseFields = {
  'image', 'imageUrl', 'imageURL', 'image_url', 'thumbnail', 'thumbnailUrl',
  'thumbnail_url', 'icon', 'iconUrl', 'avatar', 'avatarUrl', 'photo',
  'photoUrl', 'picture', 'pictureUrl', 'description', 'desc',
  'longDescription', 'shortDescription', 'meta_description',
};

bool _isImageUrl(String value) {
  if (!value.startsWith('http')) return false;
  final lower = value.toLowerCase();
  return lower.contains('/photo') ||
      lower.contains('/image') ||
      lower.contains('unsplash.com') ||
      lower.contains('cloudinary.com') ||
      lower.contains('imgur.com') ||
      RegExp(r'\.(jpg|jpeg|png|gif|webp|svg|bmp)(\?|$)', caseSensitive: false)
          .hasMatch(value);
}

Object? _stripVerbose(Object? obj) {
  if (obj == null) return obj;
  if (obj is List) return obj.map(_stripVerbose).toList();
  if (obj is Map) {
    final result = <String, Object?>{};
    for (final entry in obj.entries) {
      final key = '${entry.key}';
      if (_verboseFields.contains(key)) continue;
      final value = entry.value;
      if (value is String && _isImageUrl(value)) continue;
      result[key] = _stripVerbose(value);
    }
    return result;
  }
  return obj;
}

/// Ports `formatEventData` (storage + generic branches; redux/react-query are
/// not Flutter sources so their special-casing is unreachable and omitted).
Object? _formatEventData(UnifiedEvent event, EventsCopySettings settings) {
  final data = event.data;
  Object? result;

  if (event.source == 'storage-async' || event.source == 'storage-mmkv') {
    result = _formatStorageData(data, settings);
  } else if (settings.smartJsonParsing) {
    result = _deepParseJsonStrings(data);
  } else {
    result = data;
  }

  if (settings.stripVerboseFields && result != null) {
    result = _stripVerbose(result);
  }
  return result;
}

Map<String, Object?> _formatStorageData(
  Map<String, Object?> data,
  EventsCopySettings settings,
) {
  final result = <String, Object?>{};
  if (data['action'] != null) result['action'] = data['action'];
  if (data['storageType'] != null) result['storageType'] = data['storageType'];
  if (data['timestamp'] != null) result['timestamp'] = data['timestamp'];

  final inner = data['data'];
  if (inner is Map) {
    final innerData = <String, Object?>{
      for (final e in inner.entries) '${e.key}': e.value,
    };
    if (settings.smartJsonParsing) {
      if (innerData.containsKey('value')) {
        innerData['value'] = _tryParseJson(innerData['value']);
      }
      if (innerData.containsKey('prevValue')) {
        innerData['prevValue'] = _tryParseJson(innerData['prevValue']);
      }
    }
    result['data'] = innerData;
  }
  return result;
}

// ── Storage diff summary ─────────────────────────────────────────────────────

String? _itemIdentifier(Object? item) {
  if (item is String) return item;
  if (item is num) return '$item';
  if (item is Map) {
    if (item['name'] is String) return item['name'] as String;
    if (item['id'] != null) return '${item['id']}';
    if (item['key'] is String) return item['key'] as String;
  }
  return null;
}

/// Ports `generateStorageDiffSummary` (the branches that matter for arrays /
/// objects / create / delete).
String? _generateStorageDiffSummary(Object? prevRaw, Object? newRaw) {
  final prev = prevRaw is String ? _tryParseJson(prevRaw) : prevRaw;
  final next = newRaw is String ? _tryParseJson(newRaw) : newRaw;

  if (prev == null && next != null) return 'Created';
  if (prev != null && next == null) return 'Deleted';

  if (prev is List && next is List) {
    final prevLen = prev.length;
    final nextLen = next.length;
    final prevIds = prev.map(_itemIdentifier).whereType<String>().toList();
    final nextIds = next.map(_itemIdentifier).whereType<String>().toList();

    if (prevLen == nextLen && prevLen > 0) {
      final nextSet = nextIds.toSet();
      final kept = prevIds.where(nextSet.contains).toList();
      if (kept.isEmpty && prevIds.isNotEmpty && nextIds.isNotEmpty) {
        return '⚠️ Replaced: [${prevIds.join(", ")}] → [${nextIds.join(", ")}]';
      }
      if (kept.length < prevLen) {
        final removed = prevIds.where((id) => !nextSet.contains(id));
        final prevSet = prevIds.toSet();
        final added = nextIds.where((id) => !prevSet.contains(id));
        return 'Changed: -${removed.join(", ")} +${added.join(", ")}';
      }
    }
    if (prevLen == 0 && nextLen > 0) {
      if (nextIds.isNotEmpty) return 'Added: [${nextIds.join(", ")}]';
      return 'Added $nextLen item${nextLen > 1 ? "s" : ""}';
    }
    if (prevLen > 0 && nextLen == 0) {
      if (prevIds.isNotEmpty) return 'Removed all: [${prevIds.join(", ")}]';
      return 'Removed all $prevLen item${prevLen > 1 ? "s" : ""}';
    }
    if (nextLen > prevLen) {
      final prevSet = prevIds.toSet();
      final added = nextIds.where((id) => !prevSet.contains(id)).toList();
      if (added.isNotEmpty) {
        return 'Added: [${added.join(", ")}] ($prevLen → $nextLen)';
      }
      return 'Added ${nextLen - prevLen} item${nextLen - prevLen > 1 ? "s" : ""} ($prevLen → $nextLen)';
    }
    if (nextLen < prevLen) {
      final nextSet = nextIds.toSet();
      final removed = prevIds.where((id) => !nextSet.contains(id)).toList();
      if (removed.isNotEmpty) {
        return 'Removed: [${removed.join(", ")}] ($prevLen → $nextLen)';
      }
      return 'Removed ${prevLen - nextLen} item${prevLen - nextLen > 1 ? "s" : ""} ($prevLen → $nextLen)';
    }
    return 'Updated ($nextLen item${nextLen > 1 ? "s" : ""})';
  }

  if (prev is Map && next is Map) {
    final prevKeys = prev.keys.map((k) => '$k').toSet();
    final nextKeys = next.keys.map((k) => '$k').toSet();
    final added = nextKeys.difference(prevKeys).toList();
    final removed = prevKeys.difference(nextKeys).toList();
    if (added.isNotEmpty && removed.isNotEmpty) {
      return '+${added.length} -${removed.length} keys';
    }
    if (added.isNotEmpty) return 'Added: ${added.join(", ")}';
    if (removed.isNotEmpty) return 'Removed: ${removed.join(", ")}';
    return 'Updated';
  }
  return null;
}

// ── Timestamps / truncation ──────────────────────────────────────────────────

String _formatRelativeMs(int ms) {
  if (ms < 1000) return '+${ms}ms';
  if (ms < 60000) return '+${(ms / 1000).toStringAsFixed(1)}s';
  return '+${(ms / 60000).toStringAsFixed(1)}m';
}

String _formatAbsolute(int timestamp) =>
    DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc().toIso8601String();

String _formatTimestamp(int timestamp, int base, TimestampFormat format) {
  final relative = _formatRelativeMs(timestamp - base);
  final absolute = _formatAbsolute(timestamp);
  switch (format) {
    case TimestampFormat.relative:
      return relative;
    case TimestampFormat.absolute:
      return absolute;
    case TimestampFormat.both:
      return '$relative ($absolute)';
  }
}

const _indentEncoder = JsonEncoder.withIndent('  ');

({Object? data, bool truncated}) _truncateData(Object? data, int thresholdKb) {
  if (thresholdKb == -1) return (data: data, truncated: false);
  try {
    final json = jsonEncode(data);
    final sizeKb = json.length / 1024;
    if (sizeKb <= thresholdKb) return (data: data, truncated: false);
    return (
      data:
          '[Data truncated - ${sizeKb.toStringAsFixed(1)}KB exceeds ${thresholdKb}KB limit]',
      truncated: true,
    );
  } catch (_) {
    return (data: '[Unable to serialize data]', truncated: true);
  }
}

// ── Markdown ─────────────────────────────────────────────────────────────────

/// Ports `generateMarkdownExport`.
String generateMarkdownExport(
  List<UnifiedEvent> events,
  EventsCopySettings settings,
) {
  final filtered = filterEvents(events, settings);
  if (filtered.isEmpty) return 'No events to export.';

  final sorted = [...filtered]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final base = sorted.first.timestamp;
  final summary = getExportSummary(sorted);

  final lines = <String>['## Event Flow'];

  if (settings.includeSummaryHeader || settings.includeTotalDuration) {
    final parts = <String>[];
    if (settings.includeTotalDuration) {
      parts.add(
          '**Duration:** ${_formatRelativeMs(summary.durationMs).replaceFirst("+", "")}');
    }
    parts.add('**Events:** ${summary.totalEvents}');
    if (settings.includeSummaryHeader) {
      final statusParts = <String>[];
      if (summary.success > 0) {
        statusParts.add('${summary.success} ${_statusIcons["success"]}');
      }
      if (summary.pending > 0) {
        statusParts.add('${summary.pending} ${_statusIcons["pending"]}');
      }
      if (summary.error > 0) {
        statusParts.add('${summary.error} ${_statusIcons["error"]}');
      }
      if (summary.neutral > 0) {
        statusParts.add('${summary.neutral} ${_statusIcons["neutral"]}');
      }
      if (statusParts.isNotEmpty) {
        parts.add('**Status:** ${statusParts.join(" ")}');
      }
    }
    lines.add(parts.join(' | '));
  }

  lines.add('');
  lines.add('### Timeline');
  lines.add('');

  if (settings.compactMode) {
    for (var i = 0; i < sorted.length; i++) {
      lines.add('${i + 1}. ${_formatCompactEvent(sorted[i], base, settings)}');
    }
    return lines.join('\n');
  }

  for (var i = 0; i < sorted.length; i++) {
    final event = sorted[i];
    final parts = <String>[];
    final ts = _formatTimestamp(event.timestamp, base, settings.timestampFormat);
    parts.add('${i + 1}. `$ts`');
    if (settings.includeStatus) parts.add(_statusIcons[_statusKey(event.status)]!);
    if (settings.includeSource) parts.add('**${_sourceLabel(event.source)}**');
    if (settings.includeTitle) parts.add(event.title);
    if (settings.includeCorrelation &&
        event.correlationId != null &&
        event.sequenceInGroup != null) {
      parts.add('(${event.sequenceInGroup})');
    }
    lines.add(parts.join(' '));

    if (settings.includeSubtitle && event.subtitle.isNotEmpty) {
      lines.add('   └─ ${event.subtitle}');
    }

    if (settings.showStorageDiff &&
        !settings.includeEventData &&
        (event.source == 'storage-async' || event.source == 'storage-mmkv')) {
      lines.addAll(_storageDiffBlock(event));
    }

    if (settings.includeEventData) {
      final formatted = _formatEventData(event, settings);
      final t = _truncateData(formatted, settings.dataSizeThreshold);
      if (t.truncated) {
        lines.add('   └─ ${t.data}');
      } else {
        if (settings.showStorageDiff &&
            (event.source == 'storage-async' ||
                event.source == 'storage-mmkv')) {
          final inner = event.data['data'];
          if (inner is Map) {
            final diff =
                _generateStorageDiffSummary(inner['prevValue'], inner['value']);
            if (diff != null) lines.add('   **Change:** $diff');
          }
        }
        lines.add('   ```json');
        lines.add(
            '   ${_indentEncoder.convert(t.data).split("\n").join("\n   ")}');
        lines.add('   ```');
      }
    }

    lines.add('');
  }

  final errors = sorted.where((e) => e.status == EventStatus.error).toList();
  if (errors.isNotEmpty && settings.includeEventData) {
    lines.add('---');
    lines.add('');
    lines.add('### Errors');
    lines.add('');
    for (final error in errors) {
      final ts =
          _formatTimestamp(error.timestamp, base, settings.timestampFormat);
      lines.add('**${error.title}** ($ts)');
      final formatted = _formatEventData(error, settings);
      final t = _truncateData(formatted, settings.dataSizeThreshold);
      if (!t.truncated) {
        lines.add('```json');
        lines.add(_indentEncoder.convert(t.data));
        lines.add('```');
      }
      lines.add('');
    }
  }

  return lines.join('\n');
}

List<String> _storageDiffBlock(UnifiedEvent event) {
  final lines = <String>[];
  final inner = event.data['data'];
  if (inner is! Map) return lines;
  final diff = _generateStorageDiffSummary(inner['prevValue'], inner['value']);
  if (diff != null) lines.add('   **Change:** $diff');
  return lines;
}

String _formatCompactEvent(
  UnifiedEvent event,
  int base,
  EventsCopySettings settings,
) {
  final parts = <String>[];
  parts.add('`${_formatTimestamp(event.timestamp, base, settings.timestampFormat)}`');
  if (settings.includeStatus) parts.add(_statusIcons[_statusKey(event.status)]!);
  if (settings.includeSource) parts.add('**${_sourceLabel(event.source)}**');
  if (settings.includeTitle) parts.add(event.title);
  if (settings.showStorageDiff &&
      (event.source == 'storage-async' || event.source == 'storage-mmkv')) {
    final inner = event.data['data'];
    if (inner is Map) {
      final diff = _generateStorageDiffSummary(inner['prevValue'], inner['value']);
      if (diff != null) parts.add('→ $diff');
    }
  }
  if (settings.includeSubtitle && event.subtitle.isNotEmpty) {
    parts.add('- ${event.subtitle}');
  }
  return parts.join(' ');
}

// ── JSON ─────────────────────────────────────────────────────────────────────

/// Ports `generateJsonExport`.
String generateJsonExport(
  List<UnifiedEvent> events,
  EventsCopySettings settings,
) {
  final filtered = filterEvents(events, settings);
  if (filtered.isEmpty) return '[]';

  final sorted = [...filtered]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final base = sorted.first.timestamp;
  final summary = getExportSummary(sorted);

  final exportData = <String, Object?>{
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
  };

  if (settings.includeSummaryHeader) {
    exportData['summary'] = {
      'totalEvents': summary.totalEvents,
      'success': summary.success,
      'pending': summary.pending,
      'error': summary.error,
      'neutral': summary.neutral,
      'durationMs': summary.durationMs,
      'sources': summary.sources.toList(),
    };
  }

  exportData['events'] = [
    for (final event in sorted)
      () {
        final eventData = <String, Object?>{};
        eventData['timestamp'] = _formatAbsolute(event.timestamp);
        if (settings.timestampFormat == TimestampFormat.relative ||
            settings.timestampFormat == TimestampFormat.both) {
          eventData['relativeMs'] = event.timestamp - base;
        }
        if (settings.includeSource) eventData['source'] = event.source;
        if (settings.includeStatus) {
          eventData['status'] = _statusKey(event.status);
        }
        if (settings.includeTitle) eventData['title'] = event.title;
        if (settings.includeSubtitle) eventData['subtitle'] = event.subtitle;
        if (settings.includeCorrelation && event.correlationId != null) {
          eventData['correlationId'] = event.correlationId;
          eventData['sequenceInGroup'] = event.sequenceInGroup;
        }
        if (settings.includeEventData) {
          final formatted = _formatEventData(event, settings);
          final t = _truncateData(formatted, settings.dataSizeThreshold);
          eventData['data'] = t.data;
          if (t.truncated) eventData['dataTruncated'] = true;
          if (settings.showStorageDiff &&
              (event.source == 'storage-async' ||
                  event.source == 'storage-mmkv')) {
            final inner = event.data['data'];
            if (inner is Map) {
              final diff =
                  _generateStorageDiffSummary(inner['prevValue'], inner['value']);
              if (diff != null) eventData['changeSummary'] = diff;
            }
          }
        }
        return eventData;
      }(),
  ];

  return _indentEncoder.convert(exportData);
}

// ── Plaintext ────────────────────────────────────────────────────────────────

/// Ports `generatePlaintextExport`.
String generatePlaintextExport(
  List<UnifiedEvent> events,
  EventsCopySettings settings,
) {
  final filtered = filterEvents(events, settings);
  if (filtered.isEmpty) return 'No events to export.';

  final sorted = [...filtered]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final base = sorted.first.timestamp;
  final summary = getExportSummary(sorted);

  final lines = <String>[];
  if (settings.includeSummaryHeader || settings.includeTotalDuration) {
    var header = 'Event Flow (${summary.totalEvents} events';
    if (settings.includeTotalDuration) {
      header += ', ${_formatRelativeMs(summary.durationMs).replaceFirst("+", "")}';
    }
    header += ')';
    lines.add(header);
    if (settings.includeSummaryHeader) {
      final statusParts = <String>[];
      if (summary.success > 0) statusParts.add('${summary.success} success');
      if (summary.pending > 0) statusParts.add('${summary.pending} pending');
      if (summary.error > 0) statusParts.add('${summary.error} error');
      if (summary.neutral > 0) statusParts.add('${summary.neutral} neutral');
      if (statusParts.isNotEmpty) lines.add(statusParts.join(', '));
    }
    lines.add('');
  }

  for (final event in sorted) {
    final parts = <String>[];
    final ts = _formatTimestamp(event.timestamp, base, settings.timestampFormat);
    parts.add(ts.padRight(12));
    if (settings.includeStatus) {
      parts.add(_statusIconsAscii[_statusKey(event.status)]!);
    }
    if (settings.includeSource) parts.add('${_sourceLabel(event.source)}:');
    if (settings.includeTitle) parts.add(event.title);
    if (settings.showStorageDiff &&
        (event.source == 'storage-async' || event.source == 'storage-mmkv')) {
      final inner = event.data['data'];
      if (inner is Map) {
        final diff =
            _generateStorageDiffSummary(inner['prevValue'], inner['value']);
        if (diff != null) parts.add('-> $diff');
      }
    }
    if (settings.includeSubtitle && event.subtitle.isNotEmpty) {
      parts.add('- ${event.subtitle}');
    }
    lines.add(parts.join(' '));

    if (settings.includeEventData) {
      final formatted = _formatEventData(event, settings);
      final t = _truncateData(formatted, settings.dataSizeThreshold);
      if (t.truncated) {
        lines.add('  ${t.data}');
      } else {
        lines.add('  Data: ${jsonEncode(t.data)}');
      }
    }
  }

  return lines.join('\n');
}

// ── Mermaid ──────────────────────────────────────────────────────────────────

String _formatMermaidDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${(ms / 60000).toStringAsFixed(1)}m';
}

String _escapeMermaid(String text) => text
    .replaceAll(RegExp(r'[#;:]'), ' ')
    .replaceAll(RegExp(r'[\n\r]'), ' ')
    .replaceAll('"', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _humanRoute(String pathname) {
  if (pathname == '/' || pathname.isEmpty) return 'Home';
  final segments = pathname.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return 'Home';
  if (segments.length == 1) {
    final name = segments[0][0].toUpperCase() + segments[0].substring(1);
    return '$name List';
  }
  final entity = segments.last;
  if (RegExp(r'^\d+$').hasMatch(entity)) {
    final resource = segments[0][0].toUpperCase() + segments[0].substring(1);
    return '$resource #$entity';
  }
  return '${entity[0].toUpperCase()}${entity.substring(1)} Details';
}

/// Ports `generateMermaidExport` (route/network/storage participants — the
/// Flutter sources; other RN participants degrade to the App actor).
String generateMermaidExport(
  List<UnifiedEvent> events,
  EventsCopySettings settings,
) {
  final filtered = filterEvents(events, settings);
  if (filtered.isEmpty) {
    return 'sequenceDiagram\n    participant U as \u{1F464} User\n    participant App as \u{1F4F1} App\n    Note over U,App: No events captured';
  }

  final sorted = [...filtered]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final lines = <String>['sequenceDiagram', '    autonumber', ''];
  // Participants (only those in use, plus the always-present User/App).
  final inUse = sorted.map((e) => e.source).toSet();
  lines.add('    participant U as \u{1F464} User');
  lines.add('    participant App as \u{1F4F1} App');
  if (inUse.contains('storage-async')) {
    lines.add('    participant Async as \u{1F4BE} AsyncStorage');
  }
  if (inUse.contains('storage-mmkv')) {
    lines.add('    participant MMKV as ⚡ MMKV');
  }
  if (inUse.contains('network')) {
    lines.add('    participant API as \u{1F310} API');
  }
  lines.add('');

  for (final event in sorted) {
    switch (event.source) {
      case 'route':
        final data = event.data;
        final pathname = '${data['pathname'] ?? event.title}';
        final prev = data['previousPathname'] as String?;
        final route = _humanRoute(pathname);
        if (prev != null) {
          lines.add('    U->>App: ${_humanRoute(prev)} → $route');
          final since = data['timeSincePrevious'];
          if (since is int && since > 0) {
            lines.add(
                '    Note right of App: ${_formatMermaidDuration(since)} on ${_humanRoute(prev)}');
          }
        } else {
          lines.add('    U->>App: Open $route');
        }
      case 'network':
        final data = event.data;
        final method = '${data['method'] ?? 'GET'}';
        final path = '${data['path'] ?? data['url'] ?? ''}';
        lines.add('    App->>+API: $method $path');
        if (event.status == EventStatus.error) {
          final status = data['status'];
          lines.add('    API--x-App: ${status != null ? "$status Error" : "Failed"}');
        } else {
          lines.add('    API-->>-App: ✓ Success');
        }
        final duration = data['duration'];
        if (duration is int) {
          lines.add('    Note right of API: ${_formatMermaidDuration(duration)}');
        }
      case 'storage-async':
      case 'storage-mmkv':
        final storeId = event.source == 'storage-mmkv' ? 'MMKV' : 'Async';
        lines.add('    App->>$storeId: ${_escapeMermaid(event.title)}');
      default:
        lines.add('    App->>App: ${_escapeMermaid(event.title)}');
    }
  }

  return lines.join('\n');
}

// ── Dispatch ─────────────────────────────────────────────────────────────────

/// Ports `generateExport`.
String generateExport(List<UnifiedEvent> events, EventsCopySettings settings) {
  switch (settings.format) {
    case ExportFormat.markdown:
      return generateMarkdownExport(events, settings);
    case ExportFormat.json:
      return generateJsonExport(events, settings);
    case ExportFormat.plaintext:
      return generatePlaintextExport(events, settings);
    case ExportFormat.mermaid:
      return generateMermaidExport(events, settings);
  }
}
