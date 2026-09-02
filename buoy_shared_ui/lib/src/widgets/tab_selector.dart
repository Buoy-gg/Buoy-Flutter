import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

/// Port of shared-ui's TabSelector — the header tab strip, now the night
/// segmented control (RN night sweep): `#050505` track at radius 10 with a
/// hairline border and 3pt padding, `#161618` thumb at radius 8, 12/500
/// secondary labels (12/600 primary when active), and a 20×2 accent underline
/// with a soft glow under the active label.
///
/// Same props API it has always had, so every tool header that mounts it got
/// the night look in one shared edit. Visually identical to `NightSegmented`
/// at its compact size — new night-native code should prefer that primitive;
/// this widget exists so existing consumers convert without a code change.
class TabSelector extends StatelessWidget {
  const TabSelector({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.onTabChange,
    this.disabledKeys = const {},
  });

  /// key → label.
  final List<({String key, String label})> tabs;
  final String activeTab;
  final ValueChanged<String> onTabChange;

  /// Tabs to dim and refuse the press (RN `Tab.disabled`): the Render
  /// Highlighter's History tab is meaningless for a component with no
  /// recorded renders. The active tab is never dimmed, even when listed.
  final Set<String> disabledKeys;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: NightColor.bg,
        borderRadius: BorderRadius.circular(NightRadius.row),
        border: Border.all(color: NightColor.border),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: _TabButton(
                label: tab.label,
                active: activeTab == tab.key,
                disabled:
                    disabledKeys.contains(tab.key) && activeTab != tab.key,
                onTap: () => onTabChange(tab.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: active
          ? BoxDecoration(
              color: NightColor.surfaceElevated,
              borderRadius: BorderRadius.circular(NightRadius.segment),
            )
          : null,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // The thumb is a fixed-height pill, so a label that doesn't fit
          // must ellipsize (RN's Text just clips inside it).
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: disabled
                  ? NightColor.textTertiary
                  : active
                      ? NightColor.text
                      : NightColor.textSecondary,
            ),
          ),
          // RN `underline`: absolute, bottom 1.5 of the BUTTON. The Stack is
          // inside the 5pt vertical padding, so bottom −(5 − 1.5) lands it
          // 1.5pt above the thumb's edge.
          if (active)
            Positioned(
              bottom: -3.5,
              child: Container(
                width: 20,
                height: 2,
                decoration: BoxDecoration(
                  color: NightColor.accent,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    BoxShadow(
                      color: NightColor.accent.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (disabled) return Opacity(opacity: 0.45, child: button);
    return TouchableOpacity(activeOpacity: 0.2, onTap: onTap, child: button);
  }
}
