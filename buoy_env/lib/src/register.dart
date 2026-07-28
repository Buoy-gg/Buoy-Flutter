/// Ports packages/env-tools/src/preset.tsx (envToolPreset / createEnvTool) —
/// the one-call registration of the env tool + sync adapter with [Buoy].
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';

import 'env_store.dart';
import 'env_sync_adapter.dart';
import 'env_tool/env_modal.dart';
import 'env_types.dart';

bool _registered = false;

/// One-call setup for the env tool: registers the tool + its sync adapter with
/// [Buoy] (idempotent), and — since Flutter has no enumerable `process.env` —
/// optionally seeds the env source with the app's [vars] and [requiredEnvVars].
///
/// The `buoy` umbrella calls this arg-less; apps depending on `buoy_env`
/// directly call it once before `runApp`, typically WITH `vars`:
///
/// ```dart
/// registerBuoyEnv(
///   vars: {'API_URL': const String.fromEnvironment('API_URL')},
///   requiredEnvVars: [envVar('API_URL').withType('url').build()],
/// );
/// ```
///
/// `vars:` accepts any map, so `flutter_dotenv` integrates with no dependency:
/// `registerBuoyEnv(vars: dotenv.env)`. Calling again merges more vars / updates
/// the required config without re-registering the tool.
void registerBuoyEnv({
  Map<String, String>? vars,
  List<RequiredEnvVar>? requiredEnvVars,
}) {
  if (vars != null || requiredEnvVars != null) {
    BuoyEnv.instance.configure(vars: vars, requiredEnvVars: requiredEnvVars);
  }

  if (_registered) return;
  _registered = true;

  Buoy.registerTool(
    BuoyTool(
      // RN toolId 'env'; color = ENV_ICON_COLOR (#4AFF9F, bright green); RN icon
      // is a laptop/keyboard glyph → the closest Material analog.
      id: 'env',
      name: 'ENV',
      description: 'Environment variables debugger',
      color: const Color(0xFF4AFF9F),
      icon: (size, _) => BuoyIcon(envIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => EnvVarsModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: envSyncAdapter,
  );
}
