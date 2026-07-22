/// Buoy devtools for Flutter — umbrella package.
///
/// One widget wires everything: wrap your app with [BuoyDevTools] (via
/// `MaterialApp.builder`) and every installed Buoy tool auto-registers —
/// HTTP capture, the in-app floating menu, live desktop sync, and the MCP
/// server connection. See https://buoy.gg for docs.
library;

export 'package:buoy_core/buoy_core.dart' hide BuoyDevTools;
export 'package:buoy_network/buoy_network.dart' hide BuoyDevTools;

export 'src/buoy_devtools.dart';
