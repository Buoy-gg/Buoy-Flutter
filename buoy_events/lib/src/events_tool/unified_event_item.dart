/// Ports packages/events/src/components/UnifiedEventItem.tsx.
///
/// Renders one timeline row. Delegates to the event's own tool row builder (the
/// registered [EventSourceAdapter.rowBuilder] — the real NetworkEventRow /
/// StorageEventCard / RouteEventRow), wrapping non-network rows in a small
/// top-right SOURCE badge. Falls back to [CompactRow] when a source has no
/// builder.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../unified_event_store.dart';
import 'source_config.dart';

class UnifiedEventItem extends StatelessWidget {
  const UnifiedEventItem({
    super.key,
    required this.event,
    required this.onPress,
  });

  final UnifiedEvent event;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final discoveryId = eventSourceToDiscoveryId[event.source];
    final adapter =
        discoveryId != null ? eventSourceRegistry.byId(discoveryId) : null;
    final rowBuilder = adapter?.rowBuilder;

    if (rowBuilder != null) {
      final row = rowBuilder(context, event, onPress);
      // Network rows carry their own badges — no SOURCE wrapper (RN parity).
      if (event.source == EventSourceIds.network) return row;
      return _SourceBadgeWrapper(source: event.source, child: row);
    }

    // Fallback: CompactRow (RN's generic fallback).
    final config = sourceConfigFor(event.source);
    return CompactRow(
      statusDotColor: config.color,
      statusLabel: config.label,
      primaryText: event.title,
      secondaryText: event.subtitle,
      bottomRightText: formatRelativeTime(event.timestamp),
      showChevron: true,
      onPress: onPress,
    );
  }
}

/// Ports `SourceBadgeWrapper` — a small source badge pinned top-right.
class _SourceBadgeWrapper extends StatelessWidget {
  const _SourceBadgeWrapper({required this.source, required this.child});

  final String source;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final config = sourceConfigFor(source);
    return Stack(
      children: [
        child,
        Positioned(
          top: 4,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: config.color.hexAlpha(0x20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              config.badgeLabel,
              style: TextStyle(
                color: config.color,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
