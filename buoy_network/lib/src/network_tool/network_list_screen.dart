import 'package:flutter/material.dart';

import '../network_capture.dart';
import 'ignored_patterns.dart';
import 'macos_colors.dart';
import 'network_event_row.dart';
import 'network_filter.dart';

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
  late List<NetworkCaptureEvent> _events;

  @override
  void initState() {
    super.initState();
    _events = NetworkEventStore.instance.events;
    _unsubscribe = NetworkEventStore.instance.subscribe(_onStoreChange);
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
    IgnoredPatternsStore.instance.removeListener(_onPatternsChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleEvents = filterNetworkEvents(
      applyIgnoredPatterns(_events, IgnoredPatternsStore.instance.patterns),
      widget.filter,
    );
    final isEnabled = !widget.paused;

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
                Icon(
                  Icons.power_settings_new,
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
        Expanded(
          child: visibleEvents.isEmpty
              ? _EmptyState(isEnabled: isEnabled)
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: visibleEvents.length,
                  itemBuilder: (context, index) => NetworkEventRow(
                    event: visibleEvents[index],
                    onTap: widget.onEventPress,
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isEnabled});

  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.public, size: 32, color: MacOSColors.textMuted),
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
            isEnabled
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
