/// Ports packages/route-events/src/components/RouteEventsTimeline.tsx +
/// RouteEventItemCompact.tsx.
///
/// The chronological navigation timeline (newest-first) and its compact row.
/// A row uses [CompactRow] (status dot + label · pathname · Go button · relative
/// time). Tapping a row opens the full-screen detail (parity with the Events
/// tool). RN numerics inlined below.
library;

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../route_template.dart';
import '../routes_capture.dart';

/// RN route-type color classification (RouteEventItemCompact).
enum _RouteType { home, dynamic, withParams, defaultType }

_RouteType _routeTypeFor(RouteChangeEvent event) {
  if (event.pathname == '/') return _RouteType.home;
  if (getRouteTemplate(event.pathname, event.segments) != null) {
    return _RouteType.dynamic;
  }
  if (event.params.isNotEmpty) return _RouteType.withParams;
  return _RouteType.defaultType;
}

Color _routeTypeColor(_RouteType type) {
  switch (type) {
    case _RouteType.home:
      return BuoyColors.success;
    case _RouteType.dynamic:
      return BuoyColors.primary;
    case _RouteType.withParams:
      return BuoyColors.warning;
    case _RouteType.defaultType:
      return BuoyColors.textSecondary;
  }
}

String _statusLabel(_RouteType type) {
  switch (type) {
    case _RouteType.home:
      return 'Home';
    case _RouteType.dynamic:
      return 'Dynamic';
    case _RouteType.withParams:
      return 'Params';
    case _RouteType.defaultType:
      return 'Static';
  }
}

/// RN `formatDuration` (compact variant in RouteEventItemCompact).
String formatCompactDuration(num ms) {
  if (ms < 1000) return '${ms.round()}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
}

String _statusSublabel(RouteChangeEvent event) {
  final parts = <String>[];
  final since = event.timeSincePrevious;
  if (since != null && since > 0) parts.add(formatCompactDuration(since));
  final depth = event.segments.length;
  if (depth > 0) parts.add('depth $depth');
  return parts.isEmpty ? 'root' : parts.join(' · ');
}

String? _badgeText(RouteChangeEvent event) {
  final count = event.params.length;
  if (count > 0) return '$count PARAM${count != 1 ? 'S' : ''}';
  return null;
}

/// The chronological timeline (RN RouteEventsTimeline, ListView.builder with
/// stable `${timestamp}-${pathname}` keys — index keys remount rows on prepend).
class RouteEventsTimeline extends StatelessWidget {
  const RouteEventsTimeline({
    super.key,
    required this.events,
    required this.visitCounts,
    required this.onNavigate,
    required this.onSelectEvent,
  });

  final List<RouteChangeEvent> events;
  final Map<int, int> visitCounts;
  final void Function(String pathname) onNavigate;
  final void Function(RouteChangeEvent event, int visitNumber) onSelectEvent;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return RouteEventRow(
          key: ValueKey('${event.timestamp}-${event.pathname}'),
          event: event,
          visitNumber: visitCounts[index] ?? 1,
          onNavigate: onNavigate,
          onPress: () => onSelectEvent(event, visitCounts[index] ?? 1),
        );
      },
    );
  }
}

/// A single compact timeline row (RN RouteEventItemCompact).
class RouteEventRow extends StatelessWidget {
  const RouteEventRow({
    super.key,
    required this.event,
    required this.visitNumber,
    required this.onNavigate,
    required this.onPress,
  });

  final RouteChangeEvent event;
  final int visitNumber;
  final void Function(String pathname) onNavigate;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final type = _routeTypeFor(event);
    final color = _routeTypeColor(type);
    final badge = _badgeText(event);

    return CompactRow(
      statusDotColor: color,
      statusLabel: _statusLabel(type),
      statusSublabel: _statusSublabel(event),
      primaryText: event.pathname,
      showChevron: true,
      badgeColor: color,
      customBadge: _goBadge(badge, color),
      bottomRightText: RelativeTime(timestamp: event.timestamp),
      onPress: onPress,
    );
  }

  Widget _goBadge(String? badge, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: color,
              ),
            ),
          ),
        TouchableOpacity(
          activeOpacity: 0.7,
          onTap: () => onNavigate(event.pathname),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: BuoyColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Go',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFFFFFF),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
