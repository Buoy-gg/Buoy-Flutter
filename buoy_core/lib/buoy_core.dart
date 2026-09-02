/// Buoy devtools core for Flutter.
///
/// Provides the desktop-sync client ([BuoySyncClient] + [ToolSyncAdapter]),
/// the tool registry contract ([BuoyTool]), the floating bubble + dial shell
/// ([BuoyDevTools]), and shared UI/persistence used by tool packages.
library;

export 'src/buoy.dart';
export 'src/license/keygen.dart';
export 'src/license/license_manager.dart';
export 'src/storage.dart';
export 'src/sync/crash_flush.dart';
export 'src/sync/wire_budget.dart';
export 'src/device_identity.dart';
export 'src/sync_client.dart';
export 'src/tool.dart';
export 'src/ui/buoy_devtools.dart';
export 'src/ui/buoy_theme.dart';
export 'src/ui/modal/js_modal.dart';
export 'src/ui/modal/modal_settings.dart';
export 'src/ui/modal/modal_visibility.dart';
export 'src/ui/night/night_primitives.dart';
export 'src/ui/night/night_theme.dart';
export 'src/ui/overlay_host.dart';
export 'src/ui/settings/settings_sheet.dart' show backgroundSwitcherBuilder;
export 'src/ui/touchable_opacity.dart';

// Buoy Icon Format — the cross-framework artwork shared with React Native and
// the desktop dashboard, authored in shared/icons/*.json. It lives in core
// (not shared_ui) because core's dial renders tool icons and nothing below it
// may depend on shared_ui.
export 'src/icons/buoy_icon_data.dart';
export 'src/icons/buoy_icon_painter.dart';
export 'src/icons/buoy_icons.dart';
export 'src/icons/generated/buoy_icon_data.g.dart';
