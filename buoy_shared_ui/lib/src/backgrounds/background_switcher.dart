/// Ports the strip of packages/shared/src/ui/backgrounds/BackgroundSwitcher.tsx
/// — the ‹ prev / next › chooser. Shipping mount: the dial menu's settings
/// modal (pass `embedded` there so the host card supplies the chrome). It
/// writes to the shared [BackgroundStore], so stepping here changes the
/// background in every tool at once.
///
/// RN's second row — the Live Sky wall-clock scrubber — is not ported: Live
/// Sky has no Flutter renderer yet (see registry.dart).
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';

import '../macos_colors.dart';
import 'background_store.dart';
import 'registry.dart';

class BackgroundSwitcher extends StatelessWidget {
  const BackgroundSwitcher({super.key, this.embedded = false});

  /// The host card supplies border/fill/margins.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BackgroundStore.instance,
      builder: (context, _) {
        final store = BackgroundStore.instance;
        final preset = getPreset(store.id);
        final counterpart = preset.counterpart;
        final row = Row(
          spacing: 8,
          children: [
            _StepButton(
              icon: BuoyIcons.chevronLeft,
              label: 'Previous background',
              onTap: store.previous,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    spacing: 5,
                    children: [
                      const BuoyGlyph(BuoyIcons.palette, size: 11, color: MacOSColors.info),
                      Flexible(
                        child: Text(
                          preset.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MacOSColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${store.index + 1}/${store.count}',
                        style: const TextStyle(
                          color: MacOSColors.textMuted,
                          fontSize: 10,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      preset.blurb,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: MacOSColors.textSecondary, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
            if (counterpart != null)
              TouchableOpacity(
                activeOpacity: 0.7,
                onTap: () => store.setId(counterpart.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(38, 38, 42, 0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: MacOSColors.borderDefault),
                  ),
                  child: Text(
                    counterpart.label,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: MacOSColors.textMuted,
                    ),
                  ),
                ),
              ),
            _StepButton(
              icon: BuoyIcons.chevronRight,
              label: 'Next background',
              onTap: store.next,
            ),
          ],
        );
        if (embedded) return row;
        return Container(
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            // Deliberately translucent: the strip sits ON the background it
            // is previewing, so you can see the field through it.
            color: const Color.fromRGBO(26, 26, 28, 0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MacOSColors.borderDefault),
          ),
          child: row,
        );
      },
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.label, required this.onTap});
  final LucideIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: onTap,
        // RN hitSlop 8.
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(38, 38, 42, 0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MacOSColors.borderDefault),
            ),
            child: Center(child: BuoyGlyph(icon, size: 16, color: MacOSColors.textSecondary)),
          ),
        ),
      ),
    );
  }
}
