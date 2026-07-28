/// Ports packages/events/src/components/UnifiedEventDetail.tsx.
///
/// Detail view for one event. Delegates to the event's own tool detail builder
/// (the registered [EventSourceAdapter.detailBuilder] — the REAL
/// NetworkDetailView / StorageEventDetail / RouteEventDetail), so a network
/// event shows the same detail page the Network tool does, with the shared
/// ignored-patterns toggles. Falls back to a generic [DataViewer] view.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../unified_event_store.dart';
import 'source_config.dart';

class UnifiedEventDetail extends StatelessWidget {
  const UnifiedEventDetail({
    super.key,
    required this.event,
    this.onNavigate,
  });

  final UnifiedEvent event;
  final void Function(String pathname)? onNavigate;

  @override
  Widget build(BuildContext context) {
    final discoveryId = eventSourceToDiscoveryId[event.source];
    final adapter =
        discoveryId != null ? eventSourceRegistry.byId(discoveryId) : null;
    final detailBuilder = adapter?.detailBuilder;

    if (detailBuilder != null) {
      return ColoredBox(
        color: BuoyColors.base,
        child: detailBuilder(context, event, onNavigate),
      );
    }

    return _genericDetail(context);
  }

  Widget _genericDetail(BuildContext context) {
    final config = sourceConfigFor(event.source);
    final timestamp = DateTime.fromMillisecondsSinceEpoch(event.timestamp);

    return ColoredBox(
      color: BuoyColors.base,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source badge.
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: config.color.hexAlpha(0x20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: config.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    config.label,
                    style: TextStyle(
                      color: config.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Text(
              event.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: BuoyColors.text,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              event.subtitle,
              style: const TextStyle(
                fontSize: 16,
                color: BuoyColors.textMuted,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: BuoyColors.border),
                  bottom: BorderSide(color: BuoyColors.border),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Timestamp',
                      style: TextStyle(
                          fontSize: 14,
                          color: BuoyColors.textMuted,
                          fontFamily: 'monospace')),
                  Text(
                    '${timestamp.toLocal().toString().split(".").first} '
                    '(${formatRelativeTime(event.timestamp)})',
                    style: const TextStyle(
                      fontSize: 14,
                      color: BuoyColors.text,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'EVENT DATA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: BuoyColors.textMuted,
                letterSpacing: 0.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: BuoyColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BuoyColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: DataViewer(data: event.data, initialExpanded: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
