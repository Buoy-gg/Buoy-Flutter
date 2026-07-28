/// Ports packages/impersonate/src/impersonate/components/UserAvatar.tsx.
///
/// Avatar with initials on a deterministic color derived from the user id, plus
/// an optional active-indicator dot. Sizes + the 10-color palette + the hash
/// are byte-for-byte from the RN source.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

/// RN `AVATAR_COLORS` (indigo → blue).
const List<Color> avatarColors = [
  Color(0xFF6366F1), // Indigo
  Color(0xFF8B5CF6), // Purple
  Color(0xFFEC4899), // Pink
  Color(0xFFF43F5E), // Rose
  Color(0xFFF97316), // Orange
  Color(0xFFEAB308), // Yellow
  Color(0xFF22C55E), // Green
  Color(0xFF14B8A6), // Teal
  Color(0xFF06B6D4), // Cyan
  Color(0xFF3B82F6), // Blue
];

/// RN `UserAvatarProps.size`.
enum AvatarSize { small, medium, large }

/// RN `SIZES` — container / font / indicator px per size.
({double container, double font, double indicator}) _sizeConfig(AvatarSize s) =>
    switch (s) {
      AvatarSize.small => (container: 24, font: 10, indicator: 8),
      AvatarSize.medium => (container: 36, font: 14, indicator: 10),
      AvatarSize.large => (container: 44, font: 16, indicator: 12),
    };

/// Initials from a name or email. RN `getInitials`.
String getInitials(String name) {
  if (name.isEmpty) return '?';
  if (name.contains('@')) return name[0].toUpperCase();
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

/// Deterministic color from a user id. RN `getAvatarColor` (djb2-ish hash with
/// signed 32-bit overflow matched to JS bitwise semantics).
Color getAvatarColor(String userId) {
  var hash = 0;
  for (var i = 0; i < userId.length; i++) {
    // JS: hash = charCode + ((hash << 5) - hash), truncated to 32-bit signed.
    hash = userId.codeUnitAt(i) + ((hash << 5) - hash);
    hash = hash.toSigned(32);
  }
  return avatarColors[hash.abs() % avatarColors.length];
}

/// RN `UserAvatar`.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.name,
    this.size = AvatarSize.medium,
    this.showActiveIndicator = false,
    this.backgroundColor,
  });

  final String userId;
  final String name;
  final AvatarSize size;
  final bool showActiveIndicator;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final s = _sizeConfig(size);
    final color = backgroundColor ?? getAvatarColor(userId);
    return SizedBox(
      // Room for the indicator to overflow the circle's bottom-right.
      width: s.container,
      height: s.container,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: s.container,
            height: s.container,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              getInitials(name),
              style: TextStyle(
                color: Colors.white,
                fontSize: s.font,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (showActiveIndicator)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: s.indicator,
                height: s.indicator,
                decoration: BoxDecoration(
                  color: BuoyColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: BuoyColors.card, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
