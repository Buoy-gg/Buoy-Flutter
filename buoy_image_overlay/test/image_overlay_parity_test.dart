import 'package:buoy_image_overlay/buoy_image_overlay.dart';
import 'package:buoy_image_overlay/src/image_overlay_controller.dart'
    show computeAutoScale, computeFreePlacement;
import 'package:buoy_image_overlay/src/image_target_registry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Parity tests against packages/image-overlay/src/imageOverlay
// (ImageOverlayController.ts + fiberScanner.ts). Expected values mirror the RN
// logic.
void main() {
  final controller = ImageOverlayController.instance;

  setUp(() {
    controller.debugReset();
    debugClearImageTargets();
  });

  group('computeAutoScale (RN setImageUri autoScale)', () {
    test('targetWidth / imageWidth', () {
      expect(computeAutoScale(200, 400), 0.5);
      expect(computeAutoScale(300, 100), 3.0);
    });
    test('defaults to 1.0 when unknown or zero', () {
      expect(computeAutoScale(null, 400), 1.0);
      expect(computeAutoScale(200, null), 1.0);
      expect(computeAutoScale(200, 0), 1.0);
    });
  });

  group('computeFreePlacement (RN startFreeMode sizing)', () {
    const screen = Size(400, 800);
    test('small image is centered at intrinsic size', () {
      final p = computeFreePlacement(100, 200, screen);
      expect(p.width, 100);
      expect(p.height, 200);
      expect(p.x, (400 - 100) / 2);
      expect(p.y, (800 - 200) / 2);
    });
    test('oversize image scales to fit 80% width / 60% height', () {
      // 800x800 on a 400x800 screen: maxW=320, maxH=480 → ratio=min(0.4,0.6)=0.4
      final p = computeFreePlacement(800, 800, screen);
      expect(p.width, 320); // 800 * 0.4
      expect(p.height, 320);
      expect(p.x, (400 - 320) / 2);
    });
    test('null size falls back to 200x200', () {
      final p = computeFreePlacement(null, null, screen);
      expect(p.width, 200);
      expect(p.height, 200);
    });
  });

  group('providerForUri', () {
    test('http URL → NetworkImage', () {
      final p = providerForUri('https://example.com/a.png');
      expect(p, isA<NetworkImage>());
    });
    test('base64 data URI → MemoryImage', () {
      // 1x1 transparent PNG.
      const uri =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      expect(providerForUri(uri), isA<MemoryImage>());
    });
    test('non-base64 data URI and junk → null', () {
      expect(providerForUri('data:text/plain,hello'), isNull);
      expect(providerForUri('not a url'), isNull);
      expect(providerForUri('   '), isNull);
    });
  });

  group('controller state mutations', () {
    test('setOpacity clamps to [0,1]', () {
      controller.setOpacity(2.0);
      expect(controller.state.opacity, 1.0);
      controller.setOpacity(-1.0);
      expect(controller.state.opacity, 0.0);
      controller.setOpacity(0.42);
      expect(controller.state.opacity, 0.42);
    });

    test('setScale clamps to [0.01,5]', () {
      controller.setScale(99);
      expect(controller.state.scale, 5.0);
      controller.setScale(0);
      expect(controller.state.scale, 0.01);
    });

    test('toggleInvertX / toggleInvertY / setLocked', () {
      expect(controller.state.invertX, false);
      controller.toggleInvertX();
      expect(controller.state.invertX, true);
      controller.toggleInvertY();
      expect(controller.state.invertY, true);
      controller.setLocked(true);
      expect(controller.state.locked, true);
    });

    test('setOffset / setFreePosition / setFreeDimensions', () {
      controller.setOffset(10, -20);
      expect(controller.state.offsetX, 10);
      expect(controller.state.offsetY, -20);
      controller.setFreePosition(5, 6);
      expect(controller.state.freeX, 5);
      expect(controller.state.freeY, 6);
      controller.setFreeDimensions(30, 40, 1, 2);
      expect(controller.state.freeWidth, 30);
      expect(controller.state.freeHeight, 40);
    });

    test('toggle / setEnabled', () {
      expect(controller.state.enabled, false);
      controller.toggle();
      expect(controller.state.enabled, true);
      controller.setEnabled(false);
      expect(controller.state.enabled, false);
    });

    test('resetSettings (component mode) restores 0.5 opacity + zero offset', () {
      controller.setOpacity(0.9);
      controller.setOffset(50, 50);
      controller.resetSettings(const Size(400, 800));
      expect(controller.state.opacity, 0.5);
      expect(controller.state.offsetX, 0);
      expect(controller.state.offsetY, 0);
      expect(controller.state.scale, 1.0); // no target/image → autoScale 1.0
    });

    test('notifies listeners on mutation', () {
      var count = 0;
      void listener() => count++;
      controller.addListener(listener);
      controller.setOpacity(0.3);
      controller.toggle();
      controller.removeListener(listener);
      expect(count, 2);
    });

    test('reset clears everything back to defaults', () {
      controller
        ..setOpacity(0.1)
        ..toggleInvertX()
        ..setEnabled(true);
      controller.persistedImageUrl = 'https://x.com/a.png';
      controller.reset();
      final s = controller.state;
      expect(s.opacity, 0.5);
      expect(s.invertX, false);
      expect(s.enabled, false);
      expect(s.mode, isNull);
      expect(controller.persistedImageUrl, '');
    });
  });

  group('ImageOverlayState', () {
    test('defaults mirror RN DEFAULT_STATE', () {
      const s = ImageOverlayState();
      expect(s.opacity, 0.5);
      expect(s.scale, 1.0);
      expect(s.showOutline, true);
      expect(s.freeWidth, 200);
      expect(s.freeHeight, 200);
      expect(s.mode, isNull);
      expect(s.enabled, false);
    });

    test('copyWith clear flags force fields to null', () {
      const s = ImageOverlayState(
        mode: OverlayMode.free,
        imageWidth: 10,
        imageHeight: 20,
        targetRect: MeasuredRect(x: 0, y: 0, width: 1, height: 1),
      );
      final cleared = s.copyWith(
        clearMode: true,
        clearImageSize: true,
        clearTargetRect: true,
      );
      expect(cleared.mode, isNull);
      expect(cleared.imageWidth, isNull);
      expect(cleared.imageHeight, isNull);
      expect(cleared.targetRect, isNull);
    });
  });

  group('MeasuredRect', () {
    test('value equality', () {
      expect(
        const MeasuredRect(x: 1, y: 2, width: 3, height: 4),
        const MeasuredRect(x: 1, y: 2, width: 3, height: 4),
      );
      expect(
        const MeasuredRect(x: 1, y: 2, width: 3, height: 4),
        isNot(const MeasuredRect(x: 1, y: 2, width: 3, height: 5)),
      );
    });
  });

  group('scanForImageTargets (RN fiberScanner)', () {
    test('returns registered targets with image-target: testID, sorted', () {
      debugRegisterImageTarget('Zed', GlobalKey());
      debugRegisterImageTarget('Alpha', GlobalKey(), componentName: 'Card');
      final targets = scanForImageTargets();
      expect(targets.map((t) => t.label), ['Alpha', 'Zed']);
      expect(targets.first.testID, 'image-target:Alpha');
      expect(targets.first.componentName, 'Card');
    });

    test('empty when nothing registered', () {
      expect(scanForImageTargets(), isEmpty);
    });
  });
}
