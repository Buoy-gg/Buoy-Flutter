import 'package:flutter/material.dart';

import '../storage.dart';
import '../tool.dart';
import 'buoy_theme.dart';
import 'touchable_opacity.dart';

/// Flutter port of RN's `MinimizedToolsStack` + `ExpandablePopover` — the
/// collapsible column of restorable tool icons docked directly above the
/// floating bubble's drag handle (so it drags around with the bubble).
///
/// Collapsed: a small "peek" tab (chevron-up + count badge) that connects
/// flush to the top of the handle. Tapping it expands the column upward to
/// reveal one 32px icon per minimized tool plus a collapse chevron; expanded
/// state persists across launches (RN `@react_buoy_minimized_stack_expanded`).
/// Tapping an icon restores that tool.
///
/// Deviation from RN: no idle "glitch" shimmer on the icons (cosmetic only).
class MinimizedToolsStack extends StatefulWidget {
  const MinimizedToolsStack({
    super.key,
    required this.tools,
    required this.storage,
    required this.onRestore,
    this.width = _toolbarWidth,
  });

  final List<BuoyTool> tools;
  final BuoyStorage storage;
  final void Function(BuoyTool tool) onRestore;
  final double width;

  // RN MinimizedToolsStack constants.
  static const double _toolbarWidth = 32;
  static const double peekHeight = 28;
  static const double _toolItemSize = 32;
  static const double _iconGap = 6;
  static const double _toolbarPadding = 8;
  static const double _collapseButtonSize = 24;

  /// RN expandedHeight formula (MinimizedToolsStack.tsx).
  static double expandedHeightFor(int count) =>
      _toolbarPadding +
      count * _toolItemSize +
      (count - 1) * _iconGap +
      _iconGap +
      _collapseButtonSize +
      4;

  @override
  State<MinimizedToolsStack> createState() => _MinimizedToolsStackState();
}

class _MinimizedToolsStackState extends State<MinimizedToolsStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  bool _expanded = false;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    widget.storage.loadMinimizedStackExpanded().then((value) {
      if (!mounted) return;
      setState(() {
        _expanded = value;
        _restored = true;
        _progress.value = value ? 1 : 0;
      });
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _expanded = true);
    _progress.animateTo(1, curve: Curves.easeOut);
    widget.storage.saveMinimizedStackExpanded(true);
  }

  Future<void> _collapse() async {
    await _progress.animateBack(0, curve: Curves.easeOut);
    if (mounted) setState(() => _expanded = false);
    widget.storage.saveMinimizedStackExpanded(false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_restored || widget.tools.isEmpty) return const SizedBox.shrink();
    final count = widget.tools.length;
    final expandedHeight = MinimizedToolsStack.expandedHeightFor(count);

    // The widget always reserves its full expanded height and anchors content
    // to the BOTTOM (nearest the bubble). Collapsed, only the 28px peek shows
    // at the bottom and the space above is transparent (taps fall through);
    // expanding grows the column up into that already-reserved space, so the
    // bubble never shifts. Everything stays inside these bounds, so it all
    // hit-tests (an earlier Clip.none + negative offset painted but was
    // untappable). Material keeps the count Text off the debug yellow-underline
    // fallback when placed outside the bubble's own Material.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: widget.width,
        height: expandedHeight,
        child: Stack(
          children: [
            // Expanded column — bottom-aligned, height animates 0 → full.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: _progress.value,
                    child: child,
                  ),
                ),
                child: _expandedColumn(expandedHeight),
              ),
            ),
            // Collapsed peek tab pinned at the bottom, fades as it expands.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: _expanded,
                child: FadeTransition(
                  opacity: Tween<double>(begin: 1, end: 0).animate(_progress),
                  child: _peekTab(count),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration get _panelDecoration => const BoxDecoration(
    color: BuoyTheme.card,
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(6),
      topRight: Radius.circular(6),
    ),
    border: Border(
      top: BorderSide(color: BuoyTheme.border),
      left: BorderSide(color: BuoyTheme.border),
      right: BorderSide(color: BuoyTheme.border),
    ),
  );

  Widget _peekTab(int count) {
    return TouchableOpacity(
      activeOpacity: 0.8,
      onTap: _expand,
      child: Container(
        height: MinimizedToolsStack.peekHeight,
        decoration: _panelDecoration,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.keyboard_arrow_up,
              size: 14,
              color: BuoyTheme.muted,
            ),
            if (count > 1)
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: BuoyTheme.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _expandedColumn(double height) {
    return Container(
      height: height,
      decoration: _panelDecoration,
      padding: const EdgeInsets.only(top: MinimizedToolsStack._toolbarPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Newest on top (RN reverses the list before mapping).
          for (final tool in widget.tools.reversed) ...[
            _toolButton(tool),
            const SizedBox(height: MinimizedToolsStack._iconGap),
          ],
          TouchableOpacity(
            activeOpacity: 0.6,
            onTap: _collapse,
            child: const SizedBox(
              width: double.infinity,
              height: MinimizedToolsStack._collapseButtonSize,
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: BuoyTheme.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(BuoyTool tool) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: () => widget.onRestore(tool),
      child: Semantics(
        button: true,
        label: 'Restore ${tool.name}',
        child: SizedBox(
          width: MinimizedToolsStack._toolItemSize,
          height: MinimizedToolsStack._toolItemSize,
          child: Center(child: Icon(tool.icon, size: 18, color: tool.color)),
        ),
      ),
    );
  }
}
