/// Ports packages/shared/src/ui/backgrounds/types.ts.
library;

import 'package:flutter/widgets.dart';

/// The FULL RN catalogue, so a persisted pick made on any Buoy build round-
/// trips through the store. Presets without a Flutter renderer (see
/// `registry.dart`) fall back to [off] when drawn.
enum BackgroundId { off, deepfield, hyperspace, livesky, abyss, bubbles, jellyfish }

/// Shared contract for every preset: the measured surface size and whether
/// to run its loops. `animated: false` paints the field but starts no loops,
/// so a preset degrades to its (still good-looking) static form instead of
/// disappearing.
typedef BackgroundVariantBuilder = Widget Function(
  BuildContext context,
  double width,
  double height,
  bool animated,
);
