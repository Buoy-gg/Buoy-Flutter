/// Ports packages/events/src/components/UnifiedEventList.tsx.
///
/// Scrollable list of timeline rows with the empty-state handling. Free-tier
/// hidden-events banner is omitted (briefing precedent — all events shown).
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'unified_event_item.dart';

class UnifiedEventList extends StatelessWidget {
  const UnifiedEventList({
    super.key,
    required this.events,
    required this.onEventPress,
    required this.isCapturing,
  });

  final List<UnifiedEvent> events;
  final ValueChanged<UnifiedEvent> onEventPress;
  final bool isCapturing;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return ColoredBox(
        color: BuoyColors.base,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCapturing ? 'No Events Yet' : 'Not Capturing',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: BuoyColors.text,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isCapturing
                      ? 'Events will appear here as they occur.\nTry interacting with your app.'
                      : 'Event capture is paused. Resume to see events.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: BuoyColors.textMuted,
                    height: 1.4,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: BuoyColors.base,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: events.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final event = events[index];
          return UnifiedEventItem(
            key: ValueKey(event.id),
            event: event,
            onPress: () => onEventPress(event),
          );
        },
      ),
    );
  }
}
