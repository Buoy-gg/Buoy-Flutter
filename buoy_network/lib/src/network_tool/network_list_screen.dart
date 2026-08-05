import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../network_capture.dart';
import 'network_event_row.dart';
import 'network_filter.dart';
import '../overrides/match_rule.dart';
import '../overrides/override_rules_store.dart';
import '../overrides/resolve_override.dart';
import 'saved/network_saved_store.dart';
import 'saved/pinned_split.dart';

/// Port of NetworkListScreen — owns the event-store subscription, the list,
/// empty state, and the interception-disabled banner. The list owns its
/// scrolling (ListView.builder virtualizes; NetworkModal disables JsModal's
/// scroll wrapper while this screen is visible — same contract as RN's
/// disableScrollWrapper).
///
/// Free-tier locked-history footer dropped: the Flutter example has no
/// license gating (everything is Pro).
class NetworkListScreen extends StatefulWidget {
  const NetworkListScreen({
    super.key,
    required this.paused,
    required this.filter,
    required this.onEventPress,
  });

  final bool paused;
  final NetworkFilter filter;
  final ValueChanged<NetworkCaptureEvent> onEventPress;

  @override
  State<NetworkListScreen> createState() => _NetworkListScreenState();
}

class _NetworkListScreenState extends State<NetworkListScreen> {
  void Function()? _unsubscribe;
  void Function()? _unsubscribeSaved;
  void Function()? _unsubscribeRules;
  late List<NetworkCaptureEvent> _events;

  @override
  void initState() {
    super.initState();
    _events = NetworkEventStore.instance.events;
    _unsubscribe = NetworkEventStore.instance.subscribe(_onStoreChange);
    _unsubscribeSaved = NetworkSavedStore.instance.subscribe(() {
      if (mounted) setState(() {});
    });
    _unsubscribeRules = OverrideRulesStore.instance.subscribe(() {
      if (mounted) setState(() {});
    });
    IgnoredPatternsStore.instance.addListener(_onPatternsChange);
  }

  void _onStoreChange() {
    if (!mounted) return;
    // Paused freezes the stream, but store clears are honored so a frozen
    // list can't show deleted events (RN onClear parity).
    if (widget.paused && NetworkEventStore.instance.events.isNotEmpty) return;
    setState(() => _events = NetworkEventStore.instance.events);
  }

  void _onPatternsChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(NetworkListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resuming from pause catches up immediately (RN: subscribeToEvents
    // replays on resubscribe).
    if (oldWidget.paused && !widget.paused) {
      _events = NetworkEventStore.instance.events;
    }
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _unsubscribeSaved?.call();
    _unsubscribeRules?.call();
    IgnoredPatternsStore.instance.removeListener(_onPatternsChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final afterPatterns = applyIgnoredPatterns(
      _events,
      IgnoredPatternsStore.instance.patterns,
    );
    final visibleEvents = filterNetworkEvents(afterPatterns, widget.filter);
    final isEnabled = !widget.paused;
    final savedState = NetworkSavedStore.instance.state;
    final sections = _sections(visibleEvents, savedState);

    return Column(
      children: [
        if (!isEnabled)
          Container(
            margin: const EdgeInsets.only(left: 12, right: 12, top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MacOSColors.warningBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MacOSColors.warning.hexAlpha(0x20)),
            ),
            child: const Row(
              spacing: 8,
              children: [
                BuoyGlyph(
                  BuoyIcons.power,
                  size: 14,
                  color: MacOSColors.warning,
                ),
                Expanded(
                  child: Text(
                    'Network interception is disabled',
                    style: TextStyle(fontSize: 11, color: MacOSColors.warning),
                  ),
                ),
              ],
            ),
          ),
        // The strips render OUTSIDE the scrolling list, exactly as RN does.
        // Merging them into it would mean sentinel rows in the builder and a
        // section boundary that moves as events arrive; keeping them separate
        // also makes "pins ignore the filters" fall out for free, because
        // neither strip is ever handed the filter.
        if (sections.overridden.isNotEmpty)
          _OverriddenSection(
            events: sections.overridden,
            paused: !OverrideRulesStore.instance.enabled,
            onEventPress: widget.onEventPress,
            onTogglePaused: () => OverrideRulesStore.instance.setEnabled(
              !OverrideRulesStore.instance.enabled,
            ),
            savedState: savedState,
          ),
        if (sections.pinned.isNotEmpty)
          _PinnedSection(
            events: sections.pinned,
            onEventPress: widget.onEventPress,
            onUnpinAll: NetworkSavedStore.instance.clearPinned,
            savedState: savedState,
          ),
        Expanded(
          child: sections.rest.isNotEmpty
              ? ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: sections.rest.length,
                  itemBuilder: (context, index) =>
                      _row(sections.rest[index], savedState),
                )
              // Nothing left to list, but the strips still say something — so
              // an empty state would be claiming there's no traffic when the
              // rows above it are traffic.
              : sections.pinned.isNotEmpty || sections.overridden.isNotEmpty
              ? const SizedBox.shrink()
              : _EmptyState(
                  isEnabled: isEnabled,
                  // Only when the list is EMPTY, so it never competes with
                  // actual rows: "No network events" would otherwise be flatly
                  // wrong when every request captured was an image.
                  imagesHidden:
                      widget.filter.hideImages &&
                      afterPatterns.any(isImageEvent),
                ),
        ),
      ],
    );
  }

  /// Split the visible list into its three bands.
  ///
  /// OVERRIDDEN sits above PINNED because a stale override EXPLAINS a bug,
  /// whereas a pin only marks one. A request that is both appears once, in the
  /// louder band.
  ({
    List<NetworkCaptureEvent> overridden,
    List<NetworkCaptureEvent> pinned,
    List<NetworkCaptureEvent> rest,
  })
  _sections(List<NetworkCaptureEvent> events, NetworkSavedState savedState) {
    final split = splitPinned(
      events,
      savedState.pinnedEvents,
      savedState.pinnedLiveIds,
    );

    // Matched against the RULES, not the override mark, so a request captured
    // before the rule existed hoists immediately instead of waiting for the
    // endpoint to be called again. Paused rules still populate the strip —
    // that's how you find the thing you paused in order to resume it.
    final activeRules = [
      for (final rule in OverrideRulesStore.instance.rules)
        if (rule.enabled && !isSpent(rule)) rule,
    ];
    final overridden = activeRules.isEmpty
        ? const <NetworkCaptureEvent>[]
        : [
            for (final event in [...split.pinned, ...split.rest])
              if (event.override != null ||
                  activeRules.any(
                    (rule) => ruleMatches(rule, event.url, event.method),
                  ))
                event,
          ];
    final overriddenIds = {for (final event in overridden) event.id};

    return (
      overridden: overridden,
      pinned: [
        for (final event in split.pinned)
          if (!overriddenIds.contains(event.id)) event,
      ],
      rest: [
        for (final event in split.rest)
          if (!overriddenIds.contains(event.id)) event,
      ],
    );
  }

  Widget _row(NetworkCaptureEvent event, NetworkSavedState savedState) {
    final flags = flagsForEventId(savedState, event.id);
    return NetworkEventRow(
      key: ValueKey(event.id),
      event: event,
      onTap: widget.onEventPress,
      // Long-press pins on the live list — RN's `handleLongPress`.
      onLongPress: (e) => NetworkSavedStore.instance.togglePin(e),
      pinned: flags.pinned,
      saved: flags.saved,
    );
  }
}

/// Ports RN's `PinnedSection`.
///
/// Separated from the live list by a real rule, not just space: these rows do
/// NOT obey the filters, and the boundary is what tells you why a request you
/// just filtered out is still on screen.
class _PinnedSection extends StatelessWidget {
  const _PinnedSection({
    required this.events,
    required this.onEventPress,
    required this.onUnpinAll,
    required this.savedState,
  });

  final List<NetworkCaptureEvent> events;
  final ValueChanged<NetworkCaptureEvent> onEventPress;
  final VoidCallback onUnpinAll;
  final NetworkSavedState savedState;

  @override
  Widget build(BuildContext context) {
    return Container(
      // RN pinnedSection: bottom rule + paddingBottom 4. No fill, no radius.
      padding: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MacOSColors.borderDefault)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // RN pinnedHeader: padH 20 / padTop 10 / padBottom 6 / gap 6.
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(
              children: [
                const BuoyGlyph(
                  BuoyIcons.pin,
                  size: 11,
                  color: MacOSColors.info,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'PINNED · ${events.length}',
                    // RN pinnedTitle: 10 / w700 / tracking 0.6 / mono / info.
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      fontFamily: 'monospace',
                      color: MacOSColors.info,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Unpin all',
                  child: TouchableOpacity(
                    activeOpacity: 0.2,
                    onTap: onUnpinAll,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        'Unpin all',
                        style: TextStyle(
                          fontSize: 10,
                          color: MacOSColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final event in events)
            NetworkEventRow(
              key: ValueKey(event.id),
              event: event,
              onTap: onEventPress,
              onLongPress: (e) => NetworkSavedStore.instance.togglePin(e),
              pinned: true,
              saved: savedState.savedLiveIds.contains(event.id),
            ),
        ],
      ),
    );
  }
}

/// Ports RN's `OverriddenSection`.
///
/// An overridden request is the one thing in this list that isn't true — the
/// app got something the server never sent. That has to be impossible to miss,
/// and a glyph on a row twenty scroll-positions down isn't.
///
/// The header button is PAUSE, not "Manage". Force the failure, check the UI,
/// turn it off, check the happy path, turn it back on — by far the most
/// repeated action in a testing session, and it used to cost a trip to another
/// screen each way.
class _OverriddenSection extends StatelessWidget {
  const _OverriddenSection({
    required this.events,
    required this.paused,
    required this.onEventPress,
    required this.onTogglePaused,
    required this.savedState,
  });

  final List<NetworkCaptureEvent> events;
  final bool paused;
  final ValueChanged<NetworkCaptureEvent> onEventPress;
  final VoidCallback onTogglePaused;
  final NetworkSavedState savedState;

  @override
  Widget build(BuildContext context) {
    final accent = paused ? MacOSColors.textMuted : MacOSColors.warning;
    return Container(
      // RN overriddenSection: a full-bleed tinted band with a bottom rule —
      // no radius, no margin, no border on the other three sides.
      decoration: BoxDecoration(
        color: paused
            ? MacOSColors.backgroundCard
            : MacOSColors.warningBackground,
        border: Border(
          bottom: BorderSide(
            color: paused
                ? MacOSColors.borderDefault
                : MacOSColors.warning.hexAlpha(0x44),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // RN overriddenHeader: padH 12 / padTop 8 / padBottom 4 / gap 6.
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                BuoyGlyph(BuoyIcons.flaskConical, size: 11, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    paused
                        ? 'PAUSED · ${events.length}'
                        : 'OVERRIDDEN · ${events.length}',
                    // RN overriddenTitle: 10 / w700 / tracking 0.8.
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: accent,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: paused ? 'Resume overrides' : 'Pause overrides',
                  child: TouchableOpacity(
                    activeOpacity: 0.2,
                    onTap: onTogglePaused,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        paused ? 'Resume' : 'Pause',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final event in events)
            NetworkEventRow(
              key: ValueKey(event.id),
              event: event,
              onTap: onEventPress,
              onLongPress: (e) => NetworkSavedStore.instance.togglePin(e),
              pinned: savedState.pinnedLiveIds.contains(event.id),
              saved: savedState.savedLiveIds.contains(event.id),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isEnabled, this.imagesHidden = false});

  final bool isEnabled;

  /// Every captured request was an image, and the image filter is on.
  final bool imagesHidden;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const BuoyGlyph(BuoyIcons.globe, size: 32, color: MacOSColors.textMuted),
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              'No network events',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: MacOSColors.textPrimary,
              ),
            ),
          ),
          Text(
            imagesHidden
                ? 'Only image requests so far — turn off Hide images in '
                      'Filters to see them'
                : isEnabled
                ? 'Network requests will appear here'
                : 'Enable interception to start capturing',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: MacOSColors.textMuted),
          ),
        ],
      ),
    );
  }
}
