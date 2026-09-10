import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import '../generated/power_toggle_button_styles.g.dart';
import '../macos_colors.dart';

/// Ports packages/shared/src/ui/components/PowerToggleButton.tsx — green when
/// capture is enabled, red when paused.
///
/// Sizes are the RN ternaries (`size === "small" ? 28 : 32` box,
/// `? 12 : 14` icon); every other number comes from
/// [PowerToggleButtonStyles], generated from the RN style table.
enum PowerToggleSize { small, medium }

class PowerToggleButton extends StatelessWidget {
  const PowerToggleButton({
    super.key,
    required this.isEnabled,
    required this.onToggle,
    this.size = PowerToggleSize.medium,
    this.disabled = false,
  });

  final bool isEnabled;
  final VoidCallback onToggle;

  /// RN `size` — "small" is the 28×28 box the toolbars use.
  final PowerToggleSize size;

  /// RN `disabled` — dims the whole button and drops the press handler.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final Color color = isEnabled ? MacOSColors.success : MacOSColors.error;
    final double box = size == PowerToggleSize.small ? 28 : 32;
    final double icon = size == PowerToggleSize.small ? 12 : 14;
    final Widget button = Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: isEnabled
            ? PowerToggleButtonStyles.styles_enabledButton_backgroundColor
            : PowerToggleButtonStyles.styles_disabledButton_backgroundColor,
        borderRadius: BorderRadius.circular(
          PowerToggleButtonStyles.styles_button_borderRadius,
        ),
        border: Border.all(
          color: isEnabled
              ? PowerToggleButtonStyles.styles_enabledButton_borderColor
              : PowerToggleButtonStyles.styles_disabledButton_borderColor,
          width: PowerToggleButtonStyles.styles_button_borderWidth,
        ),
      ),
      child: BuoyGlyph(BuoyIcons.power, size: icon, color: color),
    );
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: disabled ? null : onToggle,
      child: disabled
          ? Opacity(
              opacity: PowerToggleButtonStyles.styles_buttonDisabled_opacity,
              child: button,
            )
          : button,
    );
  }
}
