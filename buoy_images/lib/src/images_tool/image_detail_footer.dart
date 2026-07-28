/// Ports packages/images/src/components/ImageDetailFooter.tsx — the detail
/// view's bottom navbar: previous/next stepping at the edges, per-image
/// actions in the middle (hard reload / retry), and a simulation row
/// (error / loading / blank / find / restore), with inline feedback.
library;

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../image_record.dart';
import '../images_actions.dart';

class ImageDetailFooter extends StatefulWidget {
  const ImageDetailFooter({
    super.key,
    required this.record,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final ImageRecord record;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  State<ImageDetailFooter> createState() => _ImageDetailFooterState();
}

class _ImageDetailFooterState extends State<ImageDetailFooter> {
  String? _message;

  void _run(ActionResult Function() action) {
    setState(() => _message = '…');
    final result = action();
    setState(() => _message = result.message);
  }

  void _simulate(OverrideKind kind, String label) {
    ImagesActions.instance.setOverride(
      widget.record.id,
      ImageOverride(source: OverrideSource(kind), label: label),
    );
    setState(() => _message = '$label — Restore to undo');
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final disabled = !record.mounted;
    final overrideActive = record.overrideLabel != null;
    final insets = MediaQuery.viewPaddingOf(context);

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + insets.bottom),
      decoration: const BoxDecoration(
        color: MacOSColors.backgroundBase,
        border: Border(top: BorderSide(color: MacOSColors.borderDefault)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_message != null)
            _feedback(_message!, MacOSColors.info)
          else if (disabled)
            _feedback(
              'Instance unmounted — reload actions need the image on screen.',
              MacOSColors.textMuted,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _navButton(BuoyIcons.chevronLeft, widget.hasPrevious,
                  widget.hasPrevious ? widget.onPrevious : null),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  'Hard reload',
                  icon: BuoyIcons.refreshCw,
                  disabled: disabled,
                  onTap: () =>
                      _run(() => ImagesActions.instance.hardReloadRecord(record)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  record.status == ImageStatus.error ? 'Retry' : 'Reload',
                  disabled: disabled,
                  onTap: () =>
                      _run(() => ImagesActions.instance.retryRecord(record)),
                ),
              ),
              const SizedBox(width: 8),
              _navButton(BuoyIcons.chevronRight, widget.hasNext,
                  widget.hasNext ? widget.onNext : null),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _simButton('Error', disabled,
                  () => _simulate(OverrideKind.error, 'Forced error')),
              const SizedBox(width: 8),
              _simButton('Loading', disabled,
                  () => _simulate(OverrideKind.hang, 'Forced loading')),
              const SizedBox(width: 8),
              _simButton('Blank', disabled,
                  () => _simulate(OverrideKind.blank, 'Blanked')),
              const SizedBox(width: 8),
              _simButton('Find', disabled, () {
                ImagesActions.instance.flashRecord(record.id);
                setState(() =>
                    _message = 'Flashing a red border on the image (2.5s)');
              }),
              const SizedBox(width: 8),
              _simButton('Restore', !overrideActive, () {
                ImagesActions.instance.clearOverride(record.id);
                setState(() =>
                    _message = 'Override removed — original source restored');
              }, accent: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _feedback(String text, Color color) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontFamily: 'monospace',
      ),
    ),
  );

  Widget _navButton(LucideIcon icon, bool enabled, VoidCallback? onTap) {
    final button = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
      ),
      child: BuoyGlyph(
        icon,
        size: 20,
        color: enabled ? MacOSColors.textPrimary : MacOSColors.textMuted,
      ),
    );
    if (!enabled || onTap == null) return Opacity(opacity: 0.4, child: button);
    return TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: button);
  }

  Widget _actionButton(
    String label, {
    LucideIcon? icon,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacOSColors.borderDefault, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            BuoyGlyph(
              icon,
              size: 13,
              color: disabled ? MacOSColors.textMuted : MacOSColors.info,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: disabled ? MacOSColors.textMuted : MacOSColors.textPrimary,
            ),
          ),
        ],
      ),
    );
    if (disabled) return Opacity(opacity: 0.4, child: child);
    return TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: child);
  }

  Widget _simButton(
    String label,
    bool disabled,
    VoidCallback onTap, {
    bool accent = false,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacOSColors.borderDefault, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: disabled
              ? MacOSColors.textMuted
              : accent
                  ? MacOSColors.warning
                  : MacOSColors.textSecondary,
        ),
      ),
    );
    if (disabled) return Expanded(child: Opacity(opacity: 0.4, child: child));
    return Expanded(
      child: TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: child),
    );
  }
}
