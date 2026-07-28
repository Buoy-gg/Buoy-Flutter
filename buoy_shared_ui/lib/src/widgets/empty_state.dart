import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';


/// Ports packages/shared/src/ui/components/EmptyState.tsx — consistent empty /
/// no-data displays. Container centers content (maxWidth 300, padding 32). Icon
/// default size 48, color #4B5563, marginBottom 16. Title #6B7280 16/500
/// (marginBottom 8); description #4B5563 14 (lineHeight 20). Optional action
/// button: bg rgba(59,130,246,0.1), border rgba(59,130,246,0.2), text #3B82F6.

enum EmptyStateVariant { normal, minimal, card }

class EmptyStateAction {
  const EmptyStateAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.iconSize = 48,
    this.iconColor = const Color(0xFF4B5563),
    this.action,
    this.variant = EmptyStateVariant.normal,
  });

  final String title;
  final String? description;
  final LucideIcon? icon;
  final double iconSize;
  final Color iconColor;
  final EmptyStateAction? action;
  final EmptyStateVariant variant;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: BuoyGlyph(icon, size: iconSize, color: iconColor),
            ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                description!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 14,
                  height: 20 / 14,
                ),
              ),
            ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TouchableOpacity(
                activeOpacity: 0.7,
                onTap: action!.onPressed,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x1A3B82F6), // rgba(59,130,246,0.1)
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0x333B82F6)),
                  ),
                  child: Text(
                    action!.label,
                    style: const TextStyle(
                      color: Color(0xFF3B82F6),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final padding = variant == EmptyStateVariant.minimal
        ? const EdgeInsets.all(16)
        : const EdgeInsets.all(32);

    if (variant == EmptyStateVariant.card) {
      return Container(
        padding: padding,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF), // rgba(255,255,255,0.03)
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x0DFFFFFF)),
        ),
        child: content,
      );
    }
    return Container(padding: padding, alignment: Alignment.center, child: content);
  }
}

/// Pre-configured empty state for no-data scenarios.
class NoDataEmptyState extends StatelessWidget {
  const NoDataEmptyState({super.key});
  @override
  Widget build(BuildContext context) => const EmptyState(
        title: 'No data found',
        description: 'Data will appear here when available',
      );
}

/// Pre-configured empty state for filtered results.
class NoResultsEmptyState extends StatelessWidget {
  const NoResultsEmptyState({super.key});
  @override
  Widget build(BuildContext context) => const EmptyState(
        title: 'No matching results',
        description: 'Try adjusting your filters to see more results',
      );
}

/// Pre-configured empty state for search results.
class NoSearchResultsEmptyState extends StatelessWidget {
  const NoSearchResultsEmptyState({super.key, this.searchTerm});
  final String? searchTerm;
  @override
  Widget build(BuildContext context) => EmptyState(
        title: 'No search results',
        description: searchTerm != null
            ? 'No results found for "$searchTerm"'
            : 'Try a different search term',
      );
}
