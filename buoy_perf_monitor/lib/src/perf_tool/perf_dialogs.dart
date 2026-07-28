/// Ports packages/perf-monitor/src/perf-monitor/components/SaveBenchmarkPrompt.tsx
/// plus the RN `Alert.alert(...)` confirmations used across the tool.
///
/// Flutter deviation (structural, not visual): Buoy mounts its dev tools in
/// `MaterialApp.builder`, i.e. ABOVE the app's Navigator, so `showDialog` has
/// no Navigator to push onto. Both prompts are therefore in-tree overlays —
/// a `Positioned.fill` backdrop + centered card — rendered by whichever
/// surface owns the state, exactly like RN's `<Modal transparent>`.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

const String _mono = 'monospace';

/// Shared backdrop + centered card chrome (RN `styles.backdrop` / `.card`:
/// rgba(0,0,0,0.55) scrim, maxWidth 360, radius 12, padH 18 / padV 16).
class PerfDialogShell extends StatelessWidget {
  const PerfDialogShell({
    super.key,
    required this.onDismiss,
    required this.child,
    this.maxWidth = 360,
  });

  final VoidCallback onDismiss;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DefaultTextStyle(
        style: const TextStyle(
          decoration: TextDecoration.none,
          color: MacOSColors.textPrimary,
          fontSize: 13,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: const ColoredBox(color: Color(0x8C000000)),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    decoration: BoxDecoration(
                      color: MacOSColors.backgroundCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MacOSColors.borderDefault),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x80000000),
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name-and-save prompt shown when a recording is stopped inline from the HUD
/// (RN `SaveBenchmarkPrompt`). Pre-fills the auto-generated name; Discard
/// drops the report.
class SaveBenchmarkPrompt extends StatefulWidget {
  const SaveBenchmarkPrompt({
    super.key,
    required this.defaultName,
    required this.onSave,
    required this.onCancel,
    this.sampleCount,
  });

  final String defaultName;

  /// Number of samples captured in this run; surfaced as a small subtitle.
  final int? sampleCount;
  final void Function(String name) onSave;
  final VoidCallback onCancel;

  @override
  State<SaveBenchmarkPrompt> createState() => _SaveBenchmarkPromptState();
}

class _SaveBenchmarkPromptState extends State<SaveBenchmarkPrompt> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.defaultName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _controller.text.trim();
    widget.onSave(trimmed.isNotEmpty ? trimmed : widget.defaultName);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.sampleCount;
    return PerfDialogShell(
      onDismiss: widget.onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Save recording',
            style: TextStyle(
              color: MacOSColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            count != null
                ? '$count ${count == 1 ? "sample" : "samples"} captured'
                : 'Name this run so you can compare it later.',
            style: const TextStyle(
              color: MacOSColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          PerfTextField(
            controller: _controller,
            hintText: widget.defaultName,
            autofocus: true,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PerfDialogButton(
                  label: 'Discard',
                  onTap: widget.onCancel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PerfDialogButton(
                  label: 'Save',
                  primary: true,
                  onTap: _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A confirmation with up to three actions — the Dart stand-in for RN's
/// `Alert.alert(title, message, [...])`.
class PerfConfirmAction {
  const PerfConfirmAction({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
}

class PerfConfirmDialog extends StatelessWidget {
  const PerfConfirmDialog({
    super.key,
    required this.title,
    required this.onCancel,
    required this.actions,
    this.message,
    this.cancelLabel = 'Cancel',
  });

  final String title;
  final String? message;
  final String cancelLabel;
  final VoidCallback onCancel;
  final List<PerfConfirmAction> actions;

  @override
  Widget build(BuildContext context) {
    return PerfDialogShell(
      onDismiss: onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: MacOSColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: const TextStyle(
                color: MacOSColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PerfDialogButton(label: cancelLabel, onTap: onCancel),
              ),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PerfDialogButton(
                    label: action.label,
                    primary: !action.destructive,
                    destructive: action.destructive,
                    onTap: action.onPressed,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Informational one-button notice (RN `Alert.alert(title, body)`).
class PerfNoticeDialog extends StatelessWidget {
  const PerfNoticeDialog({
    super.key,
    required this.title,
    required this.onDismiss,
    this.message,
  });

  final String title;
  final String? message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return PerfDialogShell(
      onDismiss: onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: MacOSColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: const TextStyle(
                color: MacOSColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          PerfDialogButton(label: 'OK', primary: true, onTap: onDismiss),
        ],
      ),
    );
  }
}

/// RN `styles.button` (radius 8, padV 11): neutral = input bg + border,
/// primary = info fill with near-black label, destructive = error tint.
class PerfDialogButton extends StatelessWidget {
  const PerfDialogButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
    this.disabled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    Color? border;
    if (destructive) {
      bg = MacOSColors.errorBackground;
      fg = MacOSColors.error;
      border = MacOSColors.error.withValues(alpha: 0x55 / 255);
    } else if (primary) {
      bg = MacOSColors.info;
      fg = const Color(0xFF0A0A0C);
    } else {
      bg = MacOSColors.backgroundInput;
      fg = MacOSColors.textSecondary;
      border = MacOSColors.borderDefault;
    }
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: border != null ? Border.all(color: border) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared text input matching RN's `styles.input` (input bg, radius 8, padH 12
/// / padV 10, 1px border, mono).
class PerfTextField extends StatelessWidget {
  const PerfTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.autofocus = false,
    this.onSubmitted,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MacOSColors.backgroundInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        textAlign: textAlign,
        onSubmitted: onSubmitted,
        cursorColor: MacOSColors.info,
        style: const TextStyle(
          color: MacOSColors.textPrimary,
          fontSize: 13,
          fontFamily: _mono,
          decoration: TextDecoration.none,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          hintText: hintText,
          hintStyle: const TextStyle(
            color: MacOSColors.textMuted,
            fontSize: 13,
            fontFamily: _mono,
          ),
        ),
      ),
    );
  }
}
