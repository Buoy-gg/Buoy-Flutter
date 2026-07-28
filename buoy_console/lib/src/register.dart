/// Ports packages/console/src/preset.tsx (consoleToolPreset) — the one-call
/// registration of the console tool + sync adapter with [Buoy].
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';

import 'console_capture.dart';
import 'console_sync_adapter.dart';
import 'console_tool/console_modal.dart';

bool _registered = false;

/// One-call setup for the console tool: installs the console capture hooks
/// (`debugPrint` + `FlutterError` + `PlatformDispatcher`) and registers the
/// tool + its sync adapter with [Buoy]. Idempotent. Called automatically by the
/// `buoy` umbrella widget; apps depending on `buoy_console` directly call it
/// once before `runApp`.
///
/// To also capture `print`, wrap `runApp` in [BuoyConsole.runZoned] — a custom
/// `Zone` is the only way to intercept `print`.
void registerBuoyConsole() {
  if (_registered) return;
  _registered = true;

  // Idempotent; captures debugPrint + errors without requiring a zone.
  BuoyConsole.install();

  Buoy.registerTool(
    BuoyTool(
      // RN toolId 'console'; color = CONSOLE_ICON_COLOR (#10B981, terminal
      // green); icon = the terminal `>_` glyph.
      id: 'console',
      name: 'Console',
      description: 'Captured console.* output',
      color: const Color(0xFF10B981),
      icon: (size, _) => BuoyIcon(consoleIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => ConsoleModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: consoleSyncAdapter,
  );
}
