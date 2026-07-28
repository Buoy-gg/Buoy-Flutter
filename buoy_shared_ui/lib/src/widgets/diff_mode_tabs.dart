/// Ports packages/shared/src/ui/components/EventHistoryViewer/DiffModeTabs.tsx
/// (+ its `DiffModeTab` type). A horizontal tab bar for switching diff modes
/// (e.g. "TREE VIEW" / "SPLIT VIEW"). Dumb component — state is external.
///
/// RN numerics: row bg card, radius 6, padding 4; active tab = info-background
/// + info40 border; labels 11/600 monospace uppercase, letter-spacing 0.5.
library;

import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../macos_colors.dart';

/// RN `DiffModeTab`.
class DiffModeTab {
  const DiffModeTab({required this.key, required this.label, this.disabled = false});
  final String key;
  final String label;
  final bool disabled;
}

class DiffModeTabs extends StatelessWidget {
  const DiffModeTabs({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.onTabChange,
  });

  final List<DiffModeTab> tabs;
  final String activeTab;
  final ValueChanged<String> onTabChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _tab(tabs[i])),
          ],
        ],
      ),
    );
  }

  Widget _tab(DiffModeTab tab) {
    final isActive = activeTab == tab.key;
    final isDisabled = tab.disabled;
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive ? MacOSColors.infoBackground : const Color(0x00000000),
        borderRadius: BorderRadius.circular(4),
        border: isActive
            ? Border.all(color: MacOSColors.info.hexAlpha(0x40))
            : null,
      ),
      child: Text(
        tab.label,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: isDisabled
              ? MacOSColors.textMuted
              : isActive
                  ? MacOSColors.textPrimary
                  : MacOSColors.textSecondary,
        ),
      ),
    );
    if (isDisabled) return Opacity(opacity: 0.4, child: content);
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: () => onTabChange(tab.key),
      child: content,
    );
  }
}
