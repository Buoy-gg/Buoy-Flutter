import 'package:flutter/material.dart';

/// RN's hex-suffix alpha idiom (`color + "40"`) as an extension, so ported
/// style code can keep the exact same alpha bytes as the RN styles.
extension MacOSHexAlpha on Color {
  Color hexAlpha(int alphaByte) => withValues(alpha: alphaByte / 255);
}

/// 1:1 port of shared-ui's `macOSColors` (macOSDesignSystemColors.ts) —
/// the palette every network-tool style below references.
class MacOSColors {
  // Background
  static const backgroundBase = Color(0xFF0A0A0C);
  static const backgroundCard = Color(0xFF1A1A1C);
  static const backgroundHover = Color(0xFF1D1D1F);
  static const backgroundInput = Color(0xFF26262A);

  // Border
  static const borderDefault = Color(0xFF2D2D2F);

  /// Input field borders (RN `macOSColors.border.input`) — a step lighter than
  /// [borderDefault] so a field reads as editable next to a plain divider.
  static const borderInput = Color(0xFF3D3D42);

  // Text
  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFFA1A1A6);
  static const textMuted = Color(0xFF8E8E93);
  static const textDisabled = Color(0xFF9E9EA0);

  // Semantic
  static const success = Color(0xFF34C759);
  static const successBackground = Color(0x2634C759); // rgba(52,199,89,0.15)
  static const error = Color(0xFFFF453A);
  static const errorBackground = Color(0x26FF453A); // rgba(255,69,58,0.15)
  static const warning = Color(0xFFFFEB3B);
  static const warningBackground = Color(0x26FFEB3B); // rgba(255,235,59,0.15)
  static const info = Color(0xFF00B8E6);
  static const infoBackground = Color(0x1A00B8E6); // rgba(0,184,230,0.1)
  static const debug = Color(0xFFBF5AF2);

  // Data types (syntax highlighting in the data viewer)
  static const typeObject = Color(0xFF00B8E6);
  static const typeArray = Color(0xFFFFEB3B);
  static const typeString = Color(0xFF34C759);
  static const typeNumber = Color(0xFFFF9F0A);
  static const typeBoolean = Color(0xFFBF5AF2);
  static const typeFunction = Color(0xFF5E5CE6);
  static const typeUndefined = Color(0xFF8E8E93);
  static const typeNull = Color(0xFFFF453A);
}

/// shared-ui `buoyColors` (gameUIColors.ts) — the components that predate the
/// macOS palette (ModalHeader, TabSelector, badges, DynamicFilterView) style
/// with these instead.
class BuoyColors {
  static const base = Color(0xFF121212);
  static const card = Color(0xFF1A1A1A);

  /// Card fill for surfaces that sit over a ToolBackground: translucent so the
  /// field reads through, but calibrated against the BRIGHTEST scene in the
  /// catalogue (Live Sky's noon clouds, ~215 luminance) so a card's backing
  /// stays ≤ ~45 luminance and text never washes out. Over the "off" preset it
  /// is visually indistinguishable from [card]. RN `buoyColors.cardScrim`
  /// = rgba(10,13,20,0.9).
  static const cardScrim = Color.fromRGBO(10, 13, 20, 0.9);
  static const hover = Color(0xFF242424);
  static const input = Color(0xFF2A2A2A);
  static const border = Color(0xFF333333);
  static const borderStrong = Color(0xFF444444);
  static const text = Color(0xFFE0E0E0);
  static const textSecondary = Color(0xFFA0A0A0);
  static const textMuted = Color(0xFF888888);
  static const primary = Color(0xFF20C997); // Buoy teal
  static const success = Color(0xFF20C997);
  static const warning = Color(0xFFFFA94D);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF00B8E6);
}
