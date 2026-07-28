/// Ports packages/impersonate/src/impersonate/components/UserCard.tsx.
///
/// A user row for search results + history: avatar, name (+ role badge), email,
/// monospace id, and contextual actions (Play to select, PowerToggle to stop an
/// active user, X to remove from history). Paddings/fonts/radii mirror RN.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../impersonate_types.dart';
import 'user_avatar.dart';

/// RN `UserCard`.
class UserCard extends StatelessWidget {
  const UserCard({
    super.key,
    required this.user,
    this.isActive = false,
    this.onPress,
    this.onStop,
    this.onRemove,
    this.showRemoveButton = false,
    this.lastUsedTime,
  });

  final ImpersonateUser user;
  final bool isActive;
  final VoidCallback? onPress;
  final VoidCallback? onStop;
  final VoidCallback? onRemove;
  final bool showRemoveButton;

  /// Rendered as a relative-time string bottom-right (history only).
  final String? lastUsedTime;

  @override
  Widget build(BuildContext context) {
    final displayName = user.displayName ?? user.email ?? user.id;
    final showEmail = user.email != null && user.displayName != null;
    final role = user.metadata?['role'] is String
        ? user.metadata!['role'] as String
        : null;

    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: isActive ? null : onPress,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isActive
                  ? BuoyColors.success.hexAlpha(0x10)
                  : BuoyColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? BuoyColors.success.hexAlpha(0x40)
                    : BuoyColors.border,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar
                UserAvatar(
                  userId: user.id,
                  name: displayName,
                  showActiveIndicator: isActive,
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isActive
                                    ? BuoyColors.success
                                    : BuoyColors.text,
                              ),
                            ),
                          ),
                          if (role != null) ...[
                            const SizedBox(width: 8),
                            _RoleBadge(role: role),
                          ],
                        ],
                      ),
                      if (showEmail) ...[
                        const SizedBox(height: 2),
                        Text(
                          user.email!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: BuoyColors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${user.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: BuoyColors.textMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive)
                      PowerToggleButton(
                        isEnabled: true,
                        onToggle: onStop ?? () {},
                      )
                    else
                      TouchableOpacity(
                        activeOpacity: 0.7,
                        onTap: onPress,
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: BuoyColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const BuoyGlyph(
                            BuoyIcons.play,
                            size: 14,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    if (showRemoveButton && onRemove != null && !isActive) ...[
                      const SizedBox(width: 8),
                      TouchableOpacity(
                        activeOpacity: 0.7,
                        onTap: onRemove,
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: BuoyColors.hover,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: BuoyColors.border),
                          ),
                          child: const BuoyGlyph(
                            BuoyIcons.x,
                            size: 12,
                            color: BuoyColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Timestamp — bottom right.
          if (lastUsedTime != null)
            Positioned(
              bottom: 8,
              right: 10,
              child: Text(
                lastUsedTime!,
                style: const TextStyle(fontSize: 10, color: BuoyColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BuoyColors.hover,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        role.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: BuoyColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
