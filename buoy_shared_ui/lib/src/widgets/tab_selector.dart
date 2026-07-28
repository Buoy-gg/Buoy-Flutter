import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import '../macos_colors.dart';

/// Port of shared-ui's TabSelector — the Filters/Copy pill switcher in the
/// filter view's header. RN: 28px row, hover bg, radius 6, padding 2; active
/// tab = primary20 bg + primary border, uppercase 12/600 labels.
class TabSelector extends StatelessWidget {
  const TabSelector({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.onTabChange,
  });

  /// key → label.
  final List<({String key, String label})> tabs;
  final String activeTab;
  final ValueChanged<String> onTabChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: BuoyColors.hover,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: BuoyColors.border),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: TouchableOpacity(
                  activeOpacity: 0.2,
                  onTap: () => onTabChange(tab.key),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: activeTab == tab.key
                        ? BoxDecoration(
                            color: BuoyColors.primary.hexAlpha(0x20),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: BuoyColors.primary),
                          )
                        : null,
                    // The row is a fixed 28pt, so a label that doesn't fit must
                    // ellipsize — left to wrap it would blow the height out
                    // (RN's Text just clips inside the fixed-height pill).
                    child: Text(
                      tab.label.toUpperCase(),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: activeTab == tab.key
                            ? BuoyColors.primary
                            : BuoyColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
