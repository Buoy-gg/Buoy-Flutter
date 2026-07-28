/// Buoy shared UI for Flutter.
///
/// The Dart mirror of `@buoy-gg/shared-ui`: the macOS/Buoy color systems, the
/// list/badge/filter widgets every tool renders, the [BaseEventStore] event-store
/// base, the centralized dev-tool storage keys, and the Buoy icon set. Depended
/// on by every Buoy tool package (dependency direction: buoy_core ← buoy_shared_ui
/// ← tools).
library;

// Colors
export 'src/macos_colors.dart';
export 'src/game_ui_colors.dart';

// Formatting + time
export 'src/formatting.dart';
export 'src/minute_ticker.dart';
export 'src/time/relative_time.dart';

// Filters
export 'src/ignored_patterns.dart';

// Stores
export 'src/stores/base_event_store.dart';
export 'src/stores/event_source_registry.dart';

// Storage keys
export 'src/storage/dev_tools_storage_keys.dart';

// Icons — the Buoy Icon Format now lives in buoy_core (core's dial renders
// tool icons, and nothing below core may depend on this package). Re-exported
// here so every existing `package:buoy_shared_ui` importer keeps working.
export 'package:buoy_core/buoy_core.dart'
    show
        BuoyIcon,
        BuoyGlyph,
        BuoyIconPainter,
        BuoyIconData,
        BuoyIcons,
        LucideIcon,
        BifElement,
        BifCircle,
        BifRect,
        BifLine,
        BifTriangle,
        BifArc,
        BifSemicircle,
        BifSmoothArc,
        BifPaint,
        BifPaintSource,
        BifDirection,
        BifHalf,
        BifPortion,
        buoyIconsByName,
        buoyGlyphsByName;

// Widgets (moved from buoy_network)
export 'src/widgets/badges.dart';
export 'src/widgets/copy_button.dart';
export 'src/widgets/data_viewer.dart';
export 'src/widgets/devtools_card.dart';
export 'src/widgets/dynamic_filter_view.dart';
export 'src/widgets/filter_components.dart';
export 'src/widgets/modal_header.dart';
export 'src/widgets/power_toggle_button.dart';
export 'src/widgets/section_header.dart';
export 'src/widgets/tab_selector.dart';

// Diff stack (dataViewer/tree + EventHistoryViewer diff parts) — used by the
// state-inspector tools (buoy_riverpod) and buoy_storage's event detail.
export 'src/data_viewer/line_diff.dart';
export 'src/data_viewer/diff_themes.dart';
export 'src/data_viewer/diff_summary.dart';
export 'src/data_viewer/split_diff_viewer.dart';
export 'src/data_viewer/tree_diff_viewer.dart';
export 'src/widgets/compare_bar.dart';
export 'src/widgets/diff_mode_tabs.dart';
export 'src/widgets/event_stepper_footer.dart';
export 'src/widgets/view_toggle_cards.dart';

// Widgets (new shared ports)
export 'src/widgets/collapsible_section.dart';
export 'src/widgets/compact_filter_chips.dart';
export 'src/widgets/compact_row.dart';
export 'src/widgets/empty_state.dart';
export 'src/widgets/expanded_info_row.dart';
export 'src/widgets/search_bar.dart';
export 'src/widgets/stats_card.dart';
export 'src/widgets/status_badge.dart';
