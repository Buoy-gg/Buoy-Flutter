/// Headless drag/hide/clamp state machine for the floating bubble, ported
/// from @buoy-gg/floating-tools-core `FloatingToolsStore.ts` with the native
/// `floatingTools.tsx` behaviors (safe-area bounds, edge padding, restore
/// rules). Pure Dart — the widget layer owns gestures, animation, and
/// persistence; this class owns every position decision.
library;

import 'constants.dart';

class BubblePoint {
  const BubblePoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is BubblePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'BubblePoint($x, $y)';
}

class BubbleBounds {
  const BubbleBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

class RestoreResult {
  const RestoreResult({
    required this.position,
    required this.wasHidden,
    required this.wasCorrected,
  });

  final BubblePoint position;
  final bool wasHidden;

  /// The saved position was out of bounds and the corrected value should be
  /// written back to storage.
  final bool wasCorrected;
}

class DragEndResult {
  const DragEndResult({
    required this.position,
    required this.wasTap,
    required this.shouldAnimate,
  });

  /// The resting position (the hidden slot when auto-hiding).
  final BubblePoint position;
  final bool wasTap;

  /// True when the bubble should animate to [position] (auto-hide); false
  /// when it is already there (normal release).
  final bool shouldAnimate;
}

class ToggleResult {
  const ToggleResult({required this.target, required this.isHiding});

  final BubblePoint target;
  final bool isHiding;
}

class BubbleStateMachine {
  BubbleStateMachine({
    required this.screenWidth,
    required this.screenHeight,
    this.insetLeft = 0,
    this.insetTop = 0,
    this.insetBottom = 0,
    this.bubbleWidth = 100,
    this.bubbleHeight = 32,
  }) : position = const BubblePoint(0, 0) {
    position = defaultPosition();
  }

  double screenWidth;
  double screenHeight;
  double insetLeft;
  double insetTop;
  double insetBottom;
  double bubbleWidth;
  double bubbleHeight;

  BubblePoint position;
  bool isHidden = false;
  bool isDragging = false;

  /// Last known good visible position, restored when un-hiding.
  BubblePoint? _savedVisiblePosition;

  BubblePoint _dragStartPosition = const BubblePoint(0, 0);
  bool _dragMoved = false;

  double get _hiddenX => screenWidth - visibleHandleWidth;

  BubbleBounds get bounds => BubbleBounds(
    minX: insetLeft,
    // Overflow to the right is allowed so only the grip stays visible.
    maxX: screenWidth - visibleHandleWidth,
    minY: insetTop + edgePadding,
    maxY: screenHeight - bubbleHeight - insetBottom,
  );

  BubblePoint validatePosition(BubblePoint p) {
    final b = bounds;
    return BubblePoint(p.x.clamp(b.minX, b.maxX), p.y.clamp(b.minY, b.maxY));
  }

  /// Default resting spot: right side, y near the top (capped at 100 like RN).
  BubblePoint defaultPosition() {
    final b = bounds;
    final y = 100.0.clamp(b.minY, b.maxY < b.minY ? b.minY : b.maxY);
    return BubblePoint(screenWidth - bubbleWidth - edgePadding, y);
  }

  /// Apply a position loaded from storage.
  RestoreResult restore(double savedX, double savedY) {
    final saved = BubblePoint(savedX, savedY);
    final validated = validatePosition(saved);
    final wasCorrected =
        (saved.x - validated.x).abs() > 5 || (saved.y - validated.y).abs() > 5;
    final wasHidden = validated.x >= _hiddenX - hiddenRestoreTolerance;

    position = validated;
    isHidden = wasHidden;
    if (!wasHidden) _savedVisiblePosition = validated;

    return RestoreResult(
      position: validated,
      wasHidden: wasHidden,
      wasCorrected: wasCorrected,
    );
  }

  /// Call when screen size or insets change (rotation, resize). Returns the
  /// corrected position when the bubble had to move, null otherwise.
  BubblePoint? setScreenMetrics({
    required double width,
    required double height,
    required double left,
    required double top,
    required double bottom,
  }) {
    screenWidth = width;
    screenHeight = height;
    insetLeft = left;
    insetTop = top;
    insetBottom = bottom;

    final target = isHidden
        ? BubblePoint(_hiddenX, position.y.clamp(bounds.minY, bounds.maxY))
        : validatePosition(position);
    if (target == position) return null;
    position = target;
    return target;
  }

  // =============================
  // Drag
  // =============================

  void dragStart() {
    _dragMoved = false;
    _dragStartPosition = position;
  }

  /// Process cumulative gesture deltas. Returns the live position once the
  /// drag threshold is crossed, null while the gesture still counts as a tap.
  /// Movement is intentionally unclamped during the drag (RN parity); bounds
  /// apply on release.
  BubblePoint? dragMove(double totalDx, double totalDy) {
    if (!_dragMoved && totalDx.abs() + totalDy.abs() > dragThreshold) {
      _dragMoved = true;
      isDragging = true;
    }
    if (!_dragMoved) return null;
    position = BubblePoint(
      _dragStartPosition.x + totalDx,
      _dragStartPosition.y + totalDy,
    );
    return position;
  }

  DragEndResult dragEnd() {
    isDragging = false;

    if (!_dragMoved) {
      return DragEndResult(
        position: position,
        wasTap: true,
        shouldAnimate: false,
      );
    }

    final b = bounds;
    // Release clamp: X may overflow right up to fully offscreen (DraggableHeader
    // maxOverflowX = bubbleWidth) so the midpoint rule below can trigger.
    final x = position.x.clamp(b.minX, screenWidth);
    final y = position.y.clamp(b.minY, b.maxY);

    final bubbleMidpoint = x + bubbleWidth / 2;
    if (bubbleMidpoint > screenWidth) {
      // Auto-hide: keep the Y where the user dropped it, remember a visible X
      // to restore to later.
      _savedVisiblePosition = BubblePoint(
        _savedVisiblePosition?.x ?? screenWidth - bubbleWidth - edgePadding,
        y,
      );
      isHidden = true;
      position = BubblePoint(_hiddenX, y);
      return DragEndResult(
        position: position,
        wasTap: false,
        shouldAnimate: true,
      );
    }

    // Pulling back out of the hidden slot un-hides.
    if (isHidden && x < _hiddenX - 10) {
      isHidden = false;
    }
    if (x < screenWidth - bubbleWidth / 2) {
      _savedVisiblePosition = BubblePoint(x, y);
    }
    position = BubblePoint(x, y);
    return DragEndResult(
      position: position,
      wasTap: false,
      shouldAnimate: false,
    );
  }

  // =============================
  // Hide / show
  // =============================

  ToggleResult toggleHideShow() {
    // The visual check handles isHidden being out of sync with the position.
    final isVisuallyOffScreen = position.x > screenWidth - bubbleWidth / 2;

    if (isHidden || isVisuallyOffScreen) {
      final saved = _savedVisiblePosition;
      final target = (saved != null && saved.x < screenWidth - bubbleWidth / 2)
          ? saved
          : BubblePoint(screenWidth - bubbleWidth - edgePadding, position.y);
      isHidden = false;
      position = target;
      return ToggleResult(target: target, isHiding: false);
    }

    _savedVisiblePosition = position;
    isHidden = true;
    position = BubblePoint(_hiddenX, position.y);
    return ToggleResult(target: position, isHiding: true);
  }

  /// Push the bubble to the hidden slot (dial or a tool opened). Returns the
  /// animation target, or null if already hidden.
  BubblePoint? forceHide() {
    if (isHidden) return null;
    _savedVisiblePosition = position;
    isHidden = true;
    position = BubblePoint(_hiddenX, position.y);
    return position;
  }

  /// Restore from [forceHide]. Returns the animation target, or null if not
  /// hidden.
  BubblePoint? forceShow() {
    if (!isHidden) return null;
    final saved = _savedVisiblePosition;
    final target =
        saved ??
        BubblePoint(screenWidth - bubbleWidth - edgePadding, position.y);
    isHidden = false;
    position = target;
    return target;
  }
}
