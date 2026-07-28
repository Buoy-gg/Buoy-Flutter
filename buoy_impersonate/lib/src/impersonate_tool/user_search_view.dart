/// Ports packages/impersonate/src/impersonate/components/UserSearchView.tsx.
///
/// The Search tab body: a not-configured warning, a loading row, an error card,
/// the results list (SectionHeader + UserCards), a no-results empty state, and
/// the pre-search EmptyState. Search input itself lives in the modal header.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../impersonate_types.dart';
import 'user_card.dart';

/// RN `UserSearchView`.
class UserSearchView extends StatelessWidget {
  const UserSearchView({
    super.key,
    required this.currentUser,
    required this.searchQuery,
    required this.searchResults,
    required this.isSearching,
    required this.searchError,
    required this.onSelectUser,
    required this.onStopImpersonation,
    this.searchAvailable = true,
  });

  final ImpersonateUser? currentUser;
  final String searchQuery;
  final List<ImpersonateUser> searchResults;
  final bool isSearching;
  final String? searchError;
  final ValueChanged<ImpersonateUser> onSelectUser;
  final VoidCallback onStopImpersonation;
  final bool searchAvailable;

  @override
  Widget build(BuildContext context) {
    // Results — own scroll container.
    if (searchResults.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!searchAvailable) _warning(),
          if (isSearching) _loading(),
          if (searchError != null) _error(searchError!),
          SectionHeader(title: 'Results', badgeCount: searchResults.length),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: searchResults.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final user = searchResults[i];
                final isCurrent = currentUser?.id == user.id;
                return UserCard(
                  user: user,
                  isActive: isCurrent,
                  onPress: isCurrent ? null : () => onSelectUser(user),
                  onStop: isCurrent ? onStopImpersonation : null,
                );
              },
            ),
          ),
        ],
      );
    }

    // No-results empty (searched, nothing matched, no error).
    if (searchQuery.isNotEmpty && !isSearching && searchError == null) {
      return Column(
        children: [
          if (!searchAvailable) _warning(),
          Expanded(child: _noResults()),
        ],
      );
    }

    // Loading / error / initial states.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!searchAvailable) _warning(),
        if (isSearching) _loading(),
        if (searchError != null) _error(searchError!),
        if (searchQuery.isEmpty && !isSearching && searchAvailable)
          const Expanded(
            child: EmptyState(
              title: 'Search for users',
              description:
                  'Tap the search icon in the header to find users by email, '
                  'name, or ID',
              icon: BuoyIcons.search,
              variant: EmptyStateVariant.minimal,
            ),
          ),
      ],
    );
  }

  Widget _warning() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BuoyColors.warning.hexAlpha(0x12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: BuoyColors.warning.hexAlpha(0x25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BuoyGlyph(BuoyIcons.alertTriangle, size: 18, color: BuoyColors.warning),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Search Not Available',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: BuoyColors.warning,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Configure the onSearchUsers callback to enable user search.',
                    style: TextStyle(
                      fontSize: 13,
                      color: BuoyColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: BuoyColors.primary,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Searching users...',
            style: TextStyle(fontSize: 13, color: BuoyColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _error(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BuoyColors.error.hexAlpha(0x12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: BuoyColors.error.hexAlpha(0x25)),
        ),
        child: Row(
          children: [
            const BuoyGlyph(BuoyIcons.alertTriangle, size: 16, color: BuoyColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, color: BuoyColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noResults() {
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
              child: const BuoyGlyph(BuoyIcons.user, size: 28, color: BuoyColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Text(
              'No users found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BuoyColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No results for "$searchQuery"',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: BuoyColors.textSecondary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try a different search term',
              style: TextStyle(fontSize: 12, color: BuoyColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
