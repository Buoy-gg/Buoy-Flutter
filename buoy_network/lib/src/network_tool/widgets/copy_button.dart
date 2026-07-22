import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:buoy_core/buoy_core.dart';
import '../macos_colors.dart';

/// Port of shared-ui's CopyButton: copy icon → green check for 1.5s on
/// success, warning triangle on failure. `value` may be a lazy `Object?
/// Function()` (RN's latest-ref pattern for expensive copy text). Pro gating
/// dropped — the Flutter example has no license system.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.value,
    this.size = 16,
    this.idleColor,
    this.successColor,
    this.errorColor,
    this.enabled = true,
    this.decoration,
    this.width,
    this.height,
  });

  final Object? value;
  final double size;
  final Color? idleColor;
  final Color? successColor;
  final Color? errorColor;
  final bool enabled;

  /// Optional chrome (the 32×32 header action button look).
  final BoxDecoration? decoration;
  final double? width;
  final double? height;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

enum _CopyState { idle, success, error }

class _CopyButtonState extends State<CopyButton> {
  _CopyState _state = _CopyState.idle;
  Timer? _resetTimer;

  static String stringify(Object? value) {
    if (value is String) return value;
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return '$value';
    }
  }

  Future<void> _copy() async {
    final raw = widget.value;
    final resolved = raw is Object? Function() ? raw() : raw;
    _resetTimer?.cancel();
    try {
      await Clipboard.setData(ClipboardData(text: stringify(resolved)));
      setState(() => _state = _CopyState.success);
    } catch (_) {
      setState(() => _state = _CopyState.error);
    }
    // RN feedbackDuration default 1500ms.
    _resetTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _state = _CopyState.idle);
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (_state) {
      _CopyState.success => (
        Icons.check_circle_outline,
        widget.successColor ?? MacOSColors.success,
      ),
      _CopyState.error => (
        Icons.warning_amber_rounded,
        widget.errorColor ?? MacOSColors.error,
      ),
      _CopyState.idle => (
        Icons.content_copy,
        widget.enabled
            ? (widget.idleColor ?? MacOSColors.textSecondary)
            : MacOSColors.textDisabled,
      ),
    };
    final child = Container(
      width: widget.width,
      height: widget.height,
      padding: widget.decoration == null ? const EdgeInsets.all(4) : null,
      decoration: widget.decoration,
      alignment: Alignment.center,
      child: Icon(icon, size: widget.size, color: color),
    );
    if (!widget.enabled) return Opacity(opacity: 0.55, child: child);
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: _state == _CopyState.idle ? _copy : null,
      child: child,
    );
  }
}
