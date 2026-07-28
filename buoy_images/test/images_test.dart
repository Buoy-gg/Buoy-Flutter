import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_images/src/image_format.dart';
import 'package:buoy_images/src/image_record.dart';
import 'package:buoy_images/src/images_store.dart';
import 'package:buoy_images/src/images_sync_adapter.dart';

/// Build a loaded record with an explicit intrinsic + layout for math tests.
ImageRecord _record({
  int id = 1,
  ImageLib lib = ImageLib.network,
  SourceKind kind = SourceKind.network,
  String uri = 'https://x/img.png',
  int? intrinsicW,
  int? intrinsicH,
  int? layoutW,
  int? layoutH,
  double dpr = 3.0,
  ImageStatus status = ImageStatus.loaded,
}) {
  final r = ImageRecord(
    id: id,
    lib: lib,
    uri: uri,
    sourceKind: kind,
    createdAt: 0,
  )
    ..status = status
    ..devicePixelRatio = dpr;
  if (intrinsicW != null && intrinsicH != null) {
    r.intrinsic = ImageDimensions(intrinsicW, intrinsicH);
  }
  if (layoutW != null && layoutH != null) {
    r.layout = ImageDimensions(layoutW, layoutH);
  }
  return r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('oversize audit math (RN imageEventStore parity)', () {
    test('neededPixels = layout × devicePixelRatio', () {
      final r = _record(layoutW: 40, layoutH: 40, dpr: 3.0);
      final needed = neededPixels(r);
      expect(needed, isNotNull);
      expect(needed!.width, 120);
      expect(needed.height, 120);
    });

    test('neededPixels null without a layout', () {
      expect(neededPixels(_record()), isNull);
    });

    test('oversizeFactor is the area-normalized linear factor', () {
      // 240×240 decoded into a 120×120 needed box → sqrt(4) = 2.0.
      final r = _record(
        intrinsicW: 240,
        intrinsicH: 240,
        layoutW: 40,
        layoutH: 40,
        dpr: 3.0,
      );
      expect(oversizeFactor(r), closeTo(2.0, 1e-9));
    });

    test('oversizeFactor 1.0 when right-sized', () {
      final r = _record(
        intrinsicW: 120,
        intrinsicH: 120,
        layoutW: 40,
        layoutH: 40,
        dpr: 3.0,
      );
      expect(oversizeFactor(r), closeTo(1.0, 1e-9));
    });

    test('estDecodedBytes = w × h × 4 (RGBA)', () {
      final r = _record(intrinsicW: 100, intrinsicH: 50);
      expect(estDecodedBytes(r), 100 * 50 * 4);
    });

    test('estWastedBytes = (intrinsicArea − neededArea) × 4, floored at 0', () {
      final r = _record(
        intrinsicW: 240,
        intrinsicH: 240,
        layoutW: 40,
        layoutH: 40,
        dpr: 3.0,
      );
      // 240² − 120² = 57600 − 14400 = 43200 px → ×4.
      expect(estWastedBytes(r), (240 * 240 - 120 * 120) * 4);
    });

    test('estWastedBytes is 0 for an undersized source', () {
      final r = _record(
        intrinsicW: 60,
        intrinsicH: 60,
        layoutW: 40,
        layoutH: 40,
        dpr: 3.0,
      );
      expect(estWastedBytes(r), 0);
    });
  });

  group('sizeVerdict thresholds (RN format.ts parity)', () {
    SizeVerdict verdictFor(double factor) {
      // Pick an intrinsic that yields the target factor at a 120px needed box.
      final needed = 120.0;
      final side = (needed * factor).round();
      return sizeVerdict(_record(
        intrinsicW: side,
        intrinsicH: side,
        layoutW: 40,
        layoutH: 40,
        dpr: 3.0,
      ));
    }

    test('< 0.9 → upscaled (info)', () {
      final v = verdictFor(0.5);
      expect(v.label, contains('upscaled'));
      expect(v.color, MacOSColors.info);
    });
    test('within 1.1 → right-sized (success)', () {
      final v = verdictFor(1.0);
      expect(v.label, 'right-sized');
      expect(v.color, MacOSColors.success);
    });
    test('≤ 1.5 → oversized (warning)', () {
      final v = verdictFor(1.4);
      expect(v.label, contains('oversized'));
      expect(v.color, MacOSColors.warning);
    });
    test('> 1.5 → oversized (error)', () {
      final v = verdictFor(3.0);
      expect(v.label, contains('oversized'));
      expect(v.color, MacOSColors.error);
    });
  });

  group('cacheBadge (RN format.ts parity)', () {
    test('memory → MEMORY green', () {
      final r = _record()..cacheVerdict = CacheVerdict.memory;
      final b = cacheBadge(r);
      expect(b.label, 'MEMORY');
      expect(b.color, MacOSColors.success);
    });
    test('disk → DISK yellow', () {
      final r = _record()..cacheVerdict = CacheVerdict.disk;
      final b = cacheBadge(r);
      expect(b.label, 'DISK');
      expect(b.color, MacOSColors.warning);
    });
    test('none/network → NETWORK red', () {
      final r = _record()..cacheVerdict = CacheVerdict.none;
      final b = cacheBadge(r);
      expect(b.label, 'NETWORK');
      expect(b.color, MacOSColors.error);
    });
    test('progressSeen alone → NETWORK red', () {
      final r = _record()..progressSeen = true;
      expect(cacheBadge(r).label, 'NETWORK');
    });
  });

  group('computeStats (RN parity)', () {
    test('counts statuses, network loads, decoded/wasted bytes', () {
      final list = [
        _record(id: 1, intrinsicW: 240, intrinsicH: 240, layoutW: 40, layoutH: 40)
          ..progressSeen = true,
        _record(id: 2, status: ImageStatus.error),
        _record(id: 3, status: ImageStatus.loading),
      ];
      final stats = computeStats(list);
      expect(stats.total, 3);
      expect(stats.loaded, 1);
      expect(stats.errors, 1);
      expect(stats.loading, 1);
      expect(stats.networkLoads, 1);
      expect(stats.estDecodedBytes, 240 * 240 * 4);
      expect(stats.estWastedBytes, (240 * 240 - 120 * 120) * 4);
    });
  });

  group('computeInsights + insightChips (RN store/insights.ts parity)', () {
    test('duplicate URLs, retry storms, missing alt, layout shifts', () {
      final list = [
        _record(id: 1, uri: 'a')..hasAltText = false,
        _record(id: 2, uri: 'a'),
        _record(id: 3, uri: 'b')
          ..loadCount = 6
          ..layoutShifts = 2,
      ];
      final ins = computeInsights(list);
      expect(ins.duplicates.length, 1);
      expect(ins.duplicates.first.uri, 'a');
      expect(ins.duplicates.first.count, 2);
      expect(ins.retryStorms.length, 1);
      expect(ins.retryStorms.first.loadCount, 6);
      expect(ins.missingAlt, 1);
      expect(ins.layoutShifters.length, 1);

      final chips = insightChips(ins);
      expect(chips.any((c) => c.contains('duplicate')), isTrue);
      expect(chips.any((c) => c.contains('retry storm')), isTrue);
      expect(chips.any((c) => c.contains('missing alt')), isTrue);
      expect(chips.any((c) => c.contains('layout-shifting')), isTrue);
    });

    test('all clear → no chips', () {
      expect(insightChips(computeInsights([_record()])), isEmpty);
    });
  });

  group('sync adapter wire shape (RN imagesSyncAdapter.ts parity)', () {
    test('version 1 and the exact RN action names', () {
      expect(imagesSyncAdapter.version, 1);
      expect(
        imagesSyncAdapter.actions.keys.toSet(),
        containsAll(<String>{
          'list',
          'getDetail',
          'hardReload',
          'retry',
          'flash',
          'setOverride',
          'clearOverride',
          'massAction',
          'setNetworkMode',
          'setBlankImages',
          'clearRecords',
          'getCaptureStatus',
        }),
      );
    });

    test('getSnapshot has stats/captureStatus/globalModes/insights/records', () {
      final snap = imagesSyncAdapter.getSnapshot()! as Map<String, Object?>;
      expect(snap.keys, containsAll(<String>['stats', 'captureStatus', 'globalModes', 'insights', 'records']));
      final capture = snap['captureStatus']! as Map;
      expect(capture['installed'], isTrue);
      final modes = snap['globalModes']! as Map;
      expect(modes['network'], 'normal');
      expect(modes['blank'], isFalse);
    });

    test('toWire (via list action) exposes the RN record fields', () {
      final record = ImagesStore.instance.createRecord(
        lib: ImageLib.cached,
        uri: 'https://x/pikachu.png',
        sourceKind: SourceKind.network,
      );
      record
        ..status = ImageStatus.loaded
        ..intrinsic = const ImageDimensions(240, 240)
        ..layout = const ImageDimensions(40, 40)
        ..devicePixelRatio = 3.0
        ..durationMs = 42.7
        ..cacheVerdict = CacheVerdict.none
        ..cacheVerdictSource = 'queryCache'
        ..progressSeen = true
        ..loadCount = 1;

      final result = imagesSyncAdapter.actions['list']!({'limit': 50})
          as Map<String, Object?>;
      final records = result['records']! as List;
      final wire = records.first as Map<String, Object?>;
      expect(
        wire.keys,
        containsAll(<String>[
          'id', 'lib', 'uri', 'kind', 'status', 'mounted', 'cache',
          'cacheSource', 'ms', 'intrinsic', 'layout', 'neededPx',
          'oversizeFactor', 'decodedKB', 'wastedKB', 'progressSeen',
          'bytesTotal', 'error', 'errorCode', 'loadCount', 'overrideLabel',
          'hasAltText', 'layoutShifts', 'ageMs',
        ]),
      );
      // Newest-first: the record we just created is first.
      expect(wire['uri'], 'https://x/pikachu.png');
      expect(wire['lib'], 'cached');
      expect(wire['ms'], 43); // rounded
      expect(wire['cache'], 'none');
      expect(wire['oversizeFactor'], 2.0);
      expect((wire['intrinsic'] as Map)['width'], 240);
      expect((wire['neededPx'] as Map)['width'], 120);
    });

    test('massAction restore + setNetworkMode round-trip', () {
      final restore =
          imagesSyncAdapter.actions['massAction']!({'kind': 'restore'}) as Map;
      expect(restore['ok'], isTrue);
      final net = imagesSyncAdapter.actions['setNetworkMode']!({'mode': 'cold'})
          as Map;
      expect(net['ok'], isTrue);
      expect((net['modes'] as Map)['network'], 'cold');
      // reset
      imagesSyncAdapter.actions['setNetworkMode']!({'mode': 'normal'});
    });
  });
}
