/// Ports the `Alert.alert(...)` confirmations the RN storage editor uses
/// (GameUIStorageBrowser's "Couldn't save", StorageKeyEditorScreen's "Unsaved
/// changes").
///
/// Flutter deviation (structural, not visual): Buoy mounts its dev tools in
/// `MaterialApp.builder`, i.e. ABOVE the app's Navigator, so `showDialog` has
/// no Navigator to push onto. These are in-tree overlays instead — a
/// `Positioned.fill` backdrop plus a centered card, rendered by whichever
/// surface owns the state. Same precedent (and chrome) as buoy_perf_monitor's
/// `PerfDialogShell`; it lives there rather than in shared-ui because each tool
/// ports its own RN alerts.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

/// One non-cancel button. RN's `style: "destructive"` becomes [destructive].
class StorageAlertAction {
  const StorageAlertAction({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool destructive;
}

class StorageAlert extends StatelessWidget {
  const StorageAlert({
    super.key,
    required this.title,
    required this.onCancel,
    required this.actions,
    this.message,
    this.cancelLabel = 'Cancel',
  });

  final String title;
  final String? message;

  /// The dismissing button — RN's `style: "cancel"`. Also fires on a backdrop
  /// tap, which is the expected way out.
  final String cancelLabel;
  final VoidCallback onCancel;
  final List<StorageAlertAction> actions;

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
                onTap: onCancel,
                child: const ColoredBox(color: Color(0x8C000000)),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 360),
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
                        if (message case final text?) ...[
                          const SizedBox(height: 8),
                          Text(
                            text,
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
                              child: _AlertButton(
                                label: cancelLabel,
                                onTap: onCancel,
                              ),
                            ),
                            for (final action in actions) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: _AlertButton(
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

class _AlertButton extends StatelessWidget {
  const _AlertButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive ? MacOSColors.error : MacOSColors.success;
    return TouchableOpacity(
      activeOpacity: 0.6,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: primary ? accent : null,
          borderRadius: BorderRadius.circular(10),
          border: primary
              ? null
              : Border.all(
                  color: destructive
                      ? MacOSColors.error.hexAlpha(0x55)
                      : MacOSColors.borderDefault,
                ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: primary
                ? MacOSColors.backgroundBase
                : (destructive
                      ? MacOSColors.error
                      : MacOSColors.textSecondary),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
