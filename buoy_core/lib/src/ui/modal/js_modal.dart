import 'dart:async';
import '../../icons/buoy_icon_painter.dart';
import '../../icons/buoy_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../storage.dart';
import '../buoy_theme.dart';
import '../touchable_opacity.dart';
import 'modal_settings.dart';
import 'modal_visibility.dart';

/// Flutter port of shared-ui's `JsModal` — the draggable/resizable tool
/// modal with two modes:
///
/// - **bottomSheet**: bottom-anchored, full width; dragging the header
///   resizes it with absolute finger anchoring; a fast downward fling closes.
/// - **floating**: free window; drag by the header, resize from the bottom
///   corners; safe-area-aware bounds; teal border + glow while interacting.
///
/// Double-tapping the header toggles modes and triple-tapping minimizes (when
/// [onMinimize] is wired), matching RN. The macOS-style window control dots
/// mirror this: yellow = minimize, green = toggle, red = close. Mode, sheet
/// height, and floating rect persist per `persistenceKey` (same JSON shape as
/// RN's ModalStorage).
///
/// Deviations from RN: no hint banner. The minimize dot only renders when
/// [onMinimize] is provided (RN hides it the same way); the host moves the
/// tool to its minimized dock and restores geometry from persistence on reopen.
enum JsModalMode { bottomSheet, floating }

const _minHeightDefault = 100.0;
const _floatingHeightDefault = 500.0;
const _floatingMinHeight = 80.0;

/// RN bottom-sheet spring: tension 180 / friction 22.
const _sheetSpring = SpringDescription(mass: 1, stiffness: 180, damping: 22);

/// Pixel-scale springs settle "done" at sub-pixel rest instead of Flutter's
/// default 0.001px tolerance — otherwise the exit spring keeps simulating
/// invisibly for seconds and delays the onClose callback.
const _pxTolerance = Tolerance(distance: 0.5, velocity: 0.5);

class JsModal extends StatefulWidget {
  const JsModal({
    super.key,
    required this.storage,
    required this.onClose,
    required this.child,
    this.onMinimize,
    this.headerContent,
    this.minHeight = _minHeightDefault,
    this.maxHeight,
    this.initialHeight = 400,
    this.initialMode = JsModalMode.bottomSheet,
    this.initialFloatingPosition,
    this.persistenceKey,
    this.onModeChange,
    this.wrapChildInScrollView = true,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final Widget child;

  /// When provided, the modal shows a yellow minimize dot (and triple-tap
  /// minimizes). The host is expected to hide the modal, dock a restorable
  /// icon, and re-open the tool on restore. When null, no minimize affordance
  /// renders (RN parity via `hideMinimizeButton`/absent `onMinimize`).
  final VoidCallback? onMinimize;

  /// Rendered under the drag indicator (e.g. the settings tab selector).
  final Widget? headerContent;

  final double minHeight;

  /// Defaults to screenHeight - top inset (RN effectiveMaxHeight).
  final double? maxHeight;
  final double initialHeight;
  final JsModalMode initialMode;
  final Offset? initialFloatingPosition;
  final String? persistenceKey;
  final void Function(JsModalMode mode)? onModeChange;
  final bool wrapChildInScrollView;

  @override
  State<JsModal> createState() => _JsModalState();
}

class _JsModalState extends State<JsModal> with TickerProviderStateMixin {
  late JsModalMode _mode = widget.initialMode;
  late final ValueNotifier<double> _sheetHeight = ValueNotifier(
    widget.initialHeight,
  );
  final ValueNotifier<Rect?> _floatRect = ValueNotifier(null);

  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
  ); // translateY px
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  bool _loaded = false;
  bool _entranceStarted = false;
  bool _closing = false;
  bool _interacting = false; // dragging or resizing → accent border

  /// Host-driven visibility (RN AppHost `visible={!app.minimized}`). While
  /// false the modal renders offstage but stays MOUNTED, so tool state
  /// survives minimize. Defaults true when no [BuoyModalVisibility] ancestor.
  bool _visible = true;
  Timer? _persistTimer;

  // Gesture scratch state (fields, not locals: a setState mid-gesture must
  // not reset accumulated deltas).
  double _grabOffsetY = 0;
  double _dragStartGlobalY = 0;
  double _lastGlobalY = 0;
  Rect _gestureStartRect = Rect.zero;
  Offset _panTotal = Offset.zero;

  // RN-style manual tap counting on the header (double tap = toggle mode).
  // A DoubleTapGestureRecognizer would hold the gesture arena and delay
  // every tap inside the header (e.g. the settings tabs) by ~300ms.
  int _headerTapCount = 0;
  DateTime _lastHeaderTap = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _headerTapTimer;

  void _handleHeaderTap() {
    final now = DateTime.now();
    if (now.difference(_lastHeaderTap).inMilliseconds > 500) {
      _headerTapCount = 0;
    }
    _headerTapCount++;
    _lastHeaderTap = now;
    _headerTapTimer?.cancel();
    _headerTapTimer = Timer(const Duration(milliseconds: 300), () {
      // RN: double tap toggles mode, triple tap minimizes (if available).
      if (_headerTapCount == 2) {
        _toggleMode();
      } else if (_headerTapCount >= 3 && widget.onMinimize != null) {
        _requestMinimize();
      }
      _headerTapCount = 0;
    });
  }

  // Expandable window controls (RN ExpandableWindowControls).
  final _controlsTriggerKey = GlobalKey();
  bool _controlsExpanded = false;
  Rect _controlsTriggerRect = Rect.zero;
  Timer? _controlsDismissTimer;
  late final AnimationController _controlsAnim = AnimationController.unbounded(
    vsync: this,
  );

  /// Own key normally; the shared record when SHARED MODAL SIZE is on
  /// (RN AppHost injects enableSharedModalDimensions into every tool modal).
  String? get _persistKey {
    final own = widget.persistenceKey;
    if (own == null) return null;
    return sharedModalDimensionsEnabled.value ? sharedModalStateKey : own;
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = BuoyModalVisibility.of(context);
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      // Restore from minimize: _requestMinimize left _closing true and the
      // exit animation settled — replay the entrance (RN re-runs its
      // visibility effect when `visible` flips back on).
      _closing = false;
      _entranceStarted = false;
    } else {
      _slide.stop();
      _fade.stop();
      _interacting = false;
      _controlsDismissTimer?.cancel();
      _controlsAnim.stop();
      _controlsExpanded = false;
    }
  }

  Future<void> _restore() async {
    final key = _persistKey;
    if (key != null) {
      final saved = await widget.storage.loadJson(key);
      if (saved != null) {
        final mode = saved['mode'];
        if (mode == 'floating') _mode = JsModalMode.floating;
        if (mode == 'bottomSheet') _mode = JsModalMode.bottomSheet;
        final height = saved['panelHeight'];
        if (height is num) _sheetHeight.value = height.toDouble();
        final dims = saved['dimensions'];
        if (dims is Map) {
          final w = dims['width'], h = dims['height'];
          final top = dims['top'], left = dims['left'];
          if (w is num && h is num && top is num && left is num) {
            _floatRect.value = Rect.fromLTWH(
              left.toDouble(),
              top.toDouble(),
              w.toDouble(),
              h.toDouble(),
            );
          }
        }
        widget.onModeChange?.call(_mode);
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _writeState() {
    final key = _persistKey;
    if (key == null) return;
    final rect = _floatRect.value;
    widget.storage.saveJson(key, {
      'mode': _mode == JsModalMode.floating ? 'floating' : 'bottomSheet',
      'panelHeight': _sheetHeight.value,
      if (rect != null)
        'dimensions': {
          'width': rect.width,
          'height': rect.height,
          'top': rect.top,
          'left': rect.left,
        },
    });
  }

  void _persistDebounced() {
    if (_persistKey == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 500), _writeState);
  }

  /// Flush the current geometry immediately (used on minimize so reopening
  /// restores the exact mode/size/position instead of the last debounced or
  /// default state).
  void _persistNow() {
    _persistTimer?.cancel();
    _writeState();
  }

  // ── Entrance / exit (RN visibility effect) ────────────────────────────

  void _startEntrance(double screenHeight) {
    _entranceStarted = true;
    _fade.forward(from: 0);
    if (_mode == JsModalMode.bottomSheet) {
      _slide.value = screenHeight;
      _slide.animateWith(
        SpringSimulation(
          _sheetSpring,
          screenHeight,
          0,
          0,
          tolerance: _pxTolerance,
        ),
      );
    } else {
      _slide.value = 0;
    }
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    _closing = true;
    await _animateOut();
    if (mounted) widget.onClose();
  }

  /// Minimize: same exit animation as close, but flush geometry first and hand
  /// off to the host's minimized dock instead of destroying the tool.
  Future<void> _requestMinimize() async {
    if (_closing || widget.onMinimize == null) return;
    _closing = true;
    _persistNow();
    await _animateOut();
    if (mounted) widget.onMinimize!();
  }

  Future<void> _animateOut() async {
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (_mode == JsModalMode.bottomSheet) {
      _fade.reverse();
      // Don't wait for the spring to formally settle (it simulates far past
      // the visible exit) — complete as soon as the sheet has fully left the
      // screen.
      final offscreenAt = _sheetHeight.value + 40;
      final done = Completer<void>();
      void onTick() {
        if (_slide.value >= offscreenAt && !done.isCompleted) {
          done.complete();
        }
      }

      _slide.addListener(onTick);
      _slide
          .animateWith(
            SpringSimulation(
              _sheetSpring,
              _slide.value,
              screenHeight,
              0,
              tolerance: _pxTolerance,
            ),
          )
          .whenCompleteOrCancel(() {
            if (!done.isCompleted) done.complete();
          });
      await done.future;
      _slide.removeListener(onTick);
      _slide.stop();
    } else {
      await _fade.reverse().orCancel.catchError((_) {});
    }
  }

  void _toggleMode() {
    if (_closing) return;
    setState(() {
      _interacting = false;
      _mode = _mode == JsModalMode.bottomSheet
          ? JsModalMode.floating
          : JsModalMode.bottomSheet;
      // RN's visibility effect re-runs on mode change, replaying the
      // entrance for the new mode.
      _entranceStarted = false;
    });
    widget.onModeChange?.call(_mode);
    _persistDebounced();
  }

  // ── Bottom-sheet resize (absolute finger anchoring) ───────────────────

  double get _effectiveMaxHeight {
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return widget.maxHeight ?? screen.height - topInset;
  }

  void _sheetDragStart(DragStartDetails details) {
    _grabOffsetY = details.localPosition.dy;
    _dragStartGlobalY = details.globalPosition.dy;
    _lastGlobalY = _dragStartGlobalY;
    _slide.stop();
    setState(() => _interacting = true);
  }

  void _sheetDragUpdate(DragUpdateDetails details) {
    _lastGlobalY = details.globalPosition.dy;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetTop = details.globalPosition.dy - _grabOffsetY;
    _sheetHeight.value = (screenHeight - sheetTop).clamp(
      widget.minHeight,
      _effectiveMaxHeight,
    );
  }

  void _sheetDragEnd(DragEndDetails details) {
    setState(() => _interacting = false);
    final dy = _lastGlobalY - _dragStartGlobalY;
    final velocity = details.primaryVelocity ?? 0;
    // RN: vy > 0.8 px/ms (& dy > 50), or dy > 150 while pinned at minHeight.
    final shouldClose =
        (velocity > 800 && dy > 50) ||
        (dy > 150 && _sheetHeight.value <= widget.minHeight);
    if (shouldClose) {
      _requestClose();
    } else {
      _persistDebounced();
    }
  }

  // ── Floating drag ─────────────────────────────────────────────────────

  Rect _defaultFloatRect(Size screen) {
    final pos = widget.initialFloatingPosition;
    return Rect.fromLTWH(
      pos?.dx ?? 0,
      pos?.dy ?? (screen.height - _floatingHeightDefault) / 2,
      screen.width,
      _floatingHeightDefault,
    );
  }

  void _floatDragStart(DragStartDetails details) {
    _gestureStartRect = _floatRect.value!;
    setState(() => _interacting = true);
  }

  void _floatDragUpdate(DragUpdateDetails details, Offset totalDelta) {
    _floatRect.value = _gestureStartRect.shift(totalDelta);
  }

  void _floatDragEnd() {
    // DraggableHeader clamps on release: x ∈ [0, screenW - w],
    // y ∈ [topInset, screenH - h].
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final rect = _floatRect.value!;
    final maxX = (screen.width - rect.width).clamp(0.0, double.infinity);
    final maxY = (screen.height - rect.height).clamp(topInset, double.infinity);
    _floatRect.value = Rect.fromLTWH(
      rect.left.clamp(0.0, maxX),
      rect.top.clamp(topInset, maxY),
      rect.width,
      rect.height,
    );
    setState(() => _interacting = false);
    _persistDebounced();
  }

  // ── Floating corner resize ────────────────────────────────────────────

  void _cornerResizeUpdate(bool isLeftCorner, Offset totalDelta) {
    final screen = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewPaddingOf(context);
    final minLeft = insets.left;
    final maxRight = screen.width - insets.right;
    final maxBottom = screen.height - insets.bottom;
    final minWidth = screen.width * 0.25; // FLOATING_MIN_WIDTH

    final start = _gestureStartRect;
    double left = start.left;
    double right = start.right;
    final newBottom = (start.bottom + totalDelta.dy).clamp(
      start.top + _floatingMinHeight,
      maxBottom,
    );

    if (isLeftCorner) {
      left = (start.left + totalDelta.dx).clamp(
        minLeft,
        start.right - minWidth,
      );
    } else {
      right = (start.right + totalDelta.dx).clamp(
        start.left + minWidth,
        maxRight,
      );
    }
    _floatRect.value = Rect.fromLTRB(left, start.top, right, newBottom);
  }

  // ── Expandable window controls ────────────────────────────────────────

  void _expandControls() {
    final box =
        _controlsTriggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _controlsTriggerRect = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _controlsExpanded = true);
    _controlsAnim.value = 0;
    // RN expand spring: tension 180 / friction 18.
    _controlsAnim.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 180, damping: 18),
        0,
        1,
        0,
      ),
    );
    _controlsDismissTimer?.cancel();
    _controlsDismissTimer = Timer(
      const Duration(milliseconds: 3000),
      _collapseControls,
    );
  }

  Future<void> _collapseControls() async {
    if (!_controlsExpanded) return;
    _controlsDismissTimer?.cancel();
    // RN collapse spring: tension 200 / friction 20.
    await _controlsAnim
        .animateWith(
          SpringSimulation(
            const SpringDescription(mass: 1, stiffness: 200, damping: 20),
            _controlsAnim.value,
            0,
            0,
          ),
        )
        .orCancel
        .catchError((_) {});
    if (mounted) setState(() => _controlsExpanded = false);
  }

  void _controlsAction(VoidCallback action) {
    _collapseControls();
    action();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _headerTapTimer?.cancel();
    _controlsDismissTimer?.cancel();
    _controlsAnim.dispose();
    _slide.dispose();
    _fade.dispose();
    _sheetHeight.dispose();
    _floatRect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);
    _floatRect.value ??= _defaultFloatRect(screen);
    if (_visible && !_entranceStarted) _startEntrance(screen.height);

    // Visibility(maintainState) = Offstage + TickerMode: while minimized the
    // subtree stays mounted (state/subscriptions live on) but paints nothing
    // and is excluded from hit testing — RN renders minimized modals
    // offscreen with pointerEvents="none" for the same effect. Kept INSIDE
    // Positioned.fill so the ParentData chain to the host Stack is intact.
    return Positioned.fill(
      child: Visibility(
        visible: _visible,
        maintainState: true,
        child: Material(
          type: MaterialType.transparency,
          child: _mode == JsModalMode.bottomSheet
              ? _bottomSheet(screen)
              : _floating(),
        ),
      ),
    );
  }

  // ── Bottom sheet ──────────────────────────────────────────────────────

  Widget _bottomSheet(Size screen) {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([_slide, _fade]),
          builder: (context, child) => Positioned(
            left: 0,
            right: 0,
            bottom: -_slide.value,
            child: Opacity(opacity: _fade.value.clamp(0.0, 1.0), child: child!),
          ),
          child: ValueListenableBuilder<double>(
            valueListenable: _sheetHeight,
            builder: (context, height, child) =>
                SizedBox(height: height, child: child),
            child: Container(
              decoration: BoxDecoration(
                color: BuoyTheme.card,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
                border: Border.all(color: BuoyTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: BuoyTheme.teal.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleHeaderTap,
                    onVerticalDragStart: _sheetDragStart,
                    onVerticalDragUpdate: _sheetDragUpdate,
                    onVerticalDragEnd: _sheetDragEnd,
                    child: _header(),
                  ),
                  Expanded(child: _content()),
                ],
              ),
            ),
          ),
        ),
        ..._expandedControlsLayers(),
      ],
    );
  }

  // ── Floating window ───────────────────────────────────────────────────

  Widget _floating() {
    return Stack(
      children: [
        ValueListenableBuilder<Rect?>(
          valueListenable: _floatRect,
          builder: (context, rect, child) =>
              Positioned.fromRect(rect: rect!, child: child!),
          child: AnimatedBuilder(
            animation: _fade,
            builder: (context, child) =>
                Opacity(opacity: _fade.value.clamp(0.0, 1.0), child: child!),
            child: Container(
              decoration: BoxDecoration(
                color: BuoyTheme.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _interacting ? BuoyTheme.teal : BuoyTheme.border,
                  width: _interacting ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: BuoyTheme.teal.withValues(
                      alpha: _interacting ? 0.5 : 0.3,
                    ),
                    blurRadius: _interacting ? 12 : 20,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _handleHeaderTap,
                        onPanStart: (details) {
                          _panTotal = Offset.zero;
                          _floatDragStart(details);
                        },
                        onPanUpdate: (details) {
                          _panTotal += details.delta;
                          _floatDragUpdate(details, _panTotal);
                        },
                        onPanEnd: (_) => _floatDragEnd(),
                        onPanCancel: _floatDragEnd,
                        child: _header(),
                      ),
                      Expanded(child: _content()),
                    ],
                  ),
                  _cornerHandle(isLeftCorner: true),
                  _cornerHandle(isLeftCorner: false),
                ],
              ),
            ),
          ),
        ),
        ..._expandedControlsLayers(),
      ],
    );
  }

  Widget _cornerHandle({required bool isLeftCorner}) {
    return Positioned(
      bottom: 4,
      left: isLeftCorner ? 4 : null,
      right: isLeftCorner ? null : 4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _panTotal = Offset.zero;
          _gestureStartRect = _floatRect.value!;
          setState(() => _interacting = true);
        },
        onPanUpdate: (details) {
          _panTotal += details.delta;
          _cornerResizeUpdate(isLeftCorner, _panTotal);
        },
        onPanEnd: (_) {
          setState(() => _interacting = false);
          _persistDebounced();
        },
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Container(
              width: 20,
              height: 20,
              decoration: _interacting
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      color: BuoyTheme.teal.withValues(alpha: 0.1),
                      border: Border.all(color: BuoyTheme.teal, width: 2),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared chrome ─────────────────────────────────────────────────────

  Widget _header() {
    final floating = _mode == JsModalMode.floating;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: const BoxDecoration(
        color: BuoyTheme.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
        border: Border(bottom: BorderSide(color: BuoyTheme.border)),
      ),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Container(
                  width: floating ? 50 : 40,
                  height: floating ? 5 : 3,
                  decoration: BoxDecoration(
                    color: floating ? BuoyTheme.muted : BuoyTheme.teal,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: floating
                        ? null
                        : [
                            BoxShadow(
                              color: BuoyTheme.teal.withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
                          ],
                  ),
                ),
              ),
              if (widget.headerContent != null) widget.headerContent!,
            ],
          ),
          // RN windowControlsContainer: absolute right 4, trigger padding 2.
          // Nudged up 2px from RN's top 4 for tighter header alignment.
          Positioned(
            top: .5,
            right: 4,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: _windowControls(),
            ),
          ),
        ],
      ),
    );
  }

  LucideIcon get _toggleModeIcon => _mode == JsModalMode.floating
      ? BuoyIcons.arrowDownToLine
      : BuoyIcons.copy;

  /// macOS-style dots (left→right, RN order): yellow minimizes, green toggles
  /// mode (icon shows the action), red closes. The minimize dot only renders
  /// when [JsModal.onMinimize] is wired. When EXPAND CONTROLS is on, the dots
  /// become a trigger that expands into large buttons (RN
  /// ExpandableWindowControls).
  Widget _windowControls() {
    final canMinimize = widget.onMinimize != null;
    return ValueListenableBuilder<bool>(
      valueListenable: expandableWindowControlsEnabled,
      builder: (context, expandable, _) {
        final dots = Row(
          spacing: 8,
          children: [
            if (canMinimize)
              _controlDot(
                color: const Color(0xFFFEBC2E),
                icon: BuoyIcons.minus,
                iconColor: const Color(0xFF7A5A00),
                onTap: expandable ? null : _requestMinimize,
              ),
            _controlDot(
              color: const Color(0xFF28C840),
              icon: _toggleModeIcon,
              iconColor: const Color(0xFF004A1A),
              onTap: expandable ? null : _toggleMode,
            ),
            _controlDot(
              color: const Color(0xFFFF5F57),
              icon: BuoyIcons.x,
              iconColor: const Color(0xFF4A0000),
              onTap: expandable ? null : _requestClose,
            ),
          ],
        );
        if (!expandable) return dots;
        return TouchableOpacity(
          key: _controlsTriggerKey,
          activeOpacity: 0.7,
          onTap: _expandControls,
          child: dots,
        );
      },
    );
  }

  Widget _controlDot({
    required Color color,
    required LucideIcon icon,
    required Color iconColor,
    VoidCallback? onTap,
  }) {
    // RN: BUTTON_SIZE 12, ICON_SIZE 8, no padding around individual dots.
    final dot = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: BuoyGlyph(icon, size: 8, color: iconColor)),
    );
    if (onTap == null) return dot;
    return TouchableOpacity(activeOpacity: 0.8, onTap: onTap, child: dot);
  }

  /// RN expanded panel: 36px buttons, 12px gap, 8px padding, anchored to the
  /// trigger's top-right, over a full-screen tap-to-dismiss layer.
  List<Widget> _expandedControlsLayers() {
    if (!_controlsExpanded) return const [];
    const buttonSize = 36.0;
    const buttonSpacing = 12.0;
    const panelPadding = 8.0;
    final buttonCount = widget.onMinimize != null ? 3 : 2;
    final panelWidth =
        buttonCount * buttonSize +
        (buttonCount - 1) * buttonSpacing +
        2 * panelPadding;
    return [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _collapseControls,
          child: const SizedBox.expand(),
        ),
      ),
      AnimatedBuilder(
        animation: _controlsAnim,
        builder: (context, child) {
          final t = _controlsAnim.value;
          final opacity = (t <= 0.5 ? t * 1.6 : 0.8 + (t - 0.5) * 0.4).clamp(
            0.0,
            1.0,
          );
          return Positioned(
            top: _controlsTriggerRect.top - panelPadding,
            left: _controlsTriggerRect.right - panelWidth,
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(scale: 0.3 + 0.7 * t, child: child!),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(panelPadding),
          decoration: BoxDecoration(
            color: BuoyTheme.card,
            borderRadius: BorderRadius.circular(
              (buttonSize + panelPadding * 2) / 2,
            ),
            border: Border.all(color: BuoyTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: buttonSpacing,
            children: [
              if (widget.onMinimize != null)
                _expandedControlButton(
                  color: const Color(0xFFFEBC2E),
                  icon: BuoyIcons.minus,
                  iconColor: const Color(0xFF7A5A00),
                  onTap: () => _controlsAction(_requestMinimize),
                ),
              _expandedControlButton(
                color: const Color(0xFF28C840),
                icon: _toggleModeIcon,
                iconColor: const Color(0xFF004A1A),
                onTap: () => _controlsAction(_toggleMode),
              ),
              _expandedControlButton(
                color: const Color(0xFFFF5F57),
                icon: BuoyIcons.x,
                iconColor: const Color(0xFF4A0000),
                onTap: () => _controlsAction(_requestClose),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _expandedControlButton({
    required Color color,
    required LucideIcon icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: BuoyGlyph(icon, size: 16, color: iconColor)),
      ),
    );
  }

  Widget _content() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: ColoredBox(
        color: BuoyTheme.base,
        child: widget.wrapChildInScrollView
            ? SingleChildScrollView(child: widget.child)
            : widget.child,
      ),
    );
  }
}
