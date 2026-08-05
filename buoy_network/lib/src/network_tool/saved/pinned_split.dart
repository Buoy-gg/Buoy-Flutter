/// Ports packages/network/src/network/utils/withPinnedFirst.ts and
/// `selectSavedEvents.ts` — the two list derivations that must not drift.
///
/// Pure functions on purpose: on RN there are two list implementations (the
/// mobile modal and the desktop dashboard's hand-mirror) and pin ordering
/// silently diverging between them is exactly the drift `buoy.tools.json`
/// exists to prevent. Same reasoning applies across frameworks.
library;

import '../../network_capture.dart';
import 'network_saved_store.dart';

class PinnedSplit {
  const PinnedSplit({required this.pinned, required this.rest});

  /// Pinned snapshots, newest first — rendered above the list.
  final List<NetworkCaptureEvent> pinned;

  /// The filtered list minus anything already shown as a pin.
  final List<NetworkCaptureEvent> rest;
}

/// Split a filtered event list into its PINNED section and the rest.
///
/// Pins are deliberately NOT filtered: they come straight from the saved store,
/// so a pinned request stays visible no matter what the search box or the
/// status chips say. The only thing the filtered list contributes is the
/// dedupe — a pinned request that is still live must not render twice.
PinnedSplit splitPinned(
  List<NetworkCaptureEvent> filtered,
  List<NetworkCaptureEvent> pinnedEvents,
  Set<String> pinnedLiveIds,
) {
  if (pinnedEvents.isEmpty) {
    return PinnedSplit(pinned: const [], rest: filtered);
  }
  return PinnedSplit(
    pinned: pinnedEvents,
    rest: pinnedLiveIds.isEmpty
        ? filtered
        : [
            for (final event in filtered)
              if (!pinnedLiveIds.contains(event.id)) event,
          ],
  );
}

/// The Saved screen's visible list.
///
/// Two places need the exact same list: the screen that renders it and the
/// detail footer that steps through it. Deriving it independently is how
/// "Next" ends up disagreeing with the row below.
///
/// RN also returns a `lockedCount` for saves past the free-tier ceiling; the
/// Flutter port has no client-side tier gate, so every save is visible and
/// [maxSaved] is the only bound.
List<NetworkCaptureEvent> selectSavedEvents(
  List<SavedNetworkRecord> savedRecords,
  String search,
) {
  final events = [
    for (final record in savedRecords.take(maxSaved)) record.event,
  ];
  if (search.isEmpty) return events;
  final needle = search.toLowerCase();
  return [
    for (final event in events)
      if (event.url.toLowerCase().contains(needle) ||
          event.method.toLowerCase().contains(needle) ||
          (event.status?.toString().contains(needle) ?? false))
        event,
  ];
}
