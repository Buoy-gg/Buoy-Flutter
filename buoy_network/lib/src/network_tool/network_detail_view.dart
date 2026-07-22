import 'dart:convert';

import 'package:flutter/material.dart';

import '../network_capture.dart';
import 'package:buoy_core/buoy_core.dart';
import 'formatting.dart';
import 'ignored_patterns.dart';
import 'macos_colors.dart';
import 'network_filter.dart';
import 'widgets/copy_button.dart';
import 'widgets/data_viewer.dart';

/// Port of NetworkEventDetailView — the request inspector: HTTP header row,
/// Sentry-style URL breakdown, timing card, collapsible header/body sections
/// (DataViewer trees), and the Filter Options section (ignore domain / URL
/// pattern toggles into the shared ignored-patterns store).
///
/// The desktop body-resolver is a no-op on device (bodies are inline in the
/// store), so it isn't ported.
class NetworkDetailView extends StatelessWidget {
  const NetworkDetailView({super.key, required this.event});

  final NetworkCaptureEvent event;

  String _fullRequestDetails() {
    const encoder = JsonEncoder.withIndent('  ');
    String pretty(Object? value) {
      try {
        return encoder.convert(value);
      } catch (_) {
        return '$value';
      }
    }

    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      event.timestamp,
    ).toUtc().toIso8601String();
    final duration = event.duration != null ? '${event.duration}ms' : 'N/A';
    final statusText = event.statusText != null ? ' (${event.statusText})' : '';
    return '''
# Network Request Details

## Request
- **Method:** ${event.method}
- **URL:** ${event.url}
- **Client:** ${event.requestClient}
- **Timestamp:** $timestamp

## Response
- **Status:** ${event.status ?? 'Pending'}$statusText
- **Duration:** $duration
- **Request Size:** ${event.requestSize != null ? formatBytes(event.requestSize) : 'N/A'}
- **Response Size:** ${event.responseSize != null ? formatBytes(event.responseSize) : 'N/A'}
${event.error != null ? '- **Error:** ${event.error}' : ''}

## Request Headers
```json
${pretty(event.requestHeaders)}
```

## Request Data
```json
${pretty(event.requestData)}
```

## Response Headers
```json
${pretty(event.responseHeaders)}
```

## Response Data
```json
${pretty(event.responseData)}
```
''';
  }

  @override
  Widget build(BuildContext context) {
    final status = event.status != null
        ? formatHttpStatus(event.status!)
        : null;
    final isPending = event.status == null && event.error == null;

    return ColoredBox(
      color: MacOSColors.backgroundBase,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          // Request details card — always visible.
          _card(
            margin: const EdgeInsets.only(left: 12, right: 12, top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MacOSColors.infoBackground,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.method,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: MacOSColors.info,
                        ),
                      ),
                    ),
                    if (status != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: status.color.hexAlpha(0x20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${status.text} ${status.meaning}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: status.color,
                          ),
                        ),
                      )
                    else if (isPending)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: MacOSColors.warningBackground,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 4,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 10,
                              color: MacOSColors.warning,
                            ),
                            Text(
                              'Pending',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: MacOSColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (event.duration != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4,
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 10,
                            color: MacOSColors.textMuted,
                          ),
                          Text(
                            formatDuration(event.duration),
                            style: const TextStyle(
                              fontSize: 11,
                              color: MacOSColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    const Spacer(),
                    CopyButton(value: _fullRequestDetails, size: 14),
                  ],
                ),
                const SizedBox(height: 12),
                _UrlBreakdown(event: event),
                if (event.error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MacOSColors.errorBackground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      spacing: 6,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 12,
                          color: MacOSColors.error,
                        ),
                        Expanded(
                          child: Text(
                            event.error!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: MacOSColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Timing card — always visible.
          _card(
            margin: const EdgeInsets.only(left: 12, right: 12, top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 12,
                      color: MacOSColors.textSecondary,
                    ),
                    const Text(
                      'Started:',
                      style: TextStyle(
                        fontSize: 11,
                        color: MacOSColors.textSecondary,
                      ),
                    ),
                    Text(
                      formatRelativeTime(event.timestamp),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: MacOSColors.textPrimary,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        '(${_localTime(event.timestamp)})',
                        style: const TextStyle(
                          fontSize: 10,
                          color: MacOSColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                if (event.requestSize != null || event.responseSize != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.only(top: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: MacOSColors.borderDefault),
                      ),
                    ),
                    child: Row(
                      spacing: 16,
                      children: [
                        if (event.requestSize != null)
                          _sizeItem(
                            Icons.arrow_upward,
                            MacOSColors.info,
                            'Sent:',
                            event.requestSize!,
                          ),
                        if (event.responseSize != null)
                          _sizeItem(
                            Icons.arrow_downward,
                            MacOSColors.success,
                            'Received:',
                            event.responseSize!,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          _CollapsibleSection(
            title: 'Request Headers',
            icon: Icons.arrow_upward,
            iconColor: MacOSColors.info,
            child: event.requestHeaders.isNotEmpty
                ? DataViewer(data: event.requestHeaders, initialExpanded: true)
                : _emptyText('No request headers'),
          ),
          _CollapsibleSection(
            title: 'Response Headers',
            icon: Icons.arrow_downward,
            iconColor: MacOSColors.success,
            child: event.responseHeaders.isNotEmpty
                ? DataViewer(data: event.responseHeaders, initialExpanded: true)
                : _emptyText('No response headers yet'),
          ),
          if (event.requestData != null)
            _CollapsibleSection(
              title: 'Request Body',
              icon: Icons.data_object,
              iconColor: MacOSColors.info,
              child: DataViewer(data: event.requestData, initialExpanded: true),
            ),
          if (event.responseData != null)
            _CollapsibleSection(
              title: 'Response Body',
              icon: Icons.data_object,
              iconColor: MacOSColors.success,
              child: DataViewer(
                data: event.responseData,
                initialExpanded: true,
              ),
            ),
          _CollapsibleSection(
            title: 'Filter Options',
            icon: Icons.filter_alt_outlined,
            iconColor: MacOSColors.warning,
            child: _FilterOptions(event: event),
          ),
        ],
      ),
    );
  }

  static String _localTime(int timestampMs) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    String pad(int n) => n.toString().padLeft(2, '0');
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final suffix = time.hour < 12 ? 'AM' : 'PM';
    return '$hour12:${pad(time.minute)}:${pad(time.second)} $suffix';
  }

  static Widget _card({required EdgeInsets margin, required Widget child}) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: child,
    );
  }

  static Widget _sizeItem(
    IconData icon,
    Color color,
    String label,
    int bytes,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Icon(icon, size: 10, color: color),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: MacOSColors.textMuted),
        ),
        Text(
          formatBytes(bytes),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            color: MacOSColors.info,
          ),
        ),
      ],
    );
  }

  static Widget _emptyText(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12,
        fontStyle: FontStyle.italic,
        color: MacOSColors.textMuted,
      ),
    );
  }
}

/// UrlBreakdown — lock icon + host + protocol + copy, path/query line, and a
/// collapsible Query Parameters DataViewer.
class _UrlBreakdown extends StatefulWidget {
  const _UrlBreakdown({required this.event});

  final NetworkCaptureEvent event;

  @override
  State<_UrlBreakdown> createState() => _UrlBreakdownState();
}

class _UrlBreakdownState extends State<_UrlBreakdown> {
  bool _showParams = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final uri = Uri.tryParse(event.url);
    final isSecure = uri?.scheme == 'https';
    final host = uri == null
        ? event.url
        : (uri.hasPort ? '${uri.host}:${uri.port}' : uri.host);
    final protocol = uri?.scheme.toUpperCase() ?? '';
    var pathname = uri?.path ?? '';
    final operationName = event.operationName;
    if (event.requestClient == 'graphql' && operationName != null) {
      pathname =
          '$pathname (${formatGraphQLDisplay(operationName, event.graphqlVariables)})';
    } else if (operationName != null) {
      pathname = '$pathname ($operationName)';
    }
    final params = uri != null && uri.queryParameters.isNotEmpty
        ? uri.queryParameters
        : null;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundInput,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 6,
            children: [
              Icon(
                isSecure ? Icons.lock_outline : Icons.lock_open,
                size: 12,
                color: isSecure ? MacOSColors.success : MacOSColors.warning,
              ),
              Expanded(
                child: Text(
                  host,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MacOSColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '($protocol)',
                style: const TextStyle(
                  fontSize: 10,
                  color: MacOSColors.textMuted,
                ),
              ),
              CopyButton(value: event.url, size: 14),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: pathname),
                  if (uri != null && uri.query.isNotEmpty)
                    TextSpan(
                      text: '?${uri.query}',
                      style: const TextStyle(color: MacOSColors.info),
                    ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: MacOSColors.textSecondary,
              ),
            ),
          ),
          if (params != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  TouchableOpacity(
                    activeOpacity: 0.7,
                    onTap: () => setState(() => _showParams = !_showParams),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: MacOSColors.backgroundHover,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MacOSColors.borderDefault),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Query Parameters',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                color: MacOSColors.textPrimary,
                              ),
                            ),
                          ),
                          Icon(
                            _showParams
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 14,
                            color: MacOSColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showParams)
                    DataViewer(data: params, initialExpanded: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// CollapsibleSection — card with a tappable hover-tinted header.
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  /// RN defaultOpen is only true for the omitted-body placeholder (desktop
  /// resolver), which doesn't exist on-device — all sections start closed.
  static const defaultOpen = false;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _isOpen = _CollapsibleSection.defaultOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, top: 8),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TouchableOpacity(
            activeOpacity: 0.2,
            onTap: () => setState(() => _isOpen = !_isOpen),
            child: Container(
              padding: const EdgeInsets.all(12),
              color: MacOSColors.backgroundHover,
              child: Row(
                children: [
                  Icon(widget.icon, size: 14, color: widget.iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MacOSColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    _isOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: MacOSColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_isOpen)
            Padding(padding: const EdgeInsets.all(12), child: widget.child),
        ],
      ),
    );
  }
}

/// Filter Options — ignore-domain / ignore-URL-pattern toggles wired to the
/// shared IgnoredPatternsStore.
class _FilterOptions extends StatelessWidget {
  const _FilterOptions({required this.event});

  final NetworkCaptureEvent event;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(event.url);
    final domain = uri?.host ?? '';
    final urlPath = (uri != null && uri.path.isNotEmpty)
        ? uri.path
        : event.url;

    return ListenableBuilder(
      listenable: IgnoredPatternsStore.instance,
      builder: (context, _) {
        final values = IgnoredPatternsStore.instance.values;
        final isDomainIgnored = values.contains(domain);
        final isUrlIgnored = values.contains(urlPath);
        return Column(
          spacing: 12,
          children: [
            _filterOption(
              icon: Icons.public,
              label: 'Ignore Domain',
              value: domain.isNotEmpty ? domain : 'N/A',
              isIgnored: isDomainIgnored,
              onTap: domain.isNotEmpty
                  ? () => IgnoredPatternsStore.instance.toggle(domain)
                  : null,
            ),
            _filterOption(
              icon: Icons.link,
              label: 'Ignore URL Pattern',
              value: urlPath.isNotEmpty ? urlPath : 'N/A',
              isIgnored: isUrlIgnored,
              onTap: urlPath.isNotEmpty
                  ? () => IgnoredPatternsStore.instance.toggle(urlPath)
                  : null,
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MacOSColors.infoBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: MacOSColors.info.hexAlpha(0x33)),
              ),
              child: const Text(
                'Ignored requests will be hidden from the network list. You '
                'can manage filters in the Filters tab.',
                style: TextStyle(
                  fontSize: 11,
                  height: 16 / 11,
                  color: MacOSColors.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filterOption({
    required IconData icon,
    required String label,
    required String value,
    required bool isIgnored,
    VoidCallback? onTap,
  }) {
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isIgnored
              ? MacOSColors.warningBackground
              : MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isIgnored
                ? MacOSColors.warning.hexAlpha(0x33)
                : MacOSColors.borderDefault,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isIgnored ? MacOSColors.warning : MacOSColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.5,
                      color: MacOSColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: MacOSColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isIgnored
                    ? MacOSColors.warning.hexAlpha(0x26)
                    : MacOSColors.backgroundInput,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isIgnored
                      ? MacOSColors.warning.hexAlpha(0x4D)
                      : MacOSColors.borderDefault,
                ),
              ),
              child: Text(
                isIgnored ? 'IGNORED' : 'IGNORE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: isIgnored
                      ? MacOSColors.warning
                      : MacOSColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
