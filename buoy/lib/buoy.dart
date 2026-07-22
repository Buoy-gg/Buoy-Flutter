/// Buoy devtools for Flutter — umbrella package.
///
/// Re-exports the full Buoy tool suite so one dependency wires everything:
/// `buoy_core` (sync client, tool registry, floating shell) and
/// `buoy_network` (network inspector). See https://buoy.gg for docs.
library;

export 'package:buoy_core/buoy_core.dart';
export 'package:buoy_network/buoy_network.dart';
