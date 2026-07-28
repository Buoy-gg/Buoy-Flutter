/// Ports packages/impersonate/src/impersonate/components/ImpersonateHistoryList.tsx.
///
/// Recently-impersonated users for quick switching. Each row is a [UserCard]
/// with a live relative-time stamp (RN's per-item `useRelativeTime` → a
/// MinuteTicker-driven wrapper here). Empty state mirrors RN.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../impersonate_types.dart';
import 'user_card.dart';

/// RN `ImpersonateHistoryList`.
class ImpersonateHistoryList extends StatelessWidget {
  const ImpersonateHistoryList({
    super.key,
    required this.history,
    required this.currentUserId,
    required this.onSelectUser,
    this.onStopImpersonation,
    this.onRemoveFromHistory,
    this.onClearHistory,
  });

  final List<HistoryEntry> history;
  final String? currentUserId;
  final ValueChanged<ImpersonateUser> onSelectUser;
  final VoidCallback? onStopImpersonation;
  final ValueChanged<String>? onRemoveFromHistory;
  final VoidCallback? onClearHistory;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: BuoyColors.hover,
                  shape: BoxShape.circle,
                ),
                child: const BuoyGlyph(BuoyIcons.clock, size: 28, color: BuoyColors.textMuted),
              ),
              const SizedBox(height: 16),
              const Text(
                'No History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: BuoyColors.text,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Users you impersonate will appear here for quick access',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: BuoyColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact header (Recent · count · clear).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              const Text(
                'RECENT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BuoyColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: BuoyColors.hover,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${history.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: BuoyColors.textMuted,
                  ),
                ),
              ),
              const Spacer(),
              if (onClearHistory != null)
                TouchableOpacity(
                  activeOpacity: 0.7,
                  onTap: onClearHistory,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BuoyColors.hover,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const BuoyGlyph(
                      BuoyIcons.trash2,
                      size: 12,
                      color: BuoyColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            itemCount: history.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final entry = history[i];
              final isActive = currentUserId == entry.user.id;
              return _HistoryItemCard(
                entry: entry,
                isActive: isActive,
                onSelect: onSelectUser,
                onStop: onStopImpersonation,
                onRemove: onRemoveFromHistory == null
                    ? null
                    : () => onRemoveFromHistory!(entry.user.id),
                showRemoveButton: onRemoveFromHistory != null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// RN `HistoryItemCard` — resolves the live relative-time string per item.
class _HistoryItemCard extends StatefulWidget {
  const _HistoryItemCard({
    required this.entry,
    required this.isActive,
    required this.onSelect,
    required this.onStop,
    required this.onRemove,
    required this.showRemoveButton,
  });

  final HistoryEntry entry;
  final bool isActive;
  final ValueChanged<ImpersonateUser> onSelect;
  final VoidCallback? onStop;
  final VoidCallback? onRemove;
  final bool showRemoveButton;

  @override
  State<_HistoryItemCard> createState() => _HistoryItemCardState();
}

class _HistoryItemCardState extends State<_HistoryItemCard> {
  @override
  void initState() {
    super.initState();
    MinuteTicker.instance.retain();
  }

  @override
  void dispose() {
    MinuteTicker.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = DateTime.tryParse(widget.entry.lastUsedAt)?.millisecondsSinceEpoch;
    return ValueListenableBuilder<int>(
      valueListenable: MinuteTicker.instance.tick,
      builder: (context, _, _) => UserCard(
        user: widget.entry.user,
        isActive: widget.isActive,
        onPress: widget.isActive ? null : () => widget.onSelect(widget.entry.user),
        onStop: widget.isActive ? widget.onStop : null,
        onRemove: widget.onRemove,
        showRemoveButton: widget.showRemoveButton,
        lastUsedTime: ms == null ? null : formatRelativeTime(ms),
      ),
    );
  }
}
