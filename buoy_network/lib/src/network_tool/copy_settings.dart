import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network_capture.dart';
import 'formatting.dart';

/// Port of NetworkCopySettingsView's CopySettings model + presets and
/// generateNetworkCopyText.ts. Persisted to the RN key
/// `@react_buoy_network_copy_options` with the same JSON field names.

enum CopyFormat { markdown, json, plaintext }

enum CopyFilterMode { all, failed, success }

@immutable
class CopySettings {
  const CopySettings({
    this.includeMethod = true,
    this.includeStatus = true,
    this.includeDuration = true,
    this.includeTimestamp = true,
    this.includeClient = true,
    this.includeSizes = true,
    this.includeErrors = true,
    this.includeRequestHeaders = true,
    this.includeResponseHeaders = true,
    this.includeRequestBody = true,
    this.includeResponseBody = true,
    this.bodySizeThreshold = 10,
    this.format = CopyFormat.markdown,
    this.filterMode = CopyFilterMode.all,
  });

  final bool includeMethod;
  final bool includeStatus;
  final bool includeDuration;
  final bool includeTimestamp;
  final bool includeClient;
  final bool includeSizes;
  final bool includeErrors;
  final bool includeRequestHeaders;
  final bool includeResponseHeaders;
  final bool includeRequestBody;
  final bool includeResponseBody;

  /// KB threshold; -1 = no limit (RN: 10 | 50 | 100 | -1).
  final int bodySizeThreshold;
  final CopyFormat format;
  final CopyFilterMode filterMode;

  CopySettings copyToggled(String key) {
    bool flip(String k, bool current) => key == k ? !current : current;
    return CopySettings(
      includeMethod: flip('includeMethod', includeMethod),
      includeStatus: flip('includeStatus', includeStatus),
      includeDuration: flip('includeDuration', includeDuration),
      includeTimestamp: flip('includeTimestamp', includeTimestamp),
      includeClient: flip('includeClient', includeClient),
      includeSizes: flip('includeSizes', includeSizes),
      includeErrors: flip('includeErrors', includeErrors),
      includeRequestHeaders:
          flip('includeRequestHeaders', includeRequestHeaders),
      includeResponseHeaders:
          flip('includeResponseHeaders', includeResponseHeaders),
      includeRequestBody: flip('includeRequestBody', includeRequestBody),
      includeResponseBody: flip('includeResponseBody', includeResponseBody),
      bodySizeThreshold: bodySizeThreshold,
      format: format,
      filterMode: filterMode,
    );
  }

  CopySettings copyWith({CopyFormat? format, CopyFilterMode? filterMode}) {
    return CopySettings(
      includeMethod: includeMethod,
      includeStatus: includeStatus,
      includeDuration: includeDuration,
      includeTimestamp: includeTimestamp,
      includeClient: includeClient,
      includeSizes: includeSizes,
      includeErrors: includeErrors,
      includeRequestHeaders: includeRequestHeaders,
      includeResponseHeaders: includeResponseHeaders,
      includeRequestBody: includeRequestBody,
      includeResponseBody: includeResponseBody,
      bodySizeThreshold: bodySizeThreshold,
      format: format ?? this.format,
      filterMode: filterMode ?? this.filterMode,
    );
  }

  bool boolValue(String key) => switch (key) {
    'includeMethod' => includeMethod,
    'includeStatus' => includeStatus,
    'includeDuration' => includeDuration,
    'includeTimestamp' => includeTimestamp,
    'includeClient' => includeClient,
    'includeSizes' => includeSizes,
    'includeErrors' => includeErrors,
    'includeRequestHeaders' => includeRequestHeaders,
    'includeResponseHeaders' => includeResponseHeaders,
    'includeRequestBody' => includeRequestBody,
    'includeResponseBody' => includeResponseBody,
    _ => false,
  };

  Map<String, Object?> toJson() => {
    'includeMethod': includeMethod,
    'includeStatus': includeStatus,
    'includeDuration': includeDuration,
    'includeTimestamp': includeTimestamp,
    'includeClient': includeClient,
    'includeSizes': includeSizes,
    'includeErrors': includeErrors,
    'includeRequestHeaders': includeRequestHeaders,
    'includeResponseHeaders': includeResponseHeaders,
    'includeRequestBody': includeRequestBody,
    'includeResponseBody': includeResponseBody,
    'bodySizeThreshold': bodySizeThreshold,
    'format': format.name,
    'filterMode': filterMode.name,
  };

  static CopySettings fromJson(Map<String, Object?> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    return CopySettings(
      includeMethod: flag('includeMethod', true),
      includeStatus: flag('includeStatus', true),
      includeDuration: flag('includeDuration', true),
      includeTimestamp: flag('includeTimestamp', true),
      includeClient: flag('includeClient', true),
      includeSizes: flag('includeSizes', true),
      includeErrors: flag('includeErrors', true),
      includeRequestHeaders: flag('includeRequestHeaders', true),
      includeResponseHeaders: flag('includeResponseHeaders', true),
      includeRequestBody: flag('includeRequestBody', true),
      includeResponseBody: flag('includeResponseBody', true),
      bodySizeThreshold:
          json['bodySizeThreshold'] is num ? (json['bodySizeThreshold'] as num).toInt() : 10,
      format: CopyFormat.values.asNameMap()[json['format']] ??
          CopyFormat.markdown,
      filterMode: CopyFilterMode.values.asNameMap()[json['filterMode']] ??
          CopyFilterMode.all,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CopySettings &&
      includeMethod == other.includeMethod &&
      includeStatus == other.includeStatus &&
      includeDuration == other.includeDuration &&
      includeTimestamp == other.includeTimestamp &&
      includeClient == other.includeClient &&
      includeSizes == other.includeSizes &&
      includeErrors == other.includeErrors &&
      includeRequestHeaders == other.includeRequestHeaders &&
      includeResponseHeaders == other.includeResponseHeaders &&
      includeRequestBody == other.includeRequestBody &&
      includeResponseBody == other.includeResponseBody &&
      bodySizeThreshold == other.bodySizeThreshold &&
      format == other.format &&
      filterMode == other.filterMode;

  @override
  int get hashCode => Object.hash(
    includeMethod,
    includeStatus,
    includeDuration,
    includeTimestamp,
    includeClient,
    includeSizes,
    includeErrors,
    includeRequestHeaders,
    includeResponseHeaders,
    includeRequestBody,
    includeResponseBody,
    bodySizeThreshold,
    format,
    filterMode,
  );
}

/// RN PRESET_CONFIGS — the copy tab's quick presets.
const copyPresets = <String, CopySettings>{
  'urls': CopySettings(
    includeStatus: false,
    includeDuration: false,
    includeTimestamp: false,
    includeClient: false,
    includeSizes: false,
    includeErrors: false,
    includeRequestHeaders: false,
    includeResponseHeaders: false,
    includeRequestBody: false,
    includeResponseBody: false,
    format: CopyFormat.plaintext,
  ),
  'llm': CopySettings(),
  'json': CopySettings(bodySizeThreshold: -1, format: CopyFormat.json),
  'full': CopySettings(bodySizeThreshold: -1),
};

/// Which preset matches the current settings, or null = "Custom".
String? detectActivePreset(CopySettings settings) {
  for (final entry in copyPresets.entries) {
    if (entry.value == settings) return entry.key;
  }
  return null;
}

const _copyOptionsKey = '@react_buoy_network_copy_options';

Future<CopySettings?> loadCopySettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_copyOptionsKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return CopySettings.fromJson(decoded.cast<String, Object?>());
    }
  } catch (_) {}
  return null;
}

Future<void> saveCopySettings(CopySettings settings) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_copyOptionsKey, jsonEncode(settings.toJson()));
  } catch (_) {}
}

// ── generateNetworkCopyText.ts ──────────────────────────────────────────

const _jsonEncoder = JsonEncoder.withIndent('  ');

String _pretty(Object? value) {
  try {
    return _jsonEncoder.convert(value);
  } catch (_) {
    return '$value';
  }
}

bool _shouldIncludePayload(Object? data, int bodySizeThresholdKb) {
  if (bodySizeThresholdKb == -1) return true;
  if (data == null) return true;
  try {
    return jsonEncode(data).length < bodySizeThresholdKb * 1024;
  } catch (_) {
    return false;
  }
}

String generateNetworkCopyText(
  List<NetworkCaptureEvent> events,
  CopySettings settings,
) {
  var eventsToUse = events;
  if (settings.filterMode == CopyFilterMode.failed) {
    eventsToUse = [
      for (final e in eventsToUse)
        if (e.error != null || (e.status != null && e.status! >= 400)) e,
    ];
  } else if (settings.filterMode == CopyFilterMode.success) {
    eventsToUse = [
      for (final e in eventsToUse)
        if (e.status != null && e.status! >= 200 && e.status! < 300) e,
    ];
  }

  if (eventsToUse.isEmpty) return 'No requests to copy';

  if (settings.format == CopyFormat.plaintext) {
    return eventsToUse.map((e) => '${e.method} ${e.url}').join('\n');
  }

  if (settings.format == CopyFormat.json) {
    final requests = [
      for (final event in eventsToUse)
        {
          if (settings.includeMethod) ...{
            'method': event.method,
            'url': event.url,
          },
          if (settings.includeStatus) ...{
            'status': event.status,
            'statusText': event.statusText,
          },
          if (settings.includeDuration) 'duration': event.duration,
          if (settings.includeTimestamp) 'timestamp': event.timestamp,
          if (settings.includeClient) 'requestClient': event.requestClient,
          if (settings.includeSizes) ...{
            'requestSize': event.requestSize,
            'responseSize': event.responseSize,
          },
          if (settings.includeErrors && event.error != null)
            'error': event.error,
          if (settings.includeRequestHeaders)
            'requestHeaders': event.requestHeaders,
          if (settings.includeResponseHeaders)
            'responseHeaders': event.responseHeaders,
          if (settings.includeRequestBody &&
              _shouldIncludePayload(
                event.requestData,
                settings.bodySizeThreshold,
              ))
            'requestData': event.requestData,
          if (settings.includeResponseBody &&
              _shouldIncludePayload(
                event.responseData,
                settings.bodySizeThreshold,
              ))
            'responseData': event.responseData,
        },
    ];
    return _pretty(requests);
  }

  // Markdown
  final buffer = StringBuffer(
    '# Network Requests (${eventsToUse.length} total)\n\n',
  );
  for (var index = 0; index < eventsToUse.length; index++) {
    final event = eventsToUse[index];
    buffer.write('# Request ${index + 1}\n\n');
    if (settings.includeMethod) {
      buffer.write('**Method:** ${event.method}\n');
      buffer.write('**URL:** ${event.url}\n');
    }
    if (settings.includeStatus) {
      final status = event.status?.toString() ?? 'Pending';
      final statusText =
          event.statusText != null ? ' (${event.statusText})' : '';
      buffer.write('**Status:** $status$statusText\n');
    }
    if (settings.includeClient) {
      buffer.write('**Client:** ${event.requestClient}\n');
    }
    if (settings.includeDuration && event.duration != null) {
      buffer.write('**Duration:** ${event.duration}ms\n');
    }
    if (settings.includeTimestamp) {
      final iso = DateTime.fromMillisecondsSinceEpoch(
        event.timestamp,
        isUtc: false,
      ).toUtc().toIso8601String();
      buffer.write('**Timestamp:** $iso\n');
    }
    if (settings.includeSizes) {
      buffer.write('**Request Size:** ${formatBytes(event.requestSize)}\n');
      buffer.write('**Response Size:** ${formatBytes(event.responseSize)}\n');
    }
    if (settings.includeErrors && event.error != null) {
      buffer.write('**Error:** ${event.error}\n');
    }
    if (settings.includeRequestHeaders && event.requestHeaders.isNotEmpty) {
      buffer.write(
        '\n## Request Headers\n```json\n${_pretty(event.requestHeaders)}\n```\n',
      );
    }
    if (settings.includeRequestBody) {
      buffer.write('\n## Request Data\n');
      if (_shouldIncludePayload(event.requestData, settings.bodySizeThreshold)) {
        buffer.write('```json\n${_pretty(event.requestData)}\n```\n');
      } else {
        final size = event.requestSize != null
            ? formatBytes(event.requestSize)
            : 'Unknown size';
        buffer.write(
          '_Payload omitted ($size). Exceeds ${settings.bodySizeThreshold}KB threshold._\n',
        );
      }
    }
    if (settings.includeResponseHeaders && event.responseHeaders.isNotEmpty) {
      buffer.write(
        '\n## Response Headers\n```json\n${_pretty(event.responseHeaders)}\n```\n',
      );
    }
    if (settings.includeResponseBody) {
      buffer.write('\n## Response Data\n');
      if (_shouldIncludePayload(
        event.responseData,
        settings.bodySizeThreshold,
      )) {
        buffer.write('```json\n${_pretty(event.responseData)}\n```\n');
      } else {
        final size = event.responseSize != null
            ? formatBytes(event.responseSize)
            : 'Unknown size';
        buffer.write(
          '_Payload omitted ($size). Exceeds ${settings.bodySizeThreshold}KB threshold._\n',
        );
      }
    }
    buffer.write('\n---\n\n');
  }
  return buffer.toString().trimRight();
}
