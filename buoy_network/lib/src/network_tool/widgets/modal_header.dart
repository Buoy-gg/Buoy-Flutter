import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import '../macos_colors.dart';

/// Port of shared-ui's ModalHeader (container + Navigation/Content/Actions).
/// Rendered inside JsModal's headerContent slot, below the drag indicator.
/// RN: row, gap 8, minHeight 32, paddingLeft 4. The window-control dots live
/// in JsModal itself, so the row reserves right-side space for them.
class ModalHeader extends StatelessWidget {
  const ModalHeader({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.only(left: 4),
      child: Row(spacing: 8, children: children),
    );
  }
}

/// ModalHeader.Navigation — back chevron (padding 4, size 20).
class ModalHeaderBack extends StatelessWidget {
  const ModalHeaderBack({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: onBack,
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(
          Icons.chevron_left,
          size: 20,
          color: BuoyColors.textSecondary,
        ),
      ),
    );
  }
}

/// ModalHeader.Content — title text or arbitrary child (flex: 1).
class ModalHeaderContent extends StatelessWidget {
  const ModalHeaderContent({
    super.key,
    this.title,
    this.centered = false,
    this.noMargin = false,
    this.child,
  });

  final String? title;
  final bool centered;
  final bool noMargin;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = child != null
        ? child!
        : Text(
            title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              color: BuoyColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          );
    return Expanded(
      child: Padding(
        padding: noMargin
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 8),
        child: content,
      ),
    );
  }
}

/// ModalHeader.Actions — trailing button row (gap 6, right margin leaves
/// room for JsModal's window-control dots).
class ModalHeaderActions extends StatelessWidget {
  const ModalHeaderActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: children),
    );
  }
}

/// The network header's 32×32 action-button chrome (headerActionButton).
BoxDecoration headerActionButtonDecoration({bool active = false}) {
  return BoxDecoration(
    color: active ? MacOSColors.infoBackground : MacOSColors.backgroundHover,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: active
          ? MacOSColors.info.hexAlpha(0x40)
          : MacOSColors.borderDefault,
    ),
  );
}

/// A 32×32 icon action button (search / filter / power / trash).
class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.color,
    this.onTap,
    this.active = false,
    this.decoration,
    this.disabled = false,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool active;
  final BoxDecoration? decoration;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 32,
      height: 32,
      decoration: decoration ?? headerActionButtonDecoration(active: active),
      child: Icon(icon, size: 14, color: color),
    );
    if (disabled) return Opacity(opacity: 0.55, child: button);
    return TouchableOpacity(activeOpacity: 0.2, onTap: onTap, child: button);
  }
}
