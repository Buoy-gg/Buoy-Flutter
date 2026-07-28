/// Ports packages/storage/src/storage/utils/storageActionHelpers.ts and the
/// action-color maps in StorageEventCard.tsx / StorageEventDetailContent.tsx.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/widgets.dart';

/// RN `translateStorageAction`: action string → human label (SET/REMOVE/…).
String translateStorageAction(String action) => switch (action) {
  'setItem' => 'SET',
  'removeItem' => 'REMOVE',
  'mergeItem' => 'MERGE',
  'clear' => 'CLEAR',
  'multiSet' => 'MULTI SET',
  'multiRemove' => 'MULTI REMOVE',
  'multiMerge' => 'MULTI MERGE',
  'set.string' || 'set.number' || 'set.boolean' || 'set.buffer' => 'SET',
  'delete' => 'REMOVE',
  'clearAll' => 'CLEAR',
  'get.string' || 'get.number' || 'get.boolean' || 'get.buffer' => 'GET',
  _ => 'UNKNOWN ACTION',
};

/// RN `getActionColor` (StorageEventCard): set=success, remove/clear=error,
/// merge=info, get=warning, else muted.
Color getActionColor(String action) => switch (action) {
  'setItem' ||
  'multiSet' ||
  'set.string' ||
  'set.number' ||
  'set.boolean' ||
  'set.buffer' =>
    MacOSColors.success,
  'removeItem' || 'multiRemove' || 'clear' || 'delete' || 'clearAll' =>
    MacOSColors.error,
  'mergeItem' || 'multiMerge' => MacOSColors.info,
  'get.string' || 'get.number' || 'get.boolean' || 'get.buffer' =>
    MacOSColors.warning,
  _ => MacOSColors.textMuted,
};
