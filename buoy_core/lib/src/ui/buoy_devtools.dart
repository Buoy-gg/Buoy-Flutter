import 'package:flutter/foundation.dart';
import '../icons/buoy_icon_painter.dart';
import '../icons/buoy_icons.dart';
import 'package:flutter/material.dart';

import '../buoy.dart';
import '../storage.dart';
import '../tool.dart';
import 'buoy_theme.dart';
import 'dial/dial_overlay.dart';
import 'floating_bubble.dart';
import 'modal/modal_settings.dart';
import 'modal/modal_visibility.dart';
import 'overlay_host.dart';
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

  /// Open tools in z-order (RN AppHost `openApps`): later = on top. Minimized
  /// tools STAY in the list and stay mounted (hidden via [BuoyModalVisibility])
  /// so their UI state survives — the single source of truth for both the
  /// modal stack and the minimized dock. Singleton per tool id.
  final List<_OpenApp> _openApps = [];
  int _nextDockSeq = 0;
  VoidCallback? _removeRegistryListener;

  /// Hosts every Buoy layer inside our own [Overlay] (see [build]). Created once
  /// — [OverlayState] consumes `initialEntries` on mount and ignores later ones.
  OverlayEntry? _buoyEntry;

  /// The entry sits inside the Overlay, so an ancestor rebuild does NOT rebuild
  /// it. Marking it dirty on every [setState] keeps the layers as reactive as
  /// they were when they were plain Stack children.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _buoyEntry?.markNeedsBuild();
  }

  /// Registered + prop tools, prop tools last (explicit wins on duplicate id).
  List<BuoyTool> get _allTools {
    final seen = <String>{};
    return [
      for (final tool in [...Buoy.tools, ...widget.tools])
        if (seen.add(tool.id)) tool,
    ];
  }

  /// Any tool visible on screen (RN `isAnyOpen` — minimized tools excluded).
  bool get _anyVisibleOpen => _openApps.any((a) => !a.minimized);

  /// Dock icons for minimized tools, in minimize order (RN appends to its
  /// tray). Derived from [_openApps] — no second store like RN's
  /// MinimizedToolsContext, whose id/instanceId reconciliation is a known
  /// source of orphan-icon bugs.
  List<BuoyTool> get _minimizedTools {
    final docked = _openApps.where((a) => a.minimized).toList()
      ..sort((a, b) => (a.dockSeq ?? 0).compareTo(b.dockSeq ?? 0));
    return [for (final a in docked) a.tool];
  }

  _OpenApp? _openAppById(String id) {
    for (final app in _openApps) {
      if (app.tool.id == id) return app;
    }
    return null;
  }

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
  /// Saved array order is stack order, so appending in sequence restores the
  /// z-order. Per-tool size/mode/position rides on each JsModal's own
  /// persistence, so re-mounting the modal restores its geometry.
  Future<void> _restoreOpenApps() async {
    final saved = await _storage.loadOpenApps();
    if (!mounted) return;
    setState(() {
      for (final entry in saved) {
        final tool = _toolById(entry.id);
        // Only modal/screen tools have a surface to reopen or minimize; skip
        // anything the user already opened during the async load (RN gets
        // this for free via singleton open()).
        if (tool == null ||
            (tool.modalBuilder == null && tool.screenBuilder == null) ||
            _openAppById(tool.id) != null) {
          continue;
        }
        _openApps.add(
          _OpenApp(
            tool,
            minimized: entry.minimized,
            dockSeq: entry.minimized ? _nextDockSeq++ : null,
          ),
        );
      }
      _appsRestored = true;
    });
  }

  BuoyTool? _toolById(String id) {
    for (final tool in _allTools) {
      if (tool.id == id) return tool;
    }
    return null;
  }

  /// Persist which tools are open / minimized (RN `@react_buoy_open_apps`).
  /// True stack order — RN persists the array as-is so z-order survives a
  /// restart.
  void _persistOpenApps() {
    if (!_appsRestored) return;
    _storage.saveOpenApps([
      for (final app in _openApps) (id: app.tool.id, minimized: app.minimized),
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

  /// Launch = RN `resolveOpenAppsState` with singleton semantics: relaunching
  /// an already-open tool moves its existing record to the end of the list
  /// (bring-to-front) and un-minimizes it — same record, same key, so the
  /// mounted subtree is reused, not remounted. Otherwise append on top.
  void _launchTool(BuoyTool tool) {
    final onPressed = tool.onPressed;
    if (onPressed != null) {
      onPressed(context);
      return;
    }
    if (tool.modalBuilder == null && tool.screenBuilder == null) return;
    setState(() {
      final existing = _openAppById(tool.id);
      if (existing != null) {
        _openApps.remove(existing);
        existing
          ..minimized = false
          ..dockSeq = null;
        _openApps.add(existing);
      } else {
        _openApps.add(_OpenApp(tool));
      }
    });
    _persistOpenApps();
  }

  void _closeTool(String id) {
    setState(() => _openApps.removeWhere((a) => a.tool.id == id));
    _persistOpenApps();
  }

  /// Minimize: hide the modal, dock a restorable icon. The record stays in
  /// [_openApps] and the tool stays MOUNTED (RN parity — RN keeps minimized
  /// apps rendering offscreen so their state and subscriptions survive). Its
  /// JsModal has already flushed geometry to persistence.
  void _minimizeTool(String id) {
    final app = _openAppById(id);
    if (app == null || app.minimized) return;
    setState(() {
      app
        ..minimized = true
        ..dockSeq = _nextDockSeq++;
    });
    _persistOpenApps();
  }

  /// Restore from the dock: un-hide in place. Deliberately NO reorder — RN's
  /// `restore()` brings a tool back at its original z-slot; only relaunching
  /// via dial/menu brings to front.
  void _restoreTool(BuoyTool tool) {
    final app = _openAppById(tool.id);
    if (app == null) return;
    setState(() {
      app
        ..minimized = false
        ..dockSeq = null;
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
    // The Buoy layers mount at `MaterialApp.builder`, i.e. ABOVE the app's
    // Navigator — so they inherit no Overlay. Any TextField in a tool modal
    // (search fields, filter inputs) then throws "No Overlay widget found" as
    // soon as it needs its selection handles / cursor / context menu. Hosting
    // the layers in their own Overlay gives those fields the ancestor they
    // need, without a nested Navigator stealing route/back-button semantics.
    _buoyEntry ??= OverlayEntry(builder: _buoyLayers);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Overlay(initialEntries: [_buoyEntry!]),
      ],
    );
  }

  /// Every interactive Buoy layer, rendered inside [_buoyEntry]. `initialEntries`
  /// is read once by [OverlayState], so this never re-runs from an ancestor
  /// rebuild — [setState] marks the entry dirty instead (see the override above).
  Widget _buoyLayers(BuildContext context) {
    // Every Stack child carries a stable key: open-tool reorders
    // (bring-to-front) and list-length changes (dial dismissing while a tool
    // launches) can land in the same frame, and an unkeyed FloatingBubble
    // caught in the diff's keyed middle range would be remounted — losing its
    // drag position.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Tool-owned full-screen overlays (e.g. image-overlay's mockup image)
        // render OUTSIDE any modal, above the app but below the interactive
        // Buoy UI. Renders nothing until a tool registers a builder.
        const _OverlayHostLayer(key: ValueKey('buoy-overlay-host')),
        // Open tools in list order = z-order (RN AppOverlay maps openApps to
        // BASE_ZINDEX + index). JsModal-style tools render their own modal
        // surface and stay mounted while minimized (hidden via
        // BuoyModalVisibility — RN's visible={!app.minimized}); screen-style
        // tools fall back to the full-screen host, which unmounts when
        // minimized (RN inline launch mode returns null when hidden).
        for (final app in _openApps)
          if (app.tool.modalBuilder != null)
            BuoyModalVisibility(
              key: ValueKey('buoy-app-${app.tool.id}'),
              visible: !app.minimized,
              child: app.tool.modalBuilder!(
                context,
                _storage,
                () => _closeTool(app.tool.id),
                () => _minimizeTool(app.tool.id),
              ),
            )
          else if (!app.minimized)
            KeyedSubtree(
              key: ValueKey('buoy-app-${app.tool.id}'),
              child: _ToolHost(
                tool: app.tool,
                onClose: () => _closeTool(app.tool.id),
              ),
            ),
        FloatingBubble(
          key: const ValueKey('buoy-bubble'),
          storage: _storage,
          pushToSide: _dialVisible || _anyVisibleOpen,
          onOpenDial: _openDial,
          minimizedTools: _minimizedTools,
          onRestoreMinimized: _restoreTool,
        ),
        if (_dialVisible)
          DialOverlay(
            key: const ValueKey('buoy-dial'),
            tools: _allTools,
            storage: _storage,
            onLaunch: _launchTool,
            onDismissed: _dialDismissed,
          ),
      ],
    );
  }
}

/// One entry in the open-tools stack (RN `AppInstance`, minus the unused
/// multi-instance machinery — launches are singleton-by-tool-id, so the tool
/// id doubles as the instance identity and widget key).
class _OpenApp {
  _OpenApp(this.tool, {this.minimized = false, this.dockSeq});

  final BuoyTool tool;
  bool minimized;

  /// Order the tool was minimized in — drives dock icon order (RN appends to
  /// its minimized tray). Null while visible.
  int? dockSeq;
}

/// Renders every builder registered with [BuoyOverlayHost] as a stacked
/// full-screen layer. Transparent regions pass touches through to the app
/// child below (no opaque background) — the Flutter analog of RN's
/// `pointerEvents="box-none"` standalone-overlay slot.
class _OverlayHostLayer extends StatelessWidget {
  const _OverlayHostLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<WidgetBuilder>>(
      valueListenable: BuoyOverlayHost.instance.listenable,
      builder: (context, builders, _) {
        if (builders.isEmpty) return const SizedBox.shrink();
        return Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [for (final build in builders) build(context)],
          ),
        );
      },
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
                    tool.icon(18, tool.color),
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
                        child: BuoyGlyph(
                          BuoyIcons.x,
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
