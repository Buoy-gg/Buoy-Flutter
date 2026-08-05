/// Ports packages/network/src/network/components/NetworkSavedScreen.tsx — the
/// network tool's favorites list.
///
/// Everything here reads from the persisted saved store, never from the live
/// event store. That is the whole point of the screen: these requests survive a
/// Clear, the 500-event cap, and an app restart, so a failure you kept is still
/// here tomorrow.
///
/// Rows are the same row component the live list uses, so a saved request looks
/// exactly like the request it was. Long-press here UNSAVES rather than pins —
/// in this list "get rid of it" is the action the row affords, and pinning is
/// still available from the detail header.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../../network_capture.dart';
import '../network_event_row.dart';
import 'network_saved_store.dart';
import 'pinned_split.dart';

class NetworkSavedScreen extends StatefulWidget {
  const NetworkSavedScreen({
    super.key,
    required this.onEventPress,
    this.search,
    this.onSearchChange,
  });

  final ValueChanged<NetworkCaptureEvent> onEventPress;

  /// Controlled search box. The modal owns it because the detail screen's
  /// prev/next footer steps through THIS list.
  final String? search;
  final ValueChanged<String>? onSearchChange;

  @override
  State<NetworkSavedScreen> createState() => _NetworkSavedScreenState();
}

class _NetworkSavedScreenState extends State<NetworkSavedScreen> {
  void Function()? _unsubscribe;
  late final TextEditingController _searchController;
  String _localSearch = '';

  bool get _controlled =>
      widget.search != null && widget.onSearchChange != null;
  String get _search => _controlled ? widget.search! : _localSearch;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: _search);
    _searchController.addListener(() {
      final text = _searchController.text;
      if (text == _search) return;
      if (_controlled) {
        widget.onSearchChange!(text);
      } else {
        setState(() => _localSearch = text);
      }
    });
    _unsubscribe = NetworkSavedStore.instance.subscribe(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = NetworkSavedStore.instance;
    final state = store.state;
    final filtered = selectSavedEvents(state.savedRecords, _search);
    final hasSaves = state.savedRecords.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(state.savedRecords.length, store),
        if (hasSaves) _searchRow(),
        Expanded(
          child: !hasSaves
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => NetworkEventRow(
                    event: filtered[index],
                    onTap: widget.onEventPress,
                    // Long-press UNSAVES here — the list's own affordance.
                    onLongPress: (event) => store.toggleSave(event),
                    saved: true,
                    pinned: state.pinnedLiveIds.contains(filtered[index].id),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _toolbar(int count, NetworkSavedStore store) {
    return Padding(
      // RN toolbar: padH 20 / padTop 10 / padBottom 6 / gap 6.
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          const BuoyGlyph(
            BuoyIcons.bookmark,
            size: 11,
            color: MacOSColors.debug,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'SAVED · $count',
              // RN toolbarTitle: 10 / w700 / tracking 0.6 / mono / debug.
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                fontFamily: 'monospace',
                color: MacOSColors.debug,
              ),
            ),
          ),
          TouchableOpacity(
            activeOpacity: count == 0 ? 1.0 : 0.2,
            onTap: count == 0 ? null : store.clearSaved,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Clear all',
                style: TextStyle(
                  fontSize: 10,
                  color: count == 0
                      ? MacOSColors.textMuted.withValues(alpha: 0.4)
                      : MacOSColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Container(
      // RN searchRow: marginH 12 / marginBottom 8 / padH 10 / padV 5 / r10.
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Row(
        children: [
          const BuoyGlyph(
            BuoyIcons.search,
            size: 13,
            color: MacOSColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchController,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                fontSize: 13,
                color: MacOSColors.textPrimary,
              ),
              cursorColor: MacOSColors.info,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 2),
                hintText: 'Search saved requests…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: MacOSColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: [
          BuoyGlyph(BuoyIcons.bookmark, size: 32, color: MacOSColors.textMuted),
          Padding(
            padding: EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              'No saved requests',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: MacOSColors.textPrimary,
              ),
            ),
          ),
          Text(
            'Open a request and tap the bookmark to keep it here — saved '
            'requests survive Clear and app restarts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: MacOSColors.textMuted),
          ),
        ],
      ),
    );
  }
}
