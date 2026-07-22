import 'package:flutter/material.dart';

import '../core/bubble_state.dart';
import '../core/constants.dart';
import '../storage.dart';
import '../tool.dart';
import 'buoy_theme.dart';
import 'minimized_tools_stack.dart';

/// The draggable floating bubble — Flutter port of the RN package's
/// `FloatingTools` + `DraggableHeader`.
///
/// Gestures use a raw [Listener] with the RN 5 px tap-vs-drag threshold
/// (Flutter's pan recognizer waits ~18 px of touch slop, which would make the
/// bubble feel laggy compared to mobile). All position decisions live in
/// [BubbleStateMachine]; this widget only binds gestures, animation, and
/// persistence.
///
/// Must be placed directly inside the root Stack: it renders a [Positioned]
/// driven by a ValueListenable, so dragging repaints only the bubble — never
/// the app subtree.
class FloatingBubble extends StatefulWidget {
  const FloatingBubble({
    super.key,
    required this.storage,
    required this.pushToSide,
    required this.onOpenDial,
    this.minimizedTools = const [],
    required this.onRestoreMinimized,
  });

  final BuoyStorage storage;

  /// When true (dial or a tool is open) the bubble tucks into the hidden
  /// slot, restoring when it goes false again.
  final bool pushToSide;

  final VoidCallback onOpenDial;

  /// Tools minimized out of their modal — rendered as a restorable stack
  /// docked above the bubble's drag handle (moves with the bubble).
  final List<BuoyTool> minimizedTools;

  final void Function(BuoyTool tool) onRestoreMinimized;

  @override
  State<FloatingBubble> createState() => _FloatingBubbleState();
}

class _FloatingBubbleState extends State<FloatingBubble>
    with SingleTickerProviderStateMixin {
  BubbleStateMachine? _machine;
  final _position = ValueNotifier<Offset>(Offset.zero);
  final _bubbleKey = GlobalKey();

  late final AnimationController _mover;
  late final CurvedAnimation _moverCurve;
  Tween<Offset>? _moveTween;
  BubblePoint? _saveAfterMove;

  bool _initialized = false;
  bool _dragging = false;
  bool _pushedBySide = false;

  int? _activePointer;
  Offset _pointerDownGlobal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _mover = AnimationController(vsync: this, duration: hideShowDuration);
    _moverCurve = CurvedAnimation(parent: _mover, curve: Curves.easeInOut);
    _mover.addListener(() {
      final tween = _moveTween;
      if (tween != null) _position.value = tween.evaluate(_moverCurve);
    });
    _mover.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      final target = _saveAfterMove;
      _saveAfterMove = null;
      if (target != null) {
        widget.storage.saveBubblePosition(target.x, target.y);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewPaddingOf(context);

    final machine = _machine;
    if (machine == null) {
      _machine = BubbleStateMachine(
        screenWidth: size.width,
        screenHeight: size.height,
        insetLeft: insets.left,
        insetTop: insets.top,
        insetBottom: insets.bottom,
      );
      _restorePosition();
      return;
    }

    // Rotation / resize: re-clamp against the new metrics.
    final corrected = machine.setScreenMetrics(
      width: size.width,
      height: size.height,
      left: insets.left,
      top: insets.top,
      bottom: insets.bottom,
    );
    if (corrected != null && !_dragging) {
      _mover.stop();
      _position.value = Offset(corrected.x, corrected.y);
    }
  }

  Future<void> _restorePosition() async {
    final saved = await widget.storage.loadBubblePosition();
    if (!mounted) return;
    final machine = _machine!;
    if (saved != null) {
      final result = machine.restore(saved.x, saved.y);
      if (result.wasCorrected) {
        widget.storage.saveBubblePosition(result.position.x, result.position.y);
      }
    }
    if (widget.pushToSide) {
      _pushedBySide = machine.forceHide() != null || machine.isHidden;
    }
    _position.value = Offset(machine.position.x, machine.position.y);
    setState(() => _initialized = true);
  }

  @override
  void didUpdateWidget(FloatingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pushToSide == oldWidget.pushToSide) return;
    final machine = _machine;
    if (machine == null || !_initialized) return;

    if (widget.pushToSide) {
      if (_dragging) return;
      final target = machine.forceHide();
      if (target != null) {
        _pushedBySide = true;
        _animateTo(target);
      }
    } else if (_pushedBySide) {
      _pushedBySide = false;
      final target = machine.forceShow();
      if (target != null) _animateTo(target);
    }
  }

  void _animateTo(BubblePoint target) {
    _moveTween = Tween(begin: _position.value, end: Offset(target.x, target.y));
    _saveAfterMove = target;
    _mover.forward(from: 0);
  }

  // =============================
  // Grip gestures (Listener: no arena, manual RN-parity threshold)
  // =============================

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _pointerDownGlobal = event.position;
    _mover.stop();
    _saveAfterMove = null;
    _machine!.dragStart();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final delta = event.position - _pointerDownGlobal;
    final live = _machine!.dragMove(delta.dx, delta.dy);
    if (live == null) return;
    if (!_dragging) setState(() => _dragging = true);
    _position.value = Offset(live.x, live.y);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _endDrag(allowTap: true);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _endDrag(allowTap: false);
  }

  void _endDrag({required bool allowTap}) {
    _activePointer = null;
    final result = _machine!.dragEnd();
    if (_dragging) setState(() => _dragging = false);

    if (result.wasTap) {
      if (allowTap) _toggleHideShow();
      return;
    }
    if (result.shouldAnimate) {
      _animateTo(result.position);
    } else {
      _position.value = Offset(result.position.x, result.position.y);
      widget.storage.saveBubblePosition(result.position.x, result.position.y);
    }
  }

  void _toggleHideShow() {
    _pushedBySide = false;
    final result = _machine!.toggleHideShow();
    _animateTo(result.target);
  }

  void _measureBubble(Duration _) {
    final machine = _machine;
    final size = _bubbleKey.currentContext?.size;
    if (machine == null || size == null) return;
    machine.bubbleWidth = size.width;
    machine.bubbleHeight = size.height;
  }

  @override
  void dispose() {
    _moverCurve.dispose();
    _mover.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No flash at (0,0): nothing renders until the position is restored.
    if (!_initialized) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback(_measureBubble);
    final hasMinimized = widget.minimizedTools.isNotEmpty;
    // The minimized stack reserves its full expanded height above the body;
    // offset the whole thing up by that amount so the body stays at its drag
    // anchor whether the stack is collapsed or expanded (and so the reserved
    // area — mostly transparent — sits above the bubble and stays tappable).
    final topOffset = hasMinimized
        ? MinimizedToolsStack.expandedHeightFor(widget.minimizedTools.length)
        : 0.0;

    final body = _BubbleBody(
      bubbleKey: _bubbleKey,
      dragging: _dragging,
      hasMinimizedTools: hasMinimized,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onOpenDial: widget.onOpenDial,
    );

    return ValueListenableBuilder<Offset>(
      valueListenable: _position,
      builder: (context, pos, child) =>
          Positioned(left: pos.dx, top: pos.dy - topOffset, child: child!),
      child: hasMinimized
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Docked above the drag handle (left-aligned, 32 wide), moves
                // with the bubble because it's inside the same Positioned.
                MinimizedToolsStack(
                  tools: widget.minimizedTools,
                  storage: widget.storage,
                  onRestore: widget.onRestoreMinimized,
                ),
                body,
              ],
            )
          : body,
    );
  }
}

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({
    required this.bubbleKey,
    required this.dragging,
    required this.hasMinimizedTools,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.onOpenDial,
  });

  final GlobalKey bubbleKey;
  final bool dragging;

  /// When the minimized-tools stack is docked on top, square off the shared
  /// top-left corner so the two panels read as one (RN seamless connection).
  final bool hasMinimizedTools;
  final PointerDownEventListener onPointerDown;
  final PointerMoveEventListener onPointerMove;
  final PointerUpEventListener onPointerUp;
  final PointerCancelEventListener onPointerCancel;
  final VoidCallback onOpenDial;

  @override
  Widget build(BuildContext context) {
    final borderColor = dragging
        ? BuoyTheme.teal
        : BuoyTheme.muted.withValues(alpha: 0.4);
    // Transparent Material: the menu lives above the app's Scaffold, and Text
    // without a Material ancestor renders the debug yellow-underline fallback.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: bubbleKey,
        decoration: BoxDecoration(
          color: BuoyTheme.panel,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(hasMinimizedTools ? 0 : 6),
            topRight: const Radius.circular(6),
            bottomLeft: const Radius.circular(6),
            bottomRight: const Radius.circular(6),
          ),
          border: Border.all(color: borderColor, width: dragging ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: dragging
                  ? BuoyTheme.teal.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: 0.3),
              blurRadius: dragging ? 12 : 8,
              offset: Offset(0, dragging ? 6 : 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: onPointerDown,
              onPointerMove: onPointerMove,
              onPointerUp: onPointerUp,
              onPointerCancel: onPointerCancel,
              child: Container(
                width: visibleHandleWidth,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: BuoyTheme.muted.withValues(alpha: 0.1),
                  border: Border(
                    right: BorderSide(
                      color: BuoyTheme.muted.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: BuoyTheme.secondary.withValues(alpha: 0.8),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dragging ? null : onOpenDial,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: BuoyTheme.teal,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'BUOY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        fontFamily: 'monospace',
                        color: BuoyTheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
