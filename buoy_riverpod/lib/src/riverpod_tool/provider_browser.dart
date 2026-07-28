/// Ports packages/jotai/src/jotai/components/JotaiAtomBrowser.tsx — the
/// Providers tab. One [CompactRow] per registered provider showing its live
/// (last-observed) value; expand for the type pill, change count + "view
/// history", and a [DataViewer] of the value.
library;

import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../riverpod_state_store.dart';
import '../riverpod_types.dart';

class ProviderBrowser extends StatefulWidget {
  const ProviderBrowser({
    super.key,
    required this.providers,
    required this.searchQuery,
    required this.onViewHistory,
  });

  final List<ProviderInfo> providers;
  final String searchQuery;
  final ValueChanged<String> onViewHistory;

  @override
  State<ProviderBrowser> createState() => _ProviderBrowserState();
}

class _ProviderBrowserState extends State<ProviderBrowser> {
  String? _expanded;

  List<ProviderInfo> get _filtered {
    if (widget.searchQuery.isEmpty) return widget.providers;
    final search = widget.searchQuery.toLowerCase();
    return widget.providers
        .where((p) => p.label.toLowerCase().contains(search))
        .toList();
  }

  static String _valuePreview(Object? value) {
    if (value == null) return 'null';
    if (value is List) {
      return value.isEmpty
          ? '[]'
          : '[${value.length} item${value.length == 1 ? "" : "s"}]';
    }
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList();
      if (keys.isEmpty) return '{}';
      if (keys.length <= 3) return keys.join(', ');
      return '${keys.take(2).join(", ")} +${keys.length - 2}';
    }
    final s = value.toString();
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  static String _valueType(Object? value) {
    if (value == null) return 'null';
    if (value is List) return 'array · ${value.length}';
    if (value is Map) return 'object';
    if (value is String) return 'string';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    return 'object';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    if (filtered.isEmpty && widget.searchQuery.isEmpty) {
      return _empty(
        'No providers registered',
        'Attach BuoyRiverpodObserver to your ProviderScope.\n'
            'Providers appear here with their current value.',
      );
    }
    if (filtered.isEmpty) {
      return _empty(
        'No matching providers',
        'No providers match "${widget.searchQuery}"',
        icon: false,
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('PROVIDERS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: MacOSColors.textMuted)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: BuoyColors.primary.hexAlpha(0x26),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${filtered.length}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: BuoyColors.primary,
                        fontFamily: 'monospace')),
              ),
            ],
          ),
        ),
        for (final provider in filtered) _row(provider),
      ],
    );
  }

  Widget _row(ProviderInfo provider) {
    final isExpanded = _expanded == provider.label;
    final color = Color(riverpodStateStore.providerColor(provider.label));

    return Stack(
      children: [
        CompactRow(
          statusDotColor: color,
          statusLabel: provider.label,
          statusSublabel: _valueType(provider.currentValue),
          primaryText: _valuePreview(provider.currentValue),
          showChevron: true,
          isExpanded: isExpanded,
          onPress: () => setState(
              () => _expanded = isExpanded ? null : provider.label),
          expandedContent: isExpanded
              ? _ExpandedContent(
                  provider: provider,
                  color: color,
                  onViewHistory: widget.onViewHistory,
                )
              : null,
        ),
        if (provider.changeCount > 0)
          Positioned(
            top: 4,
            right: 10,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.hexAlpha(0x22),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.hexAlpha(0x55)),
                ),
                child: Text('${provider.changeCount}',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        color: color)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _empty(String title, String body, {bool icon = true}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon)
              const BuoyGlyph(BuoyIcons.box,
                  size: 32, color: MacOSColors.textMuted),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(title,
                  style: const TextStyle(
                      color: MacOSColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: MacOSColors.textMuted, fontSize: 12, height: 18 / 12)),
          ],
        ),
      ),
    );
  }
}

class _ExpandedContent extends StatelessWidget {
  const _ExpandedContent({
    required this.provider,
    required this.color,
    required this.onViewHistory,
  });

  final ProviderInfo provider;
  final Color color;
  final ValueChanged<String> onViewHistory;

  @override
  Widget build(BuildContext context) {
    final value = provider.currentValue;
    final isComplex = value is Map || value is List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpandedInfoRow(
          label: 'Type',
          child: PillBadge(color: color, child: const Text('RIVERPOD')),
        ),
        if (provider.changeCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ExpandedInfoRow(
              label: 'Changes',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PillBadge(
                    color: BuoyColors.warning,
                    child: Text('${provider.changeCount}'),
                  ),
                  const SizedBox(width: 4),
                  TouchableOpacity(
                    activeOpacity: 0.7,
                    onTap: () => onViewHistory(provider.label),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text('view history →',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: color)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            decoration: BoxDecoration(
              color: BuoyColors.base,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: BuoyColors.border),
            ),
            clipBehavior: Clip.hardEdge,
            constraints: const BoxConstraints(minHeight: 60),
            child: isComplex
                ? DataViewer(
                    data: value, showTypeFilter: true, initialExpanded: true)
                : Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('${value ?? "null"}',
                        style: const TextStyle(
                            color: BuoyColors.text,
                            fontSize: 12,
                            fontFamily: 'monospace')),
                  ),
          ),
        ),
      ],
    );
  }
}
