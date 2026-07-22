import 'package:flutter/material.dart';

import '../macos_colors.dart';

/// Ports of shared-ui's Badge.tsx MethodBadge/TypeBadge (the variants the
/// network row uses, `size="small"`) plus the row's status/pending/error and
/// request-client badges.

/// Badge.tsx METHOD_COLORS (buoyColors-based).
Color methodBadgeColor(String method) => switch (method.toUpperCase()) {
  'GET' => BuoyColors.success,
  'POST' => BuoyColors.primary,
  'PUT' => BuoyColors.warning,
  'PATCH' => BuoyColors.textSecondary,
  'DELETE' => BuoyColors.error,
  'HEAD' => BuoyColors.textMuted,
  'OPTIONS' => BuoyColors.primary,
  _ => const Color(0xFF6B7280),
};

/// MethodBadge size="small": padH 6 / padV 2 / fontSize 11 / w700, minWidth
/// 45, radius 4, bg color15, border color40.
class MethodBadge extends StatelessWidget {
  const MethodBadge({super.key, required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final color = methodBadgeColor(method);
    return Container(
      constraints: const BoxConstraints(minWidth: 45),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.hexAlpha(0x40)),
      ),
      child: Text(
        method.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Badge.tsx TypeBadge size="small" — the row's content-type chip (JSON/XML/
/// IMG…). Labels aren't in its type-color map, so they render the muted
/// fallback (RN parity).
class ContentTypeBadge extends StatelessWidget {
  const ContentTypeBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF6B7280); // Badge.tsx getTypeColor fallback
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.hexAlpha(0x40)),
      ),
      child: Text(
        type,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Row status badge trio (NetworkEventItemCompact.StatusIndicator):
/// pending "…" w/ clock, error "ERR" w/ alert, else the status code text.
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.status,
    required this.error,
    required this.statusColor,
  });

  final int? status;
  final String? error;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final isPending = status == null && error == null;
    if (isPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: MacOSColors.warning.hexAlpha(0x26),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            Icon(Icons.schedule, size: 10, color: MacOSColors.warning),
            Text(
              '...',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: MacOSColors.warning,
              ),
            ),
          ],
        ),
      );
    }
    if (error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: MacOSColors.error.hexAlpha(0x26),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            Icon(Icons.error_outline, size: 10, color: MacOSColors.error),
            Text(
              'ERR',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: MacOSColors.error,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(
        '$status',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: statusColor,
        ),
      ),
    );
  }
}

/// Request-client badge (fetch / GQL / gRPC / XHR / …) — RN's inline color
/// table in NetworkEventItemCompact.
class RequestClientBadge extends StatelessWidget {
  const RequestClientBadge({super.key, required this.client});

  final String client;

  @override
  Widget build(BuildContext context) {
    final color = switch (client) {
      'fetch' => const Color(0xFF4A90E2),
      'graphql' => const Color(0xFFE535AB),
      'grpc-web' => const Color(0xFF10B981),
      'xhr' => const Color(0xFFF59E0B),
      _ => const Color(0xFF9333EA),
    };
    final label = switch (client) {
      'graphql' => 'GQL',
      'grpc-web' => 'gRPC',
      'xhr' => 'XHR',
      _ => client,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x26), // rgba(…, 0.15)
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}
