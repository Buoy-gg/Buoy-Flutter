import 'package:buoy_core/buoy_core.dart' as core;
import 'package:buoy_console/buoy_console.dart';
import 'package:buoy_env/buoy_env.dart';
import 'package:buoy_events/buoy_events.dart';
import 'package:buoy_image_overlay/buoy_image_overlay.dart';
import 'package:buoy_images/buoy_images.dart';
import 'package:buoy_impersonate/buoy_impersonate.dart';
import 'package:buoy_network/buoy_network.dart';
import 'package:buoy_perf_monitor/buoy_perf_monitor.dart';
import 'package:buoy_riverpod/buoy_riverpod.dart';
import 'package:buoy_routes/buoy_routes.dart';
import 'package:buoy_storage/buoy_storage.dart';
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
    this.deviceName,
    this.deviceId,
    this.socketUrl,
    this.licenseKey,
    required this.child,
  });

  final List<core.BuoyTool> tools;
  /// Label in Buoy Desktop / MCP. Default: `Flutter App (<platform> · <last 4 of the id>)`.
  final String? deviceName;
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
    if (kDebugMode) {
      registerBuoyNetwork();
      registerBuoyStorage();
      registerBuoyConsole();
      registerBuoyEnv();
      // Registers the Images tool for the dial. Capture is opt-in per image:
      // the app uses BuoyImage in place of Image/CachedNetworkImage.
      registerBuoyImages();
      // Registers the tool for the dial. The app still attaches
      // BuoyRouteObserver to its router and calls registerBuoyRoutes(router:)
      // so the sitemap + remote navigate light up (the umbrella can't supply
      // the router instance).
      registerBuoyRoutes();
      // Registers the Impersonate tool for the dial. The app still calls
      // registerBuoyImpersonate(onSearchUsers:) to wire user search + the
      // cache-clear callbacks (the umbrella can't supply the app's identities).
      registerBuoyImpersonate();
      // Registers the Image Overlay tool + its full-screen overlay layer. Pure
      // UI (no adapter). Wrap widgets in BuoyImageTarget to use Component Match.
      registerBuoyImageOverlay();
      // Registers the perf-monitor tool for the dial + mounts its draggable
      // live HUD (pure-Dart FrameTiming/RSS sampler). The HUD self-gates on the
      // persisted hud-enabled flag; the sampler is fully off until the HUD is
      // enabled, the modal is open, or a desktop watcher starts sampling.
      registerBuoyPerfMonitor();
      // Registers the Riverpod state-inspector tool for the dial + its events
      // source. The app still adds `buoyRiverpodObserver` to its ProviderScope
      // (the umbrella can't reach the app's ProviderScope) — otherwise the tool
      // shows but captures nothing, like Routes needing the app's router.
      registerBuoyRiverpod();
      // The unified events timeline — registered LAST so every source tool
      // above has already contributed its EventSourceAdapter to the registry.
      registerBuoyEvents();
    }
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
