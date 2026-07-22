import 'dart:convert';

import 'package:flutter/material.dart';

import '../network_capture.dart';
import 'package:buoy_core/buoy_core.dart';
import 'copy_settings.dart';
import 'formatting.dart';
import 'macos_colors.dart';
import 'minute_ticker.dart';
import 'widgets/copy_button.dart';
import 'widgets/data_viewer.dart';
import 'widgets/dynamic_filter_view.dart';

/// Port of NetworkCopySettingsView — the Copy tab: quick presets, include
/// toggles, output format, and a collapsible live preview with size
/// warnings + a toolbar copy button. Pro banner dropped (no license system).
class NetworkCopyView extends StatefulWidget {
  const NetworkCopyView({
    super.key,
    required this.events,
    required this.settings,
    required this.onSettingsChange,
  });

  final List<NetworkCaptureEvent> events;
  final CopySettings settings;
  final ValueChanged<CopySettings> onSettingsChange;

  @override
  State<NetworkCopyView> createState() => _NetworkCopyViewState();
}

const _sizeWarningThreshold = 100 * 1024;
const _sizeDangerThreshold = 500 * 1024;

class _NetworkCopyViewState extends State<NetworkCopyView> {
  /// Collapsed by default to prevent giant-preview jank (RN parity).
  bool _previewExpanded = false;

  bool get _hasLiveData => widget.events.isNotEmpty;

  /// The preview's mock request when nothing is captured yet.
  static final _mockEvent = () {
    final event = NetworkCaptureEvent(
      id: 'mock',
      method: 'POST',
      url: 'https://api.example.com/v1/users',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      requestClient: 'http',
      requestHeaders: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ***',
      },
    );
    event.status = 201;
    event.duration = 342;
    event.responseHeaders = {
      'Content-Type': 'application/json',
      'X-Request-ID': 'abc123',
    };
    event.requestData = {'name': 'John Doe', 'email': 'john@example.com'};
    event.responseData = {
      'id': 'user_123',
      'name': 'John Doe',
      'email': 'john@example.com',
      'createdAt': '2025-01-10T12:00:00Z',
    };
    return event;
  }();

  List<NetworkCaptureEvent> get _dataSource =>
      _hasLiveData ? widget.events : [_mockEvent];

  int get _estimatedSize {
    var total = 0;
    int jsonLen(Object? value) {
      try {
        return jsonEncode(value ?? const {}).length;
      } catch (_) {
        return 100;
      }
    }

    for (final event in _dataSource) {
      final settings = widget.settings;
      if (settings.includeMethod) total += event.url.length + 10;
      if (settings.includeStatus) total += 30;
      if (settings.includeTimestamp) total += 30;
      if (settings.includeRequestHeaders) total += jsonLen(event.requestHeaders);
      if (settings.includeRequestBody) total += jsonLen(event.requestData);
      if (settings.includeResponseBody) total += jsonLen(event.responseData);
    }
    return total;
  }

  void _handleOptionChange(String optionId, Object? value) {
    final parts = optionId.split('::');
    final group = parts.first;
    final key = parts.length > 1 ? parts[1] : '';
    final settings = widget.settings;
    switch (group) {
      case 'preset':
        final preset = copyPresets[key];
        if (preset != null) widget.onSettingsChange(preset);
      case 'requestInfo' || 'headers' || 'body':
        widget.onSettingsChange(settings.copyToggled(key));
      case 'format':
        widget.onSettingsChange(
          settings.copyWith(format: value as CopyFormat),
        );
    }
  }

  String _copyText() =>
      generateNetworkCopyText(_dataSource, widget.settings);

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final activePreset = detectActivePreset(settings);

    return DynamicFilterView(
      sections: [
        FilterSectionConfig(
          id: 'presets',
          title: 'Presets',
          options: [
            for (final (key, label, icon, color) in [
              ('urls', 'URLs', Icons.link, MacOSColors.info),
              ('llm', 'LLM', Icons.bolt, MacOSColors.success),
              ('json', 'JSON', Icons.code, MacOSColors.warning),
              ('full', 'Full', Icons.description_outlined, MacOSColors.info),
              (
                'custom',
                'Custom',
                Icons.settings_outlined,
                MacOSColors.textSecondary,
              ),
            ])
              FilterOption(
                id: 'preset::$key',
                label: label,
                icon: icon,
                color: color,
                value: key,
                isActive:
                    key == 'custom' ? activePreset == null : activePreset == key,
              ),
          ],
        ),
        FilterSectionConfig(
          id: 'include',
          title: 'Include',
          options: [
            for (final (id, label) in [
              ('requestInfo::includeMethod', 'URL'),
              ('requestInfo::includeStatus', 'Status'),
              ('requestInfo::includeTimestamp', 'Time'),
              ('headers::includeRequestHeaders', 'Headers'),
              ('body::includeRequestBody', 'Req Body'),
              ('body::includeResponseBody', 'Res Body'),
              ('requestInfo::includeErrors', 'Errors'),
            ])
              FilterOption(
                id: id,
                label: label,
                value: id.split('::').last,
                isActive: settings.boolValue(id.split('::').last),
              ),
          ],
        ),
        FilterSectionConfig(
          id: 'format',
          title: 'Format',
          options: [
            for (final (format, label, icon, color) in [
              (
                CopyFormat.markdown,
                'Markdown',
                Icons.description_outlined,
                MacOSColors.info,
              ),
              (CopyFormat.json, 'JSON', Icons.code, MacOSColors.warning),
              (
                CopyFormat.plaintext,
                'Text',
                Icons.tag,
                MacOSColors.textSecondary,
              ),
            ])
              FilterOption(
                id: 'format::${format.name}',
                label: label,
                icon: icon,
                color: color,
                value: format,
                isActive: settings.format == format,
              ),
          ],
        ),
      ],
      onFilterChange: _handleOptionChange,
      previewEnabled: true,
      previewTitle: 'PREVIEW',
      previewHeaderActions: (context) => [
        ValueListenableBuilder<int>(
          valueListenable: MinuteTicker.instance.tick,
          builder: (context, _, _) {
            final lastEvent = _hasLiveData
                ? widget.events
                      .map((e) => e.timestamp)
                      .reduce((a, b) => a > b ? a : b)
                : null;
            return Text(
              lastEvent != null
                  ? 'Live data • Updated ${formatRelativeTime(lastEvent)}'
                  : 'Mock data (no events captured)',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: MacOSColors.textMuted,
              ),
            );
          },
        ),
        CopyButton(value: _copyText, size: 14),
      ],
      previewBuilder: (context) => _preview(),
    );
  }

  Widget _preview() {
    final requestCount = _dataSource.length;
    final estimatedSize = _estimatedSize;
    final warningLevel = estimatedSize >= _sizeDangerThreshold
        ? 'danger'
        : estimatedSize >= _sizeWarningThreshold
        ? 'warning'
        : 'none';

    if (!_previewExpanded) {
      final warningColor = warningLevel == 'danger'
          ? MacOSColors.error
          : MacOSColors.warning;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          TouchableOpacity(
            activeOpacity: 0.2,
            onTap: () => setState(() => _previewExpanded = true),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MacOSColors.backgroundInput,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MacOSColors.borderDefault),
              ),
              child: Row(
                spacing: 10,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: MacOSColors.info,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Show Preview',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: MacOSColors.textPrimary,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '$requestCount request${requestCount == 1 ? '' : 's'} • ~${formatBytes(estimatedSize)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: MacOSColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: MacOSColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (warningLevel != 'none')
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: warningLevel == 'danger'
                    ? MacOSColors.errorBackground
                    : MacOSColors.warningBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: warningColor.hexAlpha(0x30)),
              ),
              child: Row(
                spacing: 6,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: warningColor,
                  ),
                  Expanded(
                    child: Text(
                      warningLevel == 'danger'
                          ? 'Very large payload - may cause performance issues'
                          : 'Large payload - preview may be slow',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: warningColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TouchableOpacity(
          activeOpacity: 0.2,
          onTap: () => setState(() => _previewExpanded = false),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: MacOSColors.backgroundHover,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: MacOSColors.borderDefault),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                Text(
                  'Hide Preview',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MacOSColors.textSecondary,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_up,
                  size: 14,
                  color: MacOSColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        _expandedPreview(),
      ],
    );
  }

  /// Expanded preview: JSON format renders a DataViewer tree; markdown and
  /// plaintext render the generated copy text in monospace (RN parity —
  /// content matches the copy button's output).
  Widget _expandedPreview() {
    if (widget.settings.format == CopyFormat.json) {
      Object? decoded;
      try {
        decoded = jsonDecode(generateNetworkCopyText(
          _dataSource,
          widget.settings,
        ));
      } catch (_) {
        decoded = null;
      }
      if (decoded != null) {
        return DataViewer(data: decoded, showTypeFilter: false);
      }
    }
    final text = _copyText();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: SingleChildScrollView(
        child: SelectableText(
          text.isEmpty ? 'No data included' : text,
          style: const TextStyle(
            fontSize: 11,
            height: 18 / 11,
            fontFamily: 'monospace',
            color: MacOSColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
