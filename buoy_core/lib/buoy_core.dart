/// Buoy devtools core for Flutter.
///
/// Provides the desktop-sync client ([BuoySyncClient] + [ToolSyncAdapter]),
/// the tool registry contract ([BuoyTool]), the floating bubble + dial shell
/// ([BuoyDevTools]), and shared UI/persistence used by tool packages.
library;

export 'src/storage.dart';
export 'src/sync_client.dart';
export 'src/tool.dart';
export 'src/ui/buoy_devtools.dart';
export 'src/ui/buoy_theme.dart';
export 'src/ui/modal/js_modal.dart';
export 'src/ui/modal/modal_settings.dart';
export 'src/ui/touchable_opacity.dart';
