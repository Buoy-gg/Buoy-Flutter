/// Ports packages/storage/src/storage/components/StorageEventFilterView.tsx.
///
/// The shared Filters overlay: a STORAGE TYPES toggle row (Async/MMKV/Secure)
/// above the [DynamicFilterView] key-pattern filter. RN numerics: storageType
/// section padding 16; buttons flex row gap 8, padV 10; label 11/600.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

class StorageFilterView extends StatelessWidget {
  const StorageFilterView({
    super.key,
    required this.ignoredPatterns,
    required this.onAddPattern,
    required this.onRemovePattern,
    required this.availableKeys,
    required this.enabledStorageTypes,
    required this.onToggleStorageType,
  });

  final Set<String> ignoredPatterns;
  final ValueChanged<String> onAddPattern;
  final ValueChanged<String> onRemovePattern;
  final List<String> availableKeys;
  final Set<String> enabledStorageTypes;
  final ValueChanged<String> onToggleStorageType;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: MacOSColors.borderDefault),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'STORAGE TYPES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MacOSColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _typeButton(
                      'async',
                      'AsyncStorage',
                      BuoyIcons.database,
                      MacOSColors.warning,
                    ),
                    const SizedBox(width: 8),
                    _typeButton(
                      'mmkv',
                      'MMKV',
                      BuoyIcons.box,
                      MacOSColors.info,
                    ),
                    const SizedBox(width: 8),
                    _typeButton(
                      'secure',
                      'Secure Storage',
                      BuoyIcons.shield,
                      MacOSColors.success,
                    ),
                  ],
                ),
              ],
            ),
          ),
          DynamicFilterView(
            addFilterEnabled: true,
            addFilterTitle: 'KEY FILTERS',
            addFilterPlaceholder: 'Enter key pattern to hide...',
            activePatterns: ignoredPatterns.toList(),
            onPatternAdd: onAddPattern,
            onPatternRemove: onRemovePattern,
            availableItemsEnabled: true,
            availableItemsTitle: 'AVAILABLE EVENT KEYS',
            availableItemsEmptyMessage:
                'No storage event keys available. Events will appear here once captured.',
            availableItems: availableKeys,
            howItWorksEnabled: true,
            howItWorksTitle: 'HOW EVENT FILTERS WORK',
            howItWorksDescription:
                'Patterns hide matching storage keys from the event list. Storage type toggles control which storage backends are monitored.',
            howItWorksExamples: const [
              '• react_buoy → hides keys containing react_buoy',
              '• @temp → hides @temp_user, @temp_data',
              '• redux → hides redux-persist:root',
              '• AsyncStorage → show/hide AsyncStorage events',
              '• MMKV → show/hide MMKV events',
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeButton(String type, String label, LucideIcon icon, Color color) {
    final active = enabledStorageTypes.contains(type);
    return Expanded(
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: () => onToggleStorageType(type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? MacOSColors.backgroundCard
                : MacOSColors.backgroundInput,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.hexAlpha(0x40)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BuoyGlyph(icon, size: 16, color: active ? color : MacOSColors.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? color : MacOSColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
