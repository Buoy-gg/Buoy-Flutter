import 'package:buoy_core/buoy_core.dart' as core;
import 'package:buoy_network/buoy_network.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Zero-config Buoy devtools — the Flutter analog of RN's
/// `<FloatingDevTools />`. Wrap your app once and every installed Buoy tool
/// is wired automatically: HTTP capture, the floating bubble + dial, desktop
/// sync, and the MCP server connection.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) =>
///       BuoyDevTools(child: child ?? const SizedBox.shrink()),
/// )
/// ```
///
/// All props are optional: pass `deviceName`/`deviceId` to label the device in
/// Buoy Desktop, `licenseKey` for Pro, `socketUrl` for physical devices, and
/// `tools` for your own custom [core.BuoyTool]s.
class BuoyDevTools extends StatefulWidget {
  const BuoyDevTools({
    super.key,
    this.tools = const [],
    this.deviceName = 'Flutter App',
    this.deviceId,
    this.socketUrl,
    this.licenseKey,
    required this.child,
  });

  final List<core.BuoyTool> tools;
  final String deviceName;
  final String? deviceId;
  final String? socketUrl;
  final String? licenseKey;
  final Widget child;

  @override
  State<BuoyDevTools> createState() => _BuoyDevToolsState();
}

class _BuoyDevToolsState extends State<BuoyDevTools> {
  @override
  void initState() {
    super.initState();
    // Self-register every tool this umbrella ships — the Dart stand-in for
    // the RN package's optional-require auto-discovery.
    if (kDebugMode) registerBuoyNetwork();
  }

  @override
  Widget build(BuildContext context) {
    return core.BuoyDevTools(
      tools: widget.tools,
      deviceName: widget.deviceName,
      deviceId: widget.deviceId,
      socketUrl: widget.socketUrl,
      licenseKey: widget.licenseKey,
      child: widget.child,
    );
  }
}
