import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../buoy.dart';
import '../storage.dart';
import '../tool.dart';
import 'buoy_theme.dart';
import 'dial/dial_overlay.dart';
import 'floating_bubble.dart';
import 'modal/modal_settings.dart';
import 'touchable_opacity.dart';

/// Root of the in-app floating menu — the Flutter analog of the RN package's
/// `FloatingDevTools`. Mount it once via `MaterialApp.router(builder:)` so it
/// wraps the Navigator and survives all route changes:
///
/// ```dart
/// MaterialApp.router(
///   builder: (context, child) =>
///       BuoyDevTools(tools: buoyTools, child: child!),
///   ...
/// )
/// ```
///
/// Renders nothing in release builds. The app child sits first in the Stack
/// and is never rebuilt by menu state — bubble drag, dial, and tool layers
/// composite on top.
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

  /// Extra tools beyond those self-registered via [Buoy.registerTool].
  final List<BuoyTool> tools;

  /// Desktop-sync identity — mirrors the RN `externalSync` prop. The widget
  /// auto-starts the sync connection on mount (idempotent; an explicit
  /// earlier [Buoy.init] wins).
  final String deviceName;
  final String? deviceId;
  final String? socketUrl;
  final String? licenseKey;
  final Widget child;

  @override
  State<BuoyDevTools> createState() => _BuoyDevToolsState();
}

class _BuoyDevToolsState extends State<BuoyDevTools> {
  final _storage = BuoyStorage();
  bool _dialVisible = false;
  BuoyTool? _openTool;
  VoidCallback? _removeRegistryListener;

  /// Registered + prop tools, prop tools last (explicit wins on duplicate id).
  List<BuoyTool> get _allTools {
    final seen = <String>{};
    return [
      for (final tool in [...Buoy.tools, ...widget.tools])
        if (seen.add(tool.id)) tool,
    ];
  }

  /// Tools minimized out of their modal, docked as restorable icons. Singleton
  /// per tool id (RN MinimizedToolsContext.minimize dedupes by id).
  final List<BuoyTool> _minimized = [];

  /// Guards open-apps persistence until the boot-time restore has run, so an
  /// early write can't clobber the saved state with an empty list.
  bool _appsRestored = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      Buoy.init(
        deviceName: widget.deviceName,
        deviceId: widget.deviceId,
        socketUrl: widget.socketUrl,
        licenseKey: widget.licenseKey,
      );
      _removeRegistryListener =
          Buoy.addRegistryListener(() => setState(() {}));
      _restoreDialState();
      _restoreOpenApps();
      // Apply persisted global modal settings (expandable controls, shared
      // dimensions) before any modal opens.
      _storage.loadDevToolsSettings().then(applyGlobalModalSettings);
    }
  }

  /// Re-open the tools that were open at last close (RN AppHost restore).
  /// Per-tool size/mode/position rides on each JsModal's own persistence, so
  /// re-mounting the modal restores its geometry.
  Future<void> _restoreOpenApps() async {
    final saved = await _storage.loadOpenApps();
    if (!mounted) return;
    BuoyTool? openTool;
    final minimized = <BuoyTool>[];
    for (final entry in saved) {
      final tool = _toolById(entry.id);
      // Only modal/screen tools have a surface to reopen or minimize.
      if (tool == null ||
          (tool.modalBuilder == null && tool.screenBuilder == null)) {
        continue;
      }
      if (entry.minimized) {
        minimized
          ..removeWhere((t) => t.id == tool.id)
          ..add(tool);
      } else {
        openTool = tool; // one open tool at a time — last wins
      }
    }
    setState(() {
      _appsRestored = true;
      // Don't clobber anything the user already opened during the async load.
      if (_openTool == null && _minimized.isEmpty) {
        _minimized.addAll(minimized);
        _openTool = openTool;
      }
    });
  }

  BuoyTool? _toolById(String id) {
    for (final tool in _allTools) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  /// Persist which tools are open / minimized (RN `@react_buoy_open_apps`).
  void _persistOpenApps() {
    if (!_appsRestored) return;
    _storage.saveOpenApps([
      for (final tool in _minimized) (id: tool.id, minimized: true),
      if (_openTool != null) (id: _openTool!.id, minimized: false),
    ]);
  }

  Future<void> _restoreDialState() async {
    final wasOpen = await _storage.loadDialOpen();
    if (mounted && wasOpen) setState(() => _dialVisible = true);
  }

  void _openDial() {
    setState(() => _dialVisible = true);
    _storage.saveDialOpen(true);
  }

  void _dialDismissed() {
    setState(() => _dialVisible = false);
    _storage.saveDialOpen(false);
  }

  void _launchTool(BuoyTool tool) {
    final onPressed = tool.onPressed;
    if (onPressed != null) {
      onPressed(context);
      return;
    }
    if (tool.modalBuilder != null || tool.screenBuilder != null) {
      setState(() {
        _minimized.removeWhere((t) => t.id == tool.id);
        _openTool = tool;
      });
      _persistOpenApps();
    }
  }

  void _closeTool() {
    setState(() => _openTool = null);
    _persistOpenApps();
  }

  /// Minimize the open modal-tool: hide it, dock a restorable icon. Its JsModal
  /// has already flushed geometry to persistence, so reopening restores it.
  void _minimizeTool() {
    final tool = _openTool;
    if (tool == null) return;
    setState(() {
      _openTool = null;
      _minimized.removeWhere((t) => t.id == tool.id);
      _minimized.add(tool);
    });
    _persistOpenApps();
  }

  void _restoreTool(BuoyTool tool) {
    setState(() {
      _minimized.removeWhere((t) => t.id == tool.id);
      _openTool = tool;
    });
    _persistOpenApps();
  }

  @override
  void dispose() {
    _removeRegistryListener?.call();
    _storage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;
    final openTool = _openTool;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // JsModal-style tools render their own modal surface; screen-style
        // tools fall back to the full-screen host.
        if (openTool != null && openTool.modalBuilder != null)
          openTool.modalBuilder!(
            context,
            _storage,
            _closeTool,
            _minimizeTool,
          )
        else if (openTool != null)
          _ToolHost(tool: openTool, onClose: _closeTool),
        FloatingBubble(
          storage: _storage,
          pushToSide: _dialVisible || openTool != null,
          onOpenDial: _openDial,
          minimizedTools: _minimized,
          onRestoreMinimized: _restoreTool,
        ),
        if (_dialVisible)
          DialOverlay(
            tools: _allTools,
            storage: _storage,
            onLaunch: _launchTool,
            onDismissed: _dialDismissed,
          ),
      ],
    );
  }
}

/// Full-screen host for a modal-style tool (the v1 stand-in for the RN
/// AppHost; minimize/restore comes later).
class _ToolHost extends StatelessWidget {
  const _ToolHost({required this.tool, required this.onClose});

  final BuoyTool tool;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF101010),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(tool.icon, size: 18, color: tool.color),
                    const SizedBox(width: 8),
                    Text(
                      tool.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                        color: BuoyTheme.secondary,
                      ),
                    ),
                    const Spacer(),
                    TouchableOpacity(
                      activeOpacity: 0.7,
                      onTap: onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: BuoyTheme.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: BuoyTheme.muted.withValues(alpha: 0.2)),
              Expanded(child: tool.screenBuilder!(context)),
            ],
          ),
        ),
      ),
    );
  }
}
