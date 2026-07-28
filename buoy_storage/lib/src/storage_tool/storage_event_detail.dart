/// Ports packages/storage/src/storage/components/StorageEventDetailContent.tsx
/// (+ its shared-ui EventHistoryViewer composition).
///
/// A key's event history detail: UNDO/JUMP/COPY time-travel actions (async
/// events only), a CURRENT VALUE / DIFF VIEW toggle ([ViewToggleCards]), the
/// diff view with TREE/SPLIT sub-tabs ([DiffModeTabs]), a PREV|CUR [CompareBar]
/// with any-to-any navigation, [TreeDiffViewer]/[SplitDiffViewer] rendering, and
/// a shared [EventStepperFooter]. View + diff-mode choices persist under the RN
/// keys (`storage.detailView` / `storage.diffViewerMode`).
///
/// Deviations (precedent-aligned): the footer renders inline (Flutter's JsModal
/// has no footer slot — RN passes it through the modal's `footer` prop); UNDO/
/// JUMP ship unlocked (everything Pro in the Flutter example — network
/// precedent); the diff viewers get a bounded height with their own inner
/// scroll instead of RN's whole-page `scrollDiffSection` (buoy_riverpod
/// precedent).
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_capture.dart';
import 'storage_action_helpers.dart';
import 'storage_models.dart';
import 'storage_time_travel.dart';

class StorageEventDetail extends StatefulWidget {
  const StorageEventDetail({
    super.key,
    required this.conversation,
    this.selectedEventIndex,
    this.onEventIndexChange,
    this.applySafeAreaInset = true,
  });

  final StorageConversation conversation;

  /// Selected event index in chronological (oldest-first) order. Null →
  /// uncontrolled: the widget steps its own internal index (events-timeline
  /// single-event usage). RN's props default the same way.
  final int? selectedEventIndex;
  final ValueChanged<int>? onEventIndexChange;

  /// Whether the stepper footer reserves safe-area bottom padding. True while
  /// the modal is docked as a bottom sheet (pinned to the screen edge); false
  /// in floating mode, where the inset would just be dead space.
  final bool applySafeAreaInset;

  @override
  State<StorageEventDetail> createState() => _StorageEventDetailState();
}

/// Compare-bar index for "the state before the oldest event" (RN
/// `ORIGIN_INDEX`).
///
/// Not an event — it's reconstructed from that event's own `prevValue`, which
/// every write records. Without it a key's first event had nothing to diff
/// against and both panes showed the same value.
const int _originIndex = -1;

/// What the state before the oldest event actually is.
enum _OriginKind { prior, absent, scanned }

class _OriginCopy {
  const _OriginCopy(this.label, this.timestamp, this.relativeTime, this.badge);
  final String label;
  final String timestamp;
  final String relativeTime;
  final String badge;
}

/// Compare-bar copy for each origin state (RN `ORIGIN_LABELS` — keep in sync).
const Map<_OriginKind, _OriginCopy> _originLabels = {
  _OriginKind.prior:
      _OriginCopy('BEFORE #1', 'value before first event', 'not captured', 'PRIOR'),
  _OriginKind.absent:
      _OriginCopy('NO PRIOR VALUE', 'key did not exist', 'created here', 'ABSENT'),
  _OriginKind.scanned:
      _OriginCopy('ALREADY PRESENT', 'value found at startup', 'not a write', 'SCANNED'),
};

class _StorageEventDetailState extends State<StorageEventDetail> {
  final _keys = devToolsStorageKeys.storage;

  // Default to the diff + split view on first open; a saved preference (loaded
  // in [_loadPreferences]) overrides these, and the single-event case falls
  // back to the current view via `effectiveView` in [build].
  String _activeView = 'diff';
  String _diffMode = 'split';
  int _internalIndex = 0;
  int _leftIndex = 0;
  int _rightIndex = 0;

  List<StorageEvent> get _ascEvents {
    final events = [...widget.conversation.events]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return events;
  }

  int get _total => widget.conversation.events.length;

  int get _selectedIndex =>
      (widget.selectedEventIndex ?? _internalIndex).clamp(0, _total - 1);

  @override
  void initState() {
    super.initState();
    _syncCompareIndices();
    _loadPreferences();
  }

  @override
  void didUpdateWidget(StorageEventDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedEventIndex != oldWidget.selectedEventIndex ||
        widget.conversation.events.length !=
            oldWidget.conversation.events.length) {
      _syncCompareIndices();
    }
  }

  /// RN's "keep compare indices synced to selection" effect: right follows the
  /// selection, left defaults to the event just before it.
  void _syncCompareIndices() {
    final right = _selectedIndex;
    _rightIndex = right;
    // One step past event #1 is [_originIndex] — the state it overwrote — so the
    // oldest event still has something to diff against.
    _leftIndex = right - 1;
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final view = prefs.getString(_keys.detailView());
      if (view == 'current' || view == 'diff') _activeView = view!;
      final mode = prefs.getString(_keys.diffViewerMode());
      if (mode == 'tree' || mode == 'split') _diffMode = mode!;
    });
  }

  Future<void> _save(String key, String value) async {
    (await SharedPreferences.getInstance()).setString(key, value);
  }

  void _setView(String view) {
    setState(() => _activeView = view);
    _save(_keys.detailView(), view);
  }

  void _setDiffMode(String mode) {
    setState(() => _diffMode = mode);
    _save(_keys.diffViewerMode(), mode);
  }

  void _changeIndex(int index) {
    final clamped = index.clamp(0, _total - 1);
    if (widget.onEventIndexChange != null) {
      widget.onEventIndexChange!(clamped);
    } else {
      setState(() {
        _internalIndex = clamped;
        _syncCompareIndices();
      });
    }
  }

  // ── Time-travel actions ────────────────────────────────────────────────

  Future<void> _handleUndo(StorageEvent event) async {
    try {
      await undoOperation(event);
    } catch (_) {
      // Silent fail (RN parity).
    }
  }

  Future<void> _handleJump(StorageEvent event) async {
    final asyncEvents =
        [for (final e in _ascEvents) if (e.storageType == 'async') e];
    final targetIndex = asyncEvents.indexWhere((e) => e.id == event.id);
    if (targetIndex == -1) return;
    try {
      await jumpToState(asyncEvents, targetIndex);
    } catch (_) {
      // Silent fail (RN parity).
    }
  }

  Future<void> _handleCopy(StorageEvent event) async {
    final data = {
      'action': event.action,
      'timestamp': event.timestamp.toIso8601String(),
      'data': {
        'key': event.key,
        if (event.value != null) 'value': event.value,
        if (event.prevValue != null) 'prevValue': event.prevValue,
      },
    };
    String text;
    try {
      text = const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      text = '$data';
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  // ── Build ──────────────────────────────────────────────────────────────

  static String _formatTimeWithMs(DateTime d) {
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${p(d.hour)}:${p(d.minute)}:${p(d.second)}.${p(d.millisecond, 3)}';
  }

  static String _typeOf(Object? v) {
    if (v == null) return 'null';
    if (v is List) return 'array';
    if (v is Map) return 'object';
    if (v is bool) return 'boolean';
    if (v is num) return 'number';
    if (v is String) return 'string';
    return 'undefined';
  }

  Widget _actionBadge(String action, {bool small = false}) {
    final color = getActionColor(action);
    return Container(
      padding: small
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 1)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x20),
        borderRadius: BorderRadius.circular(small ? 3 : 4),
      ),
      child: Text(
        translateStorageAction(action),
        style: TextStyle(
          fontSize: small ? 8 : 9,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: small ? 0 : 0.3,
          color: color,
        ),
      ),
    );
  }

  /// The origin state isn't an action, so it gets a neutral chip rather than a
  /// coloured action badge.
  Widget _mutedBadge(String text) {
    final color = MacOSColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x20),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          color: color,
        ),
      ),
    );
  }

  EventDisplayInfo _sideInfo(int index, StorageEvent event) => EventDisplayInfo(
        index: index,
        label: '#${index + 1} / $_total',
        timestamp: _formatTimeWithMs(event.timestamp),
        relativeTime:
            formatRelativeTime(event.timestamp.millisecondsSinceEpoch),
        badge: _actionBadge(event.action, small: true),
      );

  /// Compare-bar info for [_originIndex] (RN's origin branch of
  /// `leftEventInfo`).
  EventDisplayInfo _originSideInfo(_OriginKind kind) {
    final copy = _originLabels[kind]!;
    return EventDisplayInfo(
      index: _originIndex,
      label: copy.label,
      timestamp: copy.timestamp,
      relativeTime: copy.relativeTime,
      badge: _mutedBadge(copy.badge),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _ascEvents;
    final total = events.length;
    final selectedIndex = _selectedIndex;
    final event = events[selectedIndex];
    final isAsyncEvent = event.storageType == 'async';
    // A single event still diffs — against the value it overwrote — so the only
    // case with nothing to show is no events at all.
    final diffDisabled = total < 1;
    final effectiveView = diffDisabled ? 'current' : _activeView;

    return Column(
      children: [
        if (isAsyncEvent) _actionRow(event),
        ViewToggleCards(
          activeView: effectiveView,
          onViewChange: _setView,
          currentLabel: 'CURRENT VALUE',
          currentDescription: 'View the current stored value',
          currentIcon: BuoyIcons.database,
          diffLabel: 'DIFF VIEW',
          diffDescription: 'Compare changes between versions',
          diffIcon: BuoyIcons.gitBranch,
          diffDisabled: diffDisabled,
        ),
        Expanded(
          child: effectiveView == 'diff'
              ? _diffView(events, total)
              : _currentView(event),
        ),
        EventStepperFooter(
          currentIndex: selectedIndex,
          totalItems: total,
          onPrevious: () => _changeIndex(selectedIndex - 1),
          onNext: () => _changeIndex(selectedIndex + 1),
          itemLabel: 'Event',
          subtitle: formatRelativeTime(event.timestamp.millisecondsSinceEpoch),
          applySafeAreaInset: widget.applySafeAreaInset,
        ),
      ],
    );
  }

  /// UNDO / JUMP / COPY row (RN StorageEventActionButton strip; async only).
  Widget _actionRow(StorageEvent event) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: BuoyColors.card,
        border: Border(bottom: BorderSide(color: BuoyColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionButton(
            text: 'UNDO',
            color: BuoyColors.info,
            disabled: !canUndo(event),
            onTap: () => _handleUndo(event),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            text: 'JUMP',
            color: BuoyColors.warning,
            onTap: () => _handleJump(event),
          ),
          const SizedBox(width: 8),
          _ActionButton(
            text: 'COPY',
            color: BuoyColors.primary,
            onTap: () => _handleCopy(event),
          ),
        ],
      ),
    );
  }

  /// The CURRENT VALUE card (action badge + type badge + [DataViewer]).
  Widget _currentView(StorageEvent event) {
    final valueToShow = event.value ?? widget.conversation.currentValue;
    final parsed = parseValue(valueToShow);
    final valueType = _typeOf(parsed).toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CURRENT VALUE',
                  style: TextStyle(
                    fontSize: 10,
                    color: MacOSColors.textSecondary,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    _actionBadge(event.action),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: MacOSColors.backgroundInput,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        valueType,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: MacOSColors.textMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            DataViewer(
              data: parsed,
              showTypeFilter: true,
              initialExpanded: true,
            ),
          ],
        ),
      ),
    );
  }

  /// The DIFF view: TREE/SPLIT sub-tabs + PREV|CUR compare bar with any-to-any
  /// navigation + the selected diff renderer.
  Widget _diffView(List<StorageEvent> events, int total) {
    final leftIndex = _leftIndex.clamp(_originIndex, total - 1);
    final rightIndex = _rightIndex.clamp(0, total - 1);
    final isOriginLeft = leftIndex == _originIndex;
    final rightEvent = events[rightIndex];
    final currentValue = parseValue(rightEvent.value);

    // Every write records the value it overwrote (for time travel), so even the
    // very first event can be diffed against what was actually there. Three
    // distinct origins, and conflating them would misinform:
    //   prior   — the write replaced a real value (including `[]`, `''`, `null`)
    //   absent  — the write created the key; there was nothing before it
    //   scanned — not a write at all, just the startup snapshot of a key that
    //             already existed, so nothing changed at this event
    final originKind = rightEvent.initialScan
        ? _OriginKind.scanned
        : rightEvent.prevValue == null
            ? _OriginKind.absent
            : _OriginKind.prior;

    final originValue = switch (originKind) {
      _OriginKind.absent => absentValue,
      // A scanned key was already holding the event's own value, so diffing
      // against it correctly reports no change.
      _OriginKind.scanned => parseValue(rightEvent.value),
      _OriginKind.prior => parseValue(rightEvent.prevValue),
    };

    final previousValue = isOriginLeft
        ? originValue
        : parseValue(events[leftIndex].value);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      child: Column(
        children: [
          DiffModeTabs(
            tabs: const [
              DiffModeTab(key: 'tree', label: 'TREE VIEW'),
              DiffModeTab(key: 'split', label: 'SPLIT VIEW'),
            ],
            activeTab: _diffMode,
            onTabChange: _setDiffMode,
          ),
          CompareBar(
            leftEvent: isOriginLeft
                ? _originSideInfo(originKind)
                : _sideInfo(leftIndex, events[leftIndex]),
            rightEvent: _sideInfo(rightIndex, rightEvent),
            showNavigation: true,
            onLeftPrevious: () => setState(() => _leftIndex = leftIndex - 1),
            onLeftNext: () => setState(() => _leftIndex = leftIndex + 1),
            onRightPrevious: () => setState(() => _rightIndex = rightIndex - 1),
            onRightNext: () => setState(() => _rightIndex = rightIndex + 1),
            canLeftPrevious: leftIndex > _originIndex,
            canLeftNext: leftIndex < rightIndex - 1,
            canRightPrevious: rightIndex > leftIndex + 1,
            canRightNext: rightIndex < total - 1,
          ),
          SizedBox(
            height: 360,
            child: _diffMode == 'split'
                ? SplitDiffViewer(
                    oldValue: previousValue,
                    newValue: currentValue,
                    theme: devToolsDefaultTheme,
                    options: const SplitDiffViewerOptions(),
                    height: 360,
                  )
                : TreeDiffViewer(
                    oldValue: previousValue,
                    newValue: currentValue,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Ports StorageEventActionButton.tsx: dot + label chip (RN numerics: height
/// 25, minWidth 70, radius 6, padH 12, dot 5px). The Pro lock state is dropped
/// (everything Pro in the Flutter example — network precedent).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.text,
    required this.color,
    required this.onTap,
    this.disabled = false,
  });

  final String text;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final fg = disabled ? BuoyColors.textMuted : color;
    final button = Container(
      height: 25,
      constraints: const BoxConstraints(minWidth: 70),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: disabled
            ? BuoyColors.textMuted.hexAlpha(0x1A)
            : color.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: disabled
              ? BuoyColors.textMuted.hexAlpha(0x33)
              : color.hexAlpha(0x40),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: fg,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
              color: fg,
            ),
          ),
        ],
      ),
    );
    if (disabled) return Opacity(opacity: 0.5, child: button);
    return TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: button);
  }
}
