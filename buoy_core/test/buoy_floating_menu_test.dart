import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_core/src/core/bubble_state.dart';
import 'package:buoy_core/src/core/dial_math.dart';

// Parity tests against @buoy-gg/floating-tools-core (dial.ts /
// FloatingToolsStore.ts) — expected values mirror the TS math.
void main() {
  group('dial math', () {
    test('layout on a 390pt screen', () {
      final layout = getDialLayout(390);
      expect(layout.circleSize, closeTo(292.5, 0.001)); // 390 * 0.75
      expect(layout.circleRadius, closeTo(146.25, 0.001));
      // circleRadius - iconSize/2 - iconPadding
      expect(layout.iconRadius, closeTo(96.25, 0.001));
      expect(layout.iconSize, 60);
      expect(layout.buttonSize, 80);
    });

    test('layout caps at maxCircleSize on wide screens', () {
      expect(getDialLayout(800).circleSize, 320);
    });

    test('first icon sits at the top, slots evenly spaced', () {
      expect(getIconAngle(0, 6), closeTo(-math.pi / 2, 1e-9));
      expect(getIconAngle(1, 6) - getIconAngle(0, 6),
          closeTo(math.pi / 3, 1e-9));

      final top = getIconPosition(0, 6, 100);
      expect(top.x, closeTo(0, 1e-9));
      expect(top.y, closeTo(-100, 1e-9));

      final positions = getAllIconPositions(6, 100);
      expect(positions, hasLength(6));
      // Slot 3 is diametrically opposite slot 0.
      expect(positions[3].x, closeTo(-positions[0].x, 1e-9));
      expect(positions[3].y, closeTo(-positions[0].y, 1e-9));
    });

    test('stagger input range matches TS formula', () {
      // index 2 of 6 @ ratio 0.1 → [0, 0.2, 0.7, 1]
      final range = getIconStaggerInputRange(2, 6);
      expect(range[0], 0);
      expect(range[1], closeTo(0.2, 1e-9));
      expect(range[2], closeTo(0.7, 1e-9));
      expect(range[3], 1);
    });

    test('staggered progress maps through the window', () {
      expect(getStaggeredIconProgress(0.2, 2, 6), 0);
      expect(getStaggeredIconProgress(0.7, 2, 6), 1);
      expect(getStaggeredIconProgress(0.45, 2, 6), closeTo(0.5, 1e-9));
      expect(getStaggeredIconProgress(0, 0, 6), 0);
      expect(getStaggeredIconProgress(1, 5, 6), 1);
    });

    test('spiral starts collapsed at center and ends at the final slot', () {
      final start = getSpiralAnimationPosition(0, 1, 6, 96.25);
      expect(start.x, closeTo(0, 1e-9));
      expect(start.y, closeTo(0, 1e-9));
      expect(start.scale, 0);
      expect(start.opacity, 0);

      final end = getSpiralAnimationPosition(1, 1, 6, 96.25);
      final finalPos = getIconPosition(1, 6, 96.25);
      expect(end.x, closeTo(finalPos.x, 1e-9));
      expect(end.y, closeTo(finalPos.y, 1e-9));
      expect(end.rotation, 0);
      expect(end.scale, 1);
      expect(end.opacity, 1);
    });

    test('grid line rotations', () {
      expect(getGridLineRotations(), [0, 60, 120, 180, 240, 300]);
    });
  });

  group('bubble state machine', () {
    BubbleStateMachine makeMachine() => BubbleStateMachine(
          screenWidth: 390,
          screenHeight: 844,
          insetLeft: 0,
          insetTop: 59,
          insetBottom: 34,
        );

    test('default position: right side, y capped at 100', () {
      final m = makeMachine();
      expect(m.position, const BubblePoint(270, 100)); // 390 - 100 - 20
    });

    test('validatePosition clamps to safe-area bounds', () {
      final m = makeMachine();
      final clamped = m.validatePosition(const BubblePoint(500, 0));
      expect(clamped.x, 358); // maxX = 390 - 32 (handle may peek)
      expect(clamped.y, 79); // minY = insetTop 59 + edgePadding 20
      final bottom = m.validatePosition(const BubblePoint(10, 9999));
      expect(bottom.y, 844 - 32 - 34); // screenH - bubbleH - insetBottom
    });

    test('restore detects hidden slot within 5px tolerance', () {
      expect(makeMachine().restore(358, 200).wasHidden, isTrue);
      expect(makeMachine().restore(354, 200).wasHidden, isTrue);
      expect(makeMachine().restore(350, 200).wasHidden, isFalse);
    });

    test('restore corrects out-of-bounds positions and flags the save', () {
      final m = makeMachine();
      final result = m.restore(9999, 10);
      expect(result.wasCorrected, isTrue);
      expect(result.position.x, 358);
      expect(result.position.y, 79);
    });

    test('travel of exactly 5px is still a tap', () {
      final m = makeMachine();
      m.dragStart();
      expect(m.dragMove(3, 2), isNull); // |3| + |2| = 5, not > threshold
      final result = m.dragEnd();
      expect(result.wasTap, isTrue);
      expect(m.position, const BubblePoint(270, 100));
    });

    test('drag follows deltas relative to the start position', () {
      final m = makeMachine();
      m.dragStart();
      final live = m.dragMove(-30, 40);
      expect(live, const BubblePoint(240, 140));
      final result = m.dragEnd();
      expect(result.wasTap, isFalse);
      expect(result.shouldAnimate, isFalse);
      expect(result.position, const BubblePoint(240, 140));
    });

    test('release past the right-edge midpoint auto-hides', () {
      final m = makeMachine();
      m.dragStart();
      m.dragMove(80, 0); // x = 350, midpoint 400 > 390
      final result = m.dragEnd();
      expect(result.shouldAnimate, isTrue);
      expect(result.position.x, 358); // hidden slot
      expect(m.isHidden, isTrue);
    });

    test('dragging back out of the hidden slot un-hides', () {
      final m = makeMachine();
      m.restore(358, 200);
      expect(m.isHidden, isTrue);
      m.dragStart();
      m.dragMove(-100, 0);
      m.dragEnd();
      expect(m.isHidden, isFalse);
      expect(m.position.x, 258);
    });

    test('toggle hides to the slot and restores the saved position', () {
      final m = makeMachine();
      final hide = m.toggleHideShow();
      expect(hide.isHiding, isTrue);
      expect(hide.target, const BubblePoint(358, 100));
      expect(m.isHidden, isTrue);

      final show = m.toggleHideShow();
      expect(show.isHiding, isFalse);
      expect(show.target, const BubblePoint(270, 100));
      expect(m.isHidden, isFalse);
    });

    test('forceHide/forceShow round-trip (pushToSide)', () {
      final m = makeMachine();
      expect(m.forceShow(), isNull); // not hidden yet
      final hidden = m.forceHide();
      expect(hidden, const BubblePoint(358, 100));
      expect(m.forceHide(), isNull); // already hidden
      final shown = m.forceShow();
      expect(shown, const BubblePoint(270, 100));
    });

    test('rotation keeps a hidden bubble pinned to the new hidden slot', () {
      final m = makeMachine();
      m.restore(358, 200);
      final corrected = m.setScreenMetrics(
        width: 844,
        height: 390,
        left: 59,
        top: 0,
        bottom: 21,
      );
      expect(corrected, isNotNull);
      expect(corrected!.x, 844 - 32);
      expect(m.isHidden, isTrue);
    });

    test('rotation re-clamps a visible bubble into bounds', () {
      final m = makeMachine();
      m.restore(300, 700);
      final corrected = m.setScreenMetrics(
        width: 390,
        height: 500,
        left: 0,
        top: 59,
        bottom: 34,
      );
      expect(corrected, isNotNull);
      expect(corrected!.y, 500 - 32 - 34);
    });
  });
}
