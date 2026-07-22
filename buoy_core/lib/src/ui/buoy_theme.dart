import 'package:flutter/material.dart';

/// Floating-menu palette, matching @buoy-gg/floating-tools-core `colors.ts`
/// and shared-ui's `buoyColors` (gameUIColors.ts).
class BuoyTheme {
  /// Dark panel background (buoyColors.card).
  static const panel = Color(0xFF1A1A1A);

  /// Muted gray for secondary elements (buoyColors.textMuted).
  static const muted = Color(0xFF888888);

  /// Primary text color (buoyColors.text).
  static const secondary = Color(0xFFE0E0E0);

  /// Buoy teal — primary/success/active/drag accent.
  static const teal = Color(0xFF20C997);

  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFFFA94D);

  /// Dial backdrop: rgba(0, 0, 0, 0.85) — dialColors.dialBackdrop.
  static const dialBackdrop = Color(0xD9000000);

  // buoyColors surfaces/borders/text (settings modal etc.).
  static const base = Color(0xFF121212);
  static const card = Color(0xFF1A1A1A);
  static const hover = Color(0xFF242424);
  static const border = Color(0xFF333333);
  static const textSecondary = Color(0xFFA0A0A0);
  static const info = Color(0xFF00B8E6);
}
