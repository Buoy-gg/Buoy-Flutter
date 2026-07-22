import 'package:flutter/material.dart';

import '../network_capture.dart';
import 'formatting.dart';
import 'macos_colors.dart';
import 'minute_ticker.dart';
import 'network_filter.dart';
import 'widgets/badges.dart';
import 'widgets/devtools_card.dart';

/// Port of NetworkEventItemCompact — one request row.
/// Layout: status-tinted left border; method badge + size indicators left;
/// URL (2 lines, monospace) middle; content-type badge + chevron right;
/// status/client badges pinned top-right; duration + relative time pinned
/// bottom-right.
class NetworkEventRow extends StatelessWidget {
  const NetworkEventRow({super.key, required this.event, required this.onTap});

  final NetworkCaptureEvent event;
  final ValueChanged<NetworkCaptureEvent> onTap;

  static Color statusColor(int? status, String? error) {
    if (error != null) return MacOSColors.error;
    if (status == null) return MacOSColors.warning;
    if (status >= 200 && status < 300) return MacOSColors.success;
    if (status >= 300 && status < 400) return MacOSColors.info;
    if (status >= 400) return MacOSColors.error;
    return MacOSColors.textMuted;
  }

  /// getContentTypeBadge — returns null for unknown types (no chip).
  static String? contentTypeBadge(Map<String, String> headers) {
    final contentType =
        (headers['content-type'] ?? headers['Content-Type'] ?? '')
            .toLowerCase();
    if (contentType.contains('json')) return 'JSON';
    if (contentType.contains('xml')) return 'XML';
    if (contentType.contains('html')) return 'HTML';
    if (contentType.contains('text')) return 'TEXT';
    if (contentType.contains('image')) return 'IMG';
    if (contentType.contains('video')) return 'VIDEO';
    if (contentType.contains('audio')) return 'AUDIO';
    if (contentType.contains('form')) return 'FORM';
    return null;
  }

  String get _displayUrl {
    final uri = Uri.tryParse(event.url);
    var displayUrl = (uri != null && uri.path.isNotEmpty)
        ? uri.path + (uri.hasQuery ? '?${uri.query}' : '')
        : event.url.replaceFirst(RegExp(r'^https?://[^/]+'), '');
    if (event.requestClient == 'graphql') {
      final operationName = event.operationName;
      if (operationName != null) {
        displayUrl = formatGraphQLDisplay(
          operationName,
          event.graphqlVariables,
        );
      } else {
        displayUrl = displayUrl.replaceFirst(
          RegExp(r'/graphql[^?]*'),
          '/graphql',
        );
      }
    } else if (event.operationName != null) {
      displayUrl = '$displayUrl\n(${event.operationName})';
    }
    return displayUrl;
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor(event.status, event.error);
    final contentType = contentTypeBadge(event.responseHeaders);

    return DevToolsCard(
      marginHorizontal: 8,
      borderLeftColor: color,
      onTap: () => onTap(event),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              // Left: method badge + sizes below.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MethodBadge(method: event.method),
                    _SizeIndicators(
                      requestSize: event.requestSize,
                      responseSize: event.responseSize,
                    ),
                  ],
                ),
              ),
              // Middle: URL, max 2 lines.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _displayUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      fontFamily: 'monospace',
                      color: MacOSColors.textPrimary,
                    ),
                  ),
                ),
              ),
              // Right: content-type badge + chevron.
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  if (contentType != null) ContentTypeBadge(type: contentType),
                  const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: MacOSColors.textMuted,
                  ),
                ],
              ),
            ],
          ),
          // Top-right: status + client badges (RN: absolute top 1 / right 1
          // inside the padded box → -11 relative to the padding).
          Positioned(
            top: -11,
            right: -11,
            child: Row(
              spacing: 4,
              children: [
                StatusIndicator(
                  status: event.status,
                  error: event.error,
                  statusColor: color,
                ),
                RequestClientBadge(client: event.requestClient),
              ],
            ),
          ),
          // Bottom-right: duration + relative time.
          Positioned(
            bottom: -8,
            right: -4,
            child: _BottomRightTime(
              timestamp: event.timestamp,
              duration: event.duration,
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeIndicators extends StatelessWidget {
  const _SizeIndicators({this.requestSize, this.responseSize});

  final int? requestSize;
  final int? responseSize;

  @override
  Widget build(BuildContext context) {
    if (requestSize == null && responseSize == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (requestSize != null && requestSize! > 0)
            _sizeItem(Icons.arrow_upward, MacOSColors.info, requestSize!),
          if (responseSize != null && responseSize! > 0)
            _sizeItem(Icons.arrow_downward, MacOSColors.success, responseSize!),
        ],
      ),
    );
  }

  Widget _sizeItem(IconData icon, Color color, int bytes) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Icon(icon, size: 8, color: color),
        Text(
          formatBytes(bytes),
          style: const TextStyle(
            fontSize: 8,
            fontFamily: 'monospace',
            color: MacOSColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Sole minute-tick consumer in the row (RN BottomRightTime) — only this
/// Text rebuilds when relative timestamps refresh.
class _BottomRightTime extends StatelessWidget {
  const _BottomRightTime({required this.timestamp, this.duration});

  final int timestamp;
  final int? duration;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MinuteTicker.instance.tick,
      builder: (context, _, _) {
        final relativeTime = formatRelativeTime(timestamp);
        return Text(
          duration != null
              ? '${formatDuration(duration)}  $relativeTime'
              : relativeTime,
          style: const TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            color: MacOSColors.textMuted,
          ),
        );
      },
    );
  }
}
