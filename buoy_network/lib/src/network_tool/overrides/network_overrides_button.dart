/// Ports packages/network/src/network/components/NetworkOverridesButton.tsx —
/// the header's flask, and the always-visible "overrides are active" warning.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../../overrides/override_rules_store.dart';

/// The Overrides entry point, and the tool's standing warning.
///
/// The active tint is not decoration. A rule left enabled from yesterday makes
/// the app behave wrongly in a way that looks exactly like a real bug, so the
/// tool has to keep saying so from the top level — Chrome shows the same
/// warning in its Overrides pane for the same reason. It stays in the toolbar
/// rather than moving into the overflow menu precisely BECAUSE it carries
/// state: a "you are not seeing the truth" warning inside a menu is a warning
/// nobody sees.
///
/// Rebuilds itself off the store rather than taking a count as a prop, so the
/// modal shell doesn't re-render every time a rule records a hit.
class NetworkOverridesButton extends StatefulWidget {
  const NetworkOverridesButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<NetworkOverridesButton> createState() => _NetworkOverridesButtonState();
}

class _NetworkOverridesButtonState extends State<NetworkOverridesButton> {
  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _unsubscribe = OverrideRulesStore.instance.subscribe(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = OverrideRulesStore.instance.activeCount;
    final active = count > 0;

    return Semantics(
      button: true,
      label: active
          ? 'Response overrides — $count active'
          : 'Response overrides',
      child: TouchableOpacity(
        activeOpacity: 0.2,
        onTap: widget.onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 32,
                height: 32,
                // The standard header-action box, with the warning colour
                // swapped in when armed — the same shape as search/power/clear
                // because it is the same kind of control.
                decoration: BoxDecoration(
                  color: active
                      ? MacOSColors.warningBackground
                      : MacOSColors.backgroundHover,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active
                        ? MacOSColors.warning.hexAlpha(0x77)
                        : MacOSColors.borderDefault,
                  ),
                ),
                child: BuoyGlyph(
                  BuoyIcons.flaskConical,
                  size: 14,
                  color: active
                      ? MacOSColors.warning
                      : MacOSColors.textSecondary,
                ),
              ),
              if (active)
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 12),
                    height: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MacOSColors.warning,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    // The count is already in the button's own label; without
                    // this a screen reader reads "Response overrides — 1
                    // active, 1".
                    child: ExcludeSemantics(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: MacOSColors.backgroundBase,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
