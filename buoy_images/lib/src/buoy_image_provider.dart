/// Synthetic image providers backing the simulation overrides (RN
/// capture/overrides.ts resolveOverrideSource).
///
/// RN swaps a wrapped image's `source` to a bogus `file://` (instant error) or
/// a blackhole IP (loads forever). Flutter can express both directly with tiny
/// providers instead of relying on network behaviour, so simulations are
/// instant and offline-safe.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Always fails immediately — the analog of RN's forced-error `file://` source.
/// Identity equality (no `==` override) keeps each instance out of the shared
/// cache so the error never poisons a real key.
class ForcedErrorImageProvider extends ImageProvider<ForcedErrorImageProvider> {
  const ForcedErrorImageProvider();

  @override
  Future<ForcedErrorImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ForcedErrorImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    ForcedErrorImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(
        Exception('Forced error (Buoy Images simulation)'),
      ),
    );
  }
}

/// Never completes — the analog of RN's forced-loading blackhole-IP source.
class HangImageProvider extends ImageProvider<HangImageProvider> {
  const HangImageProvider();

  @override
  Future<HangImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<HangImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    HangImageProvider key,
    ImageDecoderCallback decode,
  ) {
    // A completer that never fires → the stream stays pending forever.
    return OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
  }
}

/// Decode helper: intrinsic (physical) pixel size of a decoded frame.
ui.Size intrinsicSize(ImageInfo info) => ui.Size(
  info.image.width.toDouble(),
  info.image.height.toDouble(),
);
