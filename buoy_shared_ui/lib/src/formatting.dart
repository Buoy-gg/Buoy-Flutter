import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'macos_colors.dart';

/// Ports of shared-ui's formatting utilities (dataFormatting.ts,
/// httpFormatting.ts, formatRelativeTime.ts) used by the network tool.

/// Ports packages/shared/src/utils/valueFormatting.ts `parseValue`: safely
/// JSON-decode a value that might be a JSON string, returning the original on
/// failure (or when it isn't a string). Used by storage/state tools so a
/// stringified blob renders as a tree in [DataViewer], not raw text.
Object? parseValue(Object? value) {
  if (value == null) return value;
  if (value is String) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }
  return value;
}

/// Default max bytes per value before it gets omitted from copy output (50 KB).
const int copyPayloadMaxBytes = 50000;

/// Ports packages/shared/src/utils/formatting/dataFormatting.ts
/// `truncatePayload`: if the serialized value exceeds [maxBytes], return a
/// human-readable placeholder instead of the value, so snapshot/copy output for
/// huge blobs (e.g. a react-query cache) stays readable. Non-serializable values
/// return `[omitted: could not serialize]`.
Object? truncatePayload(Object? value, [int maxBytes = copyPayloadMaxBytes]) {
  try {
    final serialized = jsonEncode(value);
    if (serialized.length > maxBytes) {
      return '[omitted: ${formatBytes(serialized.length)} — too large to copy]';
    }
    return value;
  } catch (_) {
    return '[omitted: could not serialize]';
  }
}

/// formatBytes: "1.5 KB", "2.3 MB" … (base 1024, one decimal).
String formatBytes(int? bytes) {
  if (bytes == null) return 'N/A';
  if (bytes == 0) return '0 B';
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (math.log(bytes) / math.log(1024)).floor().clamp(0, 4);
  final value = bytes / math.pow(1024, i);
  return '${value.toStringAsFixed(1)} ${sizes[i]}';
}

/// formatDuration: "500ms", "1.5s", "2m 30s", "1h 5m".
String formatDuration(int? ms) {
  if (ms == null) return 'N/A';
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  if (ms < 3600000) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
  }
  final hours = ms ~/ 3600000;
  final minutes = (ms % 3600000) ~/ 60000;
  return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
}

/// formatRelativeTime: "just now", "5s ago", "3m ago", "2h ago", "1d ago".
String formatRelativeTime(int timestampMs, [DateTime? now]) {
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final seconds = (nowMs - timestampMs) ~/ 1000;
  if (seconds <= 0) return 'just now';
  if (seconds < 60) return '${seconds}s ago';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h ago';
  return '${hours ~/ 24}d ago';
}

class HttpStatusInfo {
  const HttpStatusInfo(this.text, this.color, this.meaning);
  final String text;
  final Color color;
  final String meaning;
}

/// formatHttpStatus — status text + color + meaning. Colors follow the RN
/// helper, which reads gameUIColors (= the macOS theme's semantic colors).
HttpStatusInfo formatHttpStatus(int status) {
  if (status >= 100 && status < 200) {
    return HttpStatusInfo('$status', MacOSColors.info, 'Informational');
  }
  if (status >= 200 && status < 300) {
    const meanings = {
      200: 'OK',
      201: 'Created',
      202: 'Accepted',
      204: 'No Content',
      206: 'Partial Content',
    };
    return HttpStatusInfo(
      '$status',
      MacOSColors.success,
      meanings[status] ?? 'Success',
    );
  }
  if (status >= 300 && status < 400) {
    const meanings = {
      301: 'Moved Permanently',
      302: 'Found',
      303: 'See Other',
      304: 'Not Modified',
      307: 'Temporary Redirect',
      308: 'Permanent Redirect',
    };
    return HttpStatusInfo(
      '$status',
      MacOSColors.warning,
      meanings[status] ?? 'Redirect',
    );
  }
  if (status >= 400 && status < 500) {
    const meanings = {
      400: 'Bad Request',
      401: 'Unauthorized',
      402: 'Payment Required',
      403: 'Forbidden',
      404: 'Not Found',
      405: 'Method Not Allowed',
      408: 'Request Timeout',
      409: 'Conflict',
      410: 'Gone',
      422: 'Unprocessable Entity',
      429: 'Too Many Requests',
    };
    return HttpStatusInfo(
      '$status',
      MacOSColors.error,
      meanings[status] ?? 'Client Error',
    );
  }
  if (status >= 500) {
    const meanings = {
      500: 'Internal Server Error',
      501: 'Not Implemented',
      502: 'Bad Gateway',
      503: 'Service Unavailable',
      504: 'Gateway Timeout',
      505: 'HTTP Version Not Supported',
    };
    return HttpStatusInfo(
      '$status',
      MacOSColors.error,
      meanings[status] ?? 'Server Error',
    );
  }
  return HttpStatusInfo('$status', MacOSColors.textMuted, 'Unknown');
}
