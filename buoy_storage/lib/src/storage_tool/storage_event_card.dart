/// Ports packages/storage/src/storage/components/StorageEventCard.tsx.
///
/// Storage event row on [CompactRow]: status "Storage" + action-colored dot,
/// `Async/MMKV · N ops` sublabel, the key as primary text, an action badge
/// (SET/REMOVE/…), and a live [RelativeTime] bottom-right.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'storage_action_helpers.dart';

class StorageEventCard extends StatelessWidget {
  const StorageEventCard({
    super.key,
    required this.storageKey,
    required this.lastAction,
    required this.lastEventTimestamp,
    required this.storageTypes,
    this.totalOperations = 1,
    required this.onPress,
  });

  final String storageKey;
  final String lastAction;
  final DateTime lastEventTimestamp;
  final Set<String> storageTypes;
  final int totalOperations;
  final VoidCallback onPress;

  String get _sublabel {
    final types = storageTypes
        .map((t) => t == 'async' ? 'Async' : (t == 'mmkv' ? 'MMKV' : 'Secure'))
        .join('/');
    return '$types · $totalOperations op${totalOperations != 1 ? 's' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final actionColor = getActionColor(lastAction);
    return CompactRow(
      statusDotColor: actionColor,
      statusLabel: 'Storage',
      statusSublabel: _sublabel,
      primaryText: storageKey,
      badgeText: translateStorageAction(lastAction),
      badgeColor: actionColor,
      showChevron: true,
      bottomRightText: RelativeTime(timestamp: lastEventTimestamp),
      onPress: onPress,
    );
  }
}
