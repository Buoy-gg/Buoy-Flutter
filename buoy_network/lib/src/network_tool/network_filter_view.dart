import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../network_capture.dart';
import 'network_filter.dart';

/// Port of NetworkFilterViewV3 — the Filters tab: status/method/content-type
/// facet grids with counts over the currently filtered list, the shared
/// exclude-pattern manager (CONTAINS/EXACT modes), available domains & URLs,
/// and the how-it-works explainer.
class NetworkFilterView extends StatefulWidget {
  const NetworkFilterView({
    super.key,
    required this.events,
    required this.filter,
    required this.onFilterChange,
  });

  /// The same filtered list the user is looking at (facet counts read it).
  final List<NetworkCaptureEvent> events;
  final NetworkFilter filter;
  final ValueChanged<NetworkFilter> onFilterChange;

  @override
  State<NetworkFilterView> createState() => _NetworkFilterViewState();
}

class _NetworkFilterViewState extends State<NetworkFilterView> {
  /// Mode applied when the user submits the add-pattern input.
  IgnoredPatternMatchMode _nextPatternMode = IgnoredPatternMatchMode.contains;

  Color _contentTypeColor(String type) => switch (type) {
    'JSON' => MacOSColors.info,
    'XML' => MacOSColors.success,
    'HTML' => MacOSColors.warning,
    'TEXT' => MacOSColors.success,
    'IMAGE' => MacOSColors.error,
    'VIDEO' => MacOSColors.error,
    'AUDIO' => MacOSColors.debug,
    'FORM' => MacOSColors.info,
    _ => MacOSColors.textMuted,
  };

  LucideIcon _contentTypeIcon(String type) => switch (type) {
    'JSON' => BuoyIcons.braces,
    'HTML' || 'XML' || 'TEXT' => BuoyIcons.fileText,
    'IMAGE' => BuoyIcons.image,
    'VIDEO' => BuoyIcons.film,
    'AUDIO' => BuoyIcons.music,
    _ => BuoyIcons.globe,
  };

  Color _methodColor(String method) => switch (method) {
    'GET' => MacOSColors.success,
    'POST' => MacOSColors.info,
    'PUT' => MacOSColors.warning,
    'DELETE' => MacOSColors.error,
    'PATCH' => MacOSColors.success,
    _ => MacOSColors.textMuted,
  };

  void _handleFilterChange(String optionId, Object? value) {
    final filter = widget.filter;
    final group = optionId.split('::').first;
    if (group == 'status') {
      widget.onFilterChange(
        filter.copyWith(
          status: value == 'all' ? null : value as NetworkStatusFilter?,
        ),
      );
    } else if (group == 'method') {
      final method = value as String;
      final current = filter.methods ?? const [];
      // RN: toggling off removes; toggling on REPLACES the selection.
      final updated = current.contains(method)
          ? [...current.where((m) => m != method)]
          : [method];
      widget.onFilterChange(
        filter.copyWith(methods: updated.isEmpty ? null : updated),
      );
    } else if (group == 'noise') {
      widget.onFilterChange(filter.copyWith(hideImages: !filter.hideImages));
    } else if (group == 'contentType') {
      final type = value as String;
      final current = filter.contentTypes ?? const [];
      final updated = current.contains(type)
          ? [...current.where((t) => t != type)]
          : [type];
      widget.onFilterChange(
        filter.copyWith(contentTypes: updated.isEmpty ? null : updated),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    final filter = widget.filter;

    // Facet counts.
    var success = 0, error = 0, pending = 0;
    final methodCounts = <String, int>{};
    final contentTypeCounts = <String, int>{};
    final domains = <String>{};
    final urls = <String>{};
    for (final event in events) {
      if (isErrorEvent(event)) {
        error++;
      } else if (isSuccessEvent(event)) {
        success++;
      } else if (isPendingEvent(event)) {
        pending++;
      }
      methodCounts[event.method] = (methodCounts[event.method] ?? 0) + 1;
      final type = contentTypeLabel(event);
      contentTypeCounts[type] = (contentTypeCounts[type] ?? 0) + 1;
      final uri = Uri.tryParse(event.url);
      if (uri != null && uri.host.isNotEmpty) {
        domains.add(uri.hasPort ? '${uri.host}:${uri.port}' : uri.host);
        urls.add('${uri.scheme}://${uri.host}'
            '${uri.hasPort ? ':${uri.port}' : ''}${uri.path}');
      }
    }
    // From the store, NOT from `events`: this screen is handed the ALREADY
    // filtered list, so with the image filter on (its default) counting there
    // always yields 0 — a switch that reports "0" is a switch nobody believes.
    final imageCount = applyIgnoredPatterns(
      NetworkEventStore.instance.events,
      IgnoredPatternsStore.instance.patterns,
    ).where(isImageEvent).length;
    final sortedDomains = domains.toList()..sort();
    final sortedUrls = urls.toList()..sort();
    final suggestions = [
      ...sortedDomains.take(30),
      ...sortedUrls.take(30),
    ];

    return ListenableBuilder(
      listenable: IgnoredPatternsStore.instance,
      builder: (context, _) {
        final store = IgnoredPatternsStore.instance;
        final patternModes = {
          for (final p in store.patterns) p.value: p.mode,
        };
        return DynamicFilterView(
          sections: [
            FilterSectionConfig(
              id: 'status',
              title: 'Status',
              options: [
                for (final (key, label, count, icon, color, value) in [
                  (
                    'all',
                    'All',
                    events.length,
                    BuoyIcons.globe,
                    MacOSColors.info,
                    'all',
                  ),
                  (
                    'success',
                    'Success',
                    success,
                    BuoyIcons.checkCircle,
                    MacOSColors.success,
                    NetworkStatusFilter.success,
                  ),
                  (
                    'error',
                    'Error',
                    error,
                    BuoyIcons.xCircle,
                    MacOSColors.error,
                    NetworkStatusFilter.error,
                  ),
                  (
                    'pending',
                    'Pending',
                    pending,
                    BuoyIcons.clock,
                    MacOSColors.warning,
                    NetworkStatusFilter.pending,
                  ),
                ])
                  FilterOption(
                    id: 'status::$key',
                    label: label,
                    count: count,
                    icon: icon,
                    color: color,
                    value: value,
                    isActive: key == 'all'
                        ? filter.status == null
                        : filter.status == value,
                  ),
              ],
            ),
            // Its own section rather than a Content-Type chip: content types
            // are a "show only these" picker, and this is a "hide these"
            // switch that is already on. Mixing the two in one row would make
            // an on-by-default chip look like an active selection.
            FilterSectionConfig(
              id: 'noise',
              title: 'Noise',
              options: [
                FilterOption(
                  id: 'noise::images',
                  label: 'Hide images',
                  count: imageCount,
                  icon: BuoyIcons.image,
                  color: MacOSColors.textMuted,
                  value: 'images',
                  isActive: filter.hideImages,
                ),
              ],
            ),
            if (methodCounts.isNotEmpty)
              FilterSectionConfig(
                id: 'method',
                title: 'Method',
                options: [
                  for (final entry in methodCounts.entries)
                    FilterOption(
                      id: 'method::${entry.key}',
                      label: entry.key,
                      count: entry.value,
                      color: _methodColor(entry.key),
                      isMethodBadge: true,
                      value: entry.key,
                      isActive: filter.methods?.contains(entry.key) ?? false,
                    ),
                ],
              ),
            if (contentTypeCounts.isNotEmpty)
              FilterSectionConfig(
                id: 'contentType',
                title: 'Content Type',
                options: [
                  for (final entry in contentTypeCounts.entries)
                    FilterOption(
                      id: 'contentType::${entry.key}',
                      label: entry.key,
                      count: entry.value,
                      icon: _contentTypeIcon(entry.key),
                      color: _contentTypeColor(entry.key),
                      value: entry.key,
                      isActive:
                          filter.contentTypes?.contains(entry.key) ?? false,
                    ),
                ],
              ),
          ],
          onFilterChange: _handleFilterChange,
          addFilterEnabled: true,
          addFilterTitle: 'ACTIVE FILTERS',
          addFilterPlaceholder: 'Enter domain or URL pattern...',
          addFilterExtra: (context) => _modeToggleRow(),
          activePatterns: [for (final p in store.patterns) p.value],
          onPatternAdd: (pattern) =>
              store.add(IgnoredPattern(pattern, _nextPatternMode)),
          onPatternRemove: store.remove,
          patternMetaBuilder: (pattern) => _modeBadge(
            pattern,
            patternModes[pattern] ?? IgnoredPatternMatchMode.contains,
          ),
          availableItemsEnabled: true,
          availableItemsTitle: 'AVAILABLE DOMAINS & URLS',
          availableItemsEmptyMessage:
              'No network events captured yet. Domains and URLs will appear here.',
          availableItems: suggestions,
          howItWorksEnabled: true,
          howItWorksTitle: 'HOW NETWORK FILTERS WORK',
          howItWorksDescription:
              'Patterns hide matching requests from the network event list. '
              'Each pattern has a match mode you can toggle on its badge: '
              'CONTAINS hides any URL containing the text; EXACT hides only '
              'an exact path/host/url match.',
          howItWorksExamples: const [
            '• example.com (CONTAINS) → any request whose URL contains example.com',
            '• example.com (EXACT) → only requests served by that exact host',
            '• /v1 (CONTAINS) → any URL containing /v1 (e.g. /v1, /v1/users)',
            '• /v1 (EXACT) → only requests whose pathname is exactly /v1',
          ],
        );
      },
    );
  }

  /// Per-pattern CONTAINS/EXACT badge — tap flips the mode.
  Widget _modeBadge(String pattern, IgnoredPatternMatchMode mode) {
    final isExact = mode == IgnoredPatternMatchMode.exact;
    final color = isExact ? MacOSColors.warning : MacOSColors.info;
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: () => IgnoredPatternsStore.instance.toggleMode(pattern),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.hexAlpha(0x15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.hexAlpha(0x60)),
        ),
        child: Text(
          isExact ? 'EXACT' : 'CONTAINS',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ),
    );
  }

  /// "Match: [Contains|Exact]" toggle above the add-pattern input.
  Widget _modeToggleRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        spacing: 8,
        children: [
          const Text(
            'Match:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              fontFamily: 'monospace',
              color: MacOSColors.textSecondary,
            ),
          ),
          for (final (label, mode, hint) in [
            ('Contains', IgnoredPatternMatchMode.contains, 'substring'),
            ('Exact', IgnoredPatternMatchMode.exact, 'whole path/host/url'),
          ])
            Expanded(
              child: TouchableOpacity(
                activeOpacity: 0.2,
                onTap: () => setState(() => _nextPatternMode = mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _nextPatternMode == mode
                        ? MacOSColors.info.hexAlpha(0x22)
                        : MacOSColors.backgroundHover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _nextPatternMode == mode
                          ? MacOSColors.info
                          : MacOSColors.borderDefault,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          fontFamily: 'monospace',
                          color: _nextPatternMode == mode
                              ? MacOSColors.info
                              : MacOSColors.textSecondary,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          hint,
                          style: const TextStyle(
                            fontSize: 9,
                            color: MacOSColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
