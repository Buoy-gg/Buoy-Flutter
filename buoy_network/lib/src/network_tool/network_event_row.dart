import 'package:flutter/material.dart';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../network_capture.dart';
import 'network_filter.dart';

/// Port of NetworkEventItemCompact — one request row.
/// Layout: status-tinted left border; method badge + size indicators left;
/// URL (2 lines, monospace) middle; content-type badge + chevron right;
/// status/client badges pinned top-right; duration + relative time pinned
/// bottom-right.
class NetworkEventRow extends StatelessWidget {
  const NetworkEventRow({
    super.key,
    required this.event,
    required this.onTap,
    this.onLongPress,
    this.pinned = false,
    this.saved = false,
  });

  final NetworkCaptureEvent event;
  final ValueChanged<NetworkCaptureEvent> onTap;

  /// Long-press pins on the live list and UNSAVES on the Saved screen — each
  /// list affords the action that makes sense in it.
  final ValueChanged<NetworkCaptureEvent>? onLongPress;

  /// Pinned/saved markers. Deliberately GLYPHS, not buttons: this row renders
  /// hundreds of times, and a tappable target here would compete with the row
  /// itself. The toggles live in the detail header.
  final bool pinned;
  final bool saved;

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
      onLongPress: onLongPress == null ? null : () => onLongPress!(event),
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
                  const BuoyGlyph(
                    BuoyIcons.chevronRight,
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
                // The forged-response mark, immediately left of the status it
                // is responsible for. Without it a 500 you invented is
                // indistinguishable from a 500 your backend returned — which is
                // the whole hazard of this feature.
                if (event.override != null)
                  const BuoyGlyph(
                    BuoyIcons.flaskConical,
                    size: 12,
                    color: MacOSColors.warning,
                  ),
                if (pinned)
                  const BuoyGlyph(
                    BuoyIcons.pin,
                    size: 12,
                    color: MacOSColors.info,
                  ),
                if (saved)
                  const BuoyGlyph(
                    BuoyIcons.bookmark,
                    size: 12,
                    color: MacOSColors.debug,
                  ),
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
            _sizeItem(BuoyIcons.arrowUp, MacOSColors.info, requestSize!),
          if (responseSize != null && responseSize! > 0)
            _sizeItem(BuoyIcons.arrowDown, MacOSColors.success, responseSize!),
        ],
      ),
    );
  }

  Widget _sizeItem(LucideIcon icon, Color color, int bytes) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        BuoyGlyph(icon, size: 8, color: color),
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
