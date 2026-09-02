/// Ports packages/shared/src/ui/backgrounds/ToolBackground.tsx — the drop-in
/// animated backdrop for a Buoy tool surface. Non-hit-testing and absolute,
/// so it never affects layout and never eats a touch. The preset comes from
/// the shared persisted selection ([BackgroundStore]), so switching it in one
/// tool switches it in all of them.
///
/// `JsModal` (buoy_core) mounts it behind every night-variant modal through
/// the `toolBackgroundBuilder` seam — see [installToolBackground].
library;

import 'package:buoy_core/buoy_core.dart' as core;
import 'package:flutter/widgets.dart';

import 'background_store.dart';
import 'background_switcher.dart';
import 'registry.dart';
import 'types.dart';

/// Round the measured size into 8px buckets. Presets lay out from
/// width/height, so an unbucketed measurement would rebuild the whole field
/// on every frame of a modal resize drag; at this granularity nobody can see
/// the difference and a drag costs a handful of rebuilds instead of hundreds.
double _bucket(double n) => n <= 0 ? 0 : (n / 8).ceil() * 8.0;

class ToolBackground extends StatelessWidget {
  const ToolBackground({super.key, this.id, this.motion, this.opacity = 1});

  /// Force a specific preset instead of following the shared selection. The
  /// switcher's live preview uses this; tools should omit it.
  final BackgroundId? id;

  /// Force motion off regardless of the shared setting.
  final bool? motion;

  /// Multiplied into the whole layer's opacity — dial it down per tool.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: BackgroundStore.instance,
        builder: (context, _) {
          final store = BackgroundStore.instance;
          final preset = getPreset(id ?? store.id);
          final animated = motion ?? store.motion;
          final builder = preset.builder;
          if (builder == null) return const SizedBox.expand();
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = _bucket(constraints.maxWidth);
              final h = _bucket(constraints.maxHeight);
              if (w <= 0 || h <= 0) return const SizedBox.expand();
              final child = SizedBox.expand(child: builder(context, w, h, animated));
              return opacity == 1 ? child : Opacity(opacity: opacity, child: child);
            },
          );
        },
      ),
    );
  }
}

/// Publish [ToolBackground] to buoy_core's `toolBackgroundBuilder` seam so
/// every night-variant `JsModal` draws it. Idempotent; the `buoy` umbrella
/// and every tool's `registerBuoyX()` call it, so a bare-core install (no
/// tools) is the only way to end up without a backdrop.
void installToolBackground() {
  core.toolBackgroundBuilder ??= (context) => const ToolBackground();
  core.backgroundSwitcherBuilder ??=
      (context) => const BackgroundSwitcher(embedded: true);
}
