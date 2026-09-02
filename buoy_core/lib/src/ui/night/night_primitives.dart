/// Ports packages/shared/src/ui/night/primitives.tsx — the building blocks of
/// the Everlights-style surface (tokens: `night_theme.dart`). In buoy_core,
/// not shared_ui, because the dial's settings sheet is built from them and
/// nothing below core may depend on shared_ui; shared_ui re-exports them.
///
/// The shape they compose to:
///
///   NightSectionLabel   STORAGE                ← outside the card, uppercase
///   NightCard           ┌──────────────────┐
///     NightRows         │ row              │   ← hairline-separated children
///                       │ ────────────     │
///                       │ row              │
///                       └──────────────────┘
///   NightFootnote       Settings persist through…
///
/// Controls: [NightSwitch] (the Everlights 56×32 toggle), [NightChip]
/// (zone-style pill), [NightButton] (primary = filled accent w/ dark ink,
/// everything else on the #1C1C1C plate), [NightSegmented] (the All/Day
/// control with the accent underline), [NightBadge] (small status caps).
library;

import 'package:flutter/material.dart';

import '../touchable_opacity.dart';
import 'night_theme.dart';

/// Uppercase section label that sits ABOVE a [NightCard]. RN: textSecondary,
/// 12/600, tracking 0.8, marginBottom 8, marginLeft 4.
class NightSectionLabel extends StatelessWidget {
  const NightSectionLabel(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: Night.labelInset),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: NightColor.textSecondary,
          fontSize: NightFont.label,
          fontWeight: FontWeight.w600,
          letterSpacing: Night.labelTracking,
        ).merge(style),
      ),
    );
  }
}

enum NightFootnoteTone { tertiary, secondary, warning, danger }

/// Explanatory line under a [NightCard] (or above a CTA, `centered`). RN:
/// 13/500, lineHeight 1.4, marginTop 8, marginLeft 4 (0 when centered).
class NightFootnote extends StatelessWidget {
  const NightFootnote(
    this.text, {
    super.key,
    this.centered = false,
    this.tone = NightFootnoteTone.tertiary,
    this.style,
  });

  final String text;
  final bool centered;
  final NightFootnoteTone tone;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      NightFootnoteTone.tertiary => NightColor.textTertiary,
      NightFootnoteTone.secondary => NightColor.textSecondary,
      NightFootnoteTone.warning => NightColor.warning,
      NightFootnoteTone.danger => NightColor.danger,
    };
    return Padding(
      padding: EdgeInsets.only(top: 8, left: centered ? 0 : Night.labelInset),
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          color: color,
          fontSize: NightFont.caption,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ).merge(style),
      ),
    );
  }
}

/// A card: `#0C0C0C`, radius 14, hairline border, clipped. `padded` =
/// interior 14 with a 10pt gap between children (pass a [Column] with
/// `spacing: 10` to get the gap; the card only adds the padding).
class NightCard extends StatelessWidget {
  const NightCard({super.key, required this.child, this.padded = false});

  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: padded ? const EdgeInsets.all(Night.cardPad) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: NightColor.surface,
        borderRadius: BorderRadius.circular(NightRadius.card),
        border: Border.all(color: NightColor.border),
      ),
      child: child,
    );
  }
}

/// Hairline separator between rows, inset from the left like iOS.
class NightSeparator extends StatelessWidget {
  const NightSeparator({super.key, this.inset = Night.rowPadH});

  final double inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: inset),
      child: Container(height: 0.5, color: NightColor.separator),
    );
  }
}

/// Interleaves a hairline between consecutive children so rows never track
/// their own position. Meant to live inside an unpadded [NightCard].
class NightRows extends StatelessWidget {
  const NightRows({super.key, required this.children, this.inset = Night.rowPadH});

  final List<Widget> children;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) NightSeparator(inset: inset),
          children[i],
        ],
      ],
    );
  }
}

// Everlights toggle geometry, verbatim.
const double _trackW = 56;
const double _trackH = 32;
const double _thumb = 22;
const double _trackPad = 5;
const double _travel = _trackW - _thumb - _trackPad * 2;

/// The Everlights 56×32 switch. The thumb slides (200ms); the colours snap
/// with the state change, which reads fine at this size.
class NightSwitch extends StatelessWidget {
  const NightSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final track = Container(
      width: _trackW,
      height: _trackH,
      padding: const EdgeInsets.symmetric(horizontal: _trackPad),
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: value ? NightColor.accentFill : NightColor.surfaceElevated,
        borderRadius: BorderRadius.circular(_trackH / 2),
        border: Border.all(
          color: value ? NightColor.accentBorderStrong : NightColor.fillTertiary,
        ),
      ),
      child: AnimatedSlide(
        // AnimatedSlide is in fractions of the child's own size.
        offset: Offset(value ? _travel / _thumb : 0, 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Container(
          width: _thumb,
          height: _thumb,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? NightColor.accent : NightColor.knob,
          ),
        ),
      ),
    );
    final body = disabled ? Opacity(opacity: 0.4, child: track) : track;
    return Semantics(
      toggled: value,
      enabled: !disabled,
      child: TouchableOpacity(
        activeOpacity: 0.8,
        onTap: disabled ? null : () => onChanged(!value),
        // RN hitSlop 8 on every side.
        child: Padding(padding: const EdgeInsets.all(8), child: body),
      ),
    );
  }
}

/// Zone-style pill chip. The fill never changes — selection is signalled by
/// the border and label colour only, exactly like the Everlights zone row.
class NightChip extends StatelessWidget {
  const NightChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.disabled = false,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool disabled;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: NightColor.buttonSurface,
        borderRadius: BorderRadius.circular(NightRadius.chip),
        border: Border.all(
          width: 1.5,
          color: selected ? NightColor.accentBorderStrong : NightColor.fillTertiary,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          ?icon,
          Text(
            label,
            style: TextStyle(
              fontSize: NightFont.body,
              fontWeight: FontWeight.w500,
              color: selected ? NightColor.accent : NightColor.textSecondary,
            ),
          ),
        ],
      ),
    );
    if (disabled) return Opacity(opacity: 0.4, child: chip);
    if (onTap == null) return chip;
    return TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: chip);
  }
}

enum NightButtonVariant { primary, secondary, tertiary, destructive, ghost }

enum NightButtonSize { md, lg }

/// Everlights button. `primary` fills with the accent and takes DARK ink;
/// every other variant sits on the `#1C1C1C` plate and differs only in label
/// colour. `lg` is the fully-rounded 50pt CTA (md = 34pt).
class NightButton extends StatelessWidget {
  const NightButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = NightButtonVariant.secondary,
    this.size = NightButtonSize.lg,
    this.icon,
    this.disabled = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback onTap;
  final NightButtonVariant variant;
  final NightButtonSize size;
  final Widget? icon;
  final bool disabled;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final labelColor = switch (variant) {
      NightButtonVariant.primary => NightColor.onAccent,
      NightButtonVariant.tertiary => NightColor.text,
      NightButtonVariant.destructive => NightColor.danger,
      NightButtonVariant.secondary || NightButtonVariant.ghost => NightColor.accent,
    };
    final fill = switch (variant) {
      NightButtonVariant.primary => NightColor.accent,
      NightButtonVariant.ghost => Colors.transparent,
      _ => NightColor.button,
    };
    final lg = size == NightButtonSize.lg;
    final button = Container(
      height: lg ? 50 : 34,
      padding: EdgeInsets.symmetric(horizontal: lg ? 20 : 16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(lg ? 25 : 17),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          ?icon,
          Text(
            label,
            style: TextStyle(
              fontSize: lg ? 17 : 15,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
    if (disabled) return Opacity(opacity: 0.4, child: button);
    return TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: button);
  }
}

enum NightSegmentedSize { md, sm }

/// Segmented control: `#050505` track, `#161618` thumb, and the accent
/// underline glow beneath the active label (the Everlights All/Day tabs).
///
/// THE shared tab control for night-theme tool headers — the dial settings
/// and the network tool both mount this one. `sm` is the compact variant for
/// in-tool headers where the full-height control reads too tall (it is what
/// `TabSelector` renders).
class NightSegmented extends StatelessWidget {
  const NightSegmented({
    super.key,
    required this.tabs,
    required this.activeKey,
    required this.onChange,
    this.size = NightSegmentedSize.md,
  });

  final List<({String key, String label})> tabs;
  final String activeKey;
  final ValueChanged<String> onChange;
  final NightSegmentedSize size;

  @override
  Widget build(BuildContext context) {
    final small = size == NightSegmentedSize.sm;
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
              child: _Segment(
                label: tab.label,
                active: tab.key == activeKey,
                small: small,
                onTap: () => onChange(tab.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.small,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool small;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final padV = small ? 5.0 : 8.0;
    // RN underline: absolute, bottom 2 (sm 1.5) of the segment. The Stack is
    // inside the vertical padding, so shift by −(padV − bottom).
    final underlineBottom = small ? 1.5 : 2.0;
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(vertical: padV),
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
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: small ? 12 : NightFont.caption,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? NightColor.text : NightColor.textSecondary,
              ),
            ),
            if (active)
              Positioned(
                bottom: -(padV - underlineBottom),
                child: Container(
                  width: small ? 20 : 24,
                  height: small ? 2 : 2.5,
                  decoration: BoxDecoration(
                    color: NightColor.accent,
                    borderRadius: BorderRadius.circular(small ? 1 : 1.25),
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
      ),
    );
  }
}

enum NightBadgeTone { accent, warning, danger, info, neutral }

/// Small uppercase status cap ("FILE SYSTEM", "CONNECTED"). RN: padH 8 /
/// padV 4, radius 6, 11/600 tracking 0.5.
class NightBadge extends StatelessWidget {
  const NightBadge(this.label, {super.key, this.tone = NightBadgeTone.neutral});

  final String label;
  final NightBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch (tone) {
      NightBadgeTone.accent => (NightColor.accentSoft, NightColor.accent),
      NightBadgeTone.warning => (NightColor.warningSoft, NightColor.warning),
      NightBadgeTone.danger => (NightColor.dangerSoft, NightColor.danger),
      NightBadgeTone.info => (NightColor.infoSoft, NightColor.info),
      NightBadgeTone.neutral => (NightColor.fillSecondary, NightColor.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(NightRadius.badge),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: NightFont.micro,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: ink,
        ),
      ),
    );
  }
}
