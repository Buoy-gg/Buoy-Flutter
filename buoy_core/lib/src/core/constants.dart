/// Shared constants for the floating menu, ported from
/// @buoy-gg/floating-tools-core `constants.ts` and the native
/// `floatingTools.tsx`. Values (and storage key names) are kept identical to
/// the React Native implementation so behavior and persisted state stay
/// consistent across frameworks.
library;

/// Width of the visible grip handle when the bubble is hidden (logical px).
const double visibleHandleWidth = 32;

/// Minimum total travel (|dx| + |dy|) to treat a gesture as a drag, not a tap.
const double dragThreshold = 5;

/// Duration of hide/show and settle animations.
const Duration hideShowDuration = Duration(milliseconds: 200);

/// Padding from screen edges (native floatingTools.tsx uses 20, not the web
/// store's 10).
const double edgePadding = 20;

/// Debounce for persisting the bubble position while it moves.
const Duration saveDebounce = Duration(milliseconds: 500);

/// When a restored X is within this many px of the hidden slot, the bubble is
/// considered to have been hidden when the app last closed.
const double hiddenRestoreTolerance = 5;

/// Storage keys — identical to the RN package's `@react_buoy` namespace.
class BuoyStorageKeys {
  static const prefix = '@react_buoy';
  static const bubblePositionX = '@react_buoy_bubble_position_x';
  static const bubblePositionY = '@react_buoy_bubble_position_y';
  static const dialIsOpen = '@react_buoy_dial_is_open';
  static const dialUsage = '@react_buoy_dial_usage';
  static const settingsModalOpen = '@react_buoy_settings_modal_open';
  static const settingsActiveTab = '@react_buoy_settings_active_tab';
  static const devToolsSettings = '@react_buoy_dev_tools_settings';
  static const minimizedStackExpanded = '@react_buoy_minimized_stack_expanded';

  /// Which tools were open (and whether minimized) at last close — RN AppHost's
  /// `@react_buoy_open_apps`. Per-tool modal geometry lives under each tool's
  /// own JsModal persistenceKey, not here.
  static const openApps = '@react_buoy_open_apps';
}
