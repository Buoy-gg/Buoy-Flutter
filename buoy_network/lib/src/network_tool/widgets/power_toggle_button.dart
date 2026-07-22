import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import '../macos_colors.dart';

/// Port of shared-ui's PowerToggleButton — green when capture is enabled,
/// red when paused. Medium size: 32×32 button, 14px icon, radius 8.
class PowerToggleButton extends StatelessWidget {
  const PowerToggleButton({
    super.key,
    required this.isEnabled,
    required this.onToggle,
  });

  final bool isEnabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final color = isEnabled ? MacOSColors.success : MacOSColors.error;
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onToggle,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isEnabled
              ? MacOSColors.successBackground
              : MacOSColors.errorBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.hexAlpha(0x40)),
        ),
        child: Icon(Icons.power_settings_new, size: 14, color: color),
      ),
    );
  }
}
