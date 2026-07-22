/// Buoy network inspector for Flutter.
///
/// Install [BuoyHttpOverrides] before `runApp` to capture all dart:io HTTP
/// traffic, register [networkSyncAdapter] with a [BuoySyncClient] tool map to
/// stream it to Buoy Desktop, and mount [NetworkModal] via a [BuoyTool] for
/// the in-app panel.
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

export 'src/network_capture.dart';
export 'src/network_tool/network_modal.dart';
export 'src/register.dart';
