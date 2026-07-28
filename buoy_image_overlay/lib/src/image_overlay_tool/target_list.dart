/// Ports packages/image-overlay/src/imageOverlay/components/TargetList.tsx.
///
/// The list of discovered [BuoyImageTarget]s, styled like highlight-updates'
/// RenderListItem: a teal side bar, the label, a testID badge, and the owning
/// component name.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../image_overlay_types.dart';

class TargetList extends StatelessWidget {
  const TargetList({
    super.key,
    required this.targets,
    required this.onSelect,
  });

  final List<DiscoveredTarget> targets;
  final ValueChanged<DiscoveredTarget> onSelect;

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No targets found',
              style: TextStyle(
                color: BuoyColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Wrap widgets with\nBuoyImageTarget(label: "YourLabel")',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BuoyColors.textMuted,
                fontSize: 12,
                height: 18 / 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      children: [
        for (final target in targets)
          _TargetRow(target: target, onSelect: () => onSelect(target)),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target, required this.onSelect});

  final DiscoveredTarget target;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: BuoyColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BuoyColors.border),
        ),
        child: Row(
          children: [
            // colorIndicator
            Container(
              width: 4,
              height: 36,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: BuoyColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: BuoyColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // testID badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              BuoyColors.success.withValues(alpha: 0x20 / 255),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const BuoyGlyph(BuoyIcons.hash,
                                size: 8, color: BuoyColors.success),
                            const SizedBox(width: 3),
                            const Text(
                              'testID',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: BuoyColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          target.testID,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: BuoyColors.text,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (target.componentName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        target.componentName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFA855F7),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const BuoyGlyph(BuoyIcons.chevronRight,
                size: 16, color: BuoyColors.textMuted),
          ],
        ),
      ),
    );
  }
}
