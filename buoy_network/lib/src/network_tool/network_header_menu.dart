/// Ports packages/network/src/network/components/NetworkHeaderMenu.tsx — the
/// header's overflow menu.
///
/// The toolbar had grown past what a 402pt screen holds. Something had to
/// leave, and the rule for deciding what is:
///
///   **A control that COMMUNICATES STATE stays visible. A destination or a rare
///   action goes in the menu.**
///
/// That keeps the power toggle (are we capturing?), the overrides flask (is the
/// app being lied to, and how many rules?), the status badges (what happened)
/// and Clear (the reproduce loop is clear → repro → read, and burying the first
/// step doubles it). Search stays because it's the only way through 500 rows.
///
/// Filters and Copy leave. Filters is the interesting one — it does show state,
/// so the ⋮ carries a dot when a filter is applied rather than hiding that
/// fact.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

/// The ⋮ itself. Uses the shared `more-vertical` glyph — RN draws its three
/// dots by hand because its icon set has no ellipsis; the BIF set does.
class NetworkHeaderMenuButton extends StatelessWidget {
  const NetworkHeaderMenuButton({
    super.key,
    required this.onTap,
    this.isOpen = false,
    this.hasIndicator = false,
  });

  final VoidCallback onTap;

  /// The menu is showing — the button holds a lit state and closes on tap.
  final bool isOpen;

  /// Something behind the menu is active — currently a filter.
  final bool hasIndicator;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isOpen ? 'Close menu' : 'More actions',
      child: TouchableOpacity(
        activeOpacity: 0.2,
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  // Lit only while the menu is down — the button is the one
                  // thing the backdrop doesn't cover, so it has to look like
                  // the thing that is currently open.
                  color: isOpen
                      ? MacOSColors.backgroundHover
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: BuoyGlyph(
                  BuoyIcons.moreVertical,
                  size: 14,
                  color: isOpen
                      ? MacOSColors.textPrimary
                      : MacOSColors.textSecondary,
                ),
              ),
              if (hasIndicator)
                Positioned(
                  top: 6,
                  right: 8,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: MacOSColors.info,
                      shape: BoxShape.circle,
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

/// The dropdown, rendered over the modal BODY rather than inside the header —
/// the header is a fixed-height row and anything overflowing it is clipped, so
/// a panel anchored to the top-right of the body lands exactly where a dropdown
/// from the ⋮ should appear.
class NetworkHeaderMenu extends StatelessWidget {
  const NetworkHeaderMenu({
    super.key,
    required this.onClose,
    required this.children,
  });

  final VoidCallback onClose;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: const ColoredBox(color: Color(0x80000000)),
            ),
          ),
          Positioned(
            top: 6,
            right: 8,
            // An explicit width, NOT RN's `minWidth: 196`. A Positioned with
            // only top/right is laid out with 0..infinity width, and a Column
            // with `stretch` inside an unbounded width throws — so the direct
            // port rendered nothing at all. Flexbox sizes to content; Flutter
            // needs the bound stated.
            width: 220,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: MacOSColors.backgroundCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MacOSColors.borderInput),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NetworkHeaderMenuItem extends StatelessWidget {
  const NetworkHeaderMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.iconColor,
  });

  final LucideIcon icon;
  final String label;
  final VoidCallback onTap;

  /// Right-aligned state, e.g. the active filter count.
  final String? detail;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: BuoyGlyph(
                icon,
                size: 14,
                color: iconColor ?? MacOSColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MacOSColors.textPrimary,
                ),
              ),
            ),
            if (detail != null)
              Text(
                detail!,
                style: const TextStyle(
                  fontSize: 11,
                  color: MacOSColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
