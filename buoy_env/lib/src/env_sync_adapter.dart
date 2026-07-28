/// Ports packages/env-tools/src/sync/envSyncAdapter.ts.
///
/// Streams the device's env values + required-var config to Buoy Desktop, which
/// renders the same [EnvVarsModal] via `setRemoteEnv`. Field-for-field mirror of
/// the RN adapter: `version 1`, snapshot `{env, requiredEnvVars}`, and NO
/// actions. RN's `subscribe` is a literal no-op (env is baked into the bundle,
/// so one snapshot is sent when watching starts); here it registers on
/// [BuoyEnv] so a reconfigured env re-pushes — a benign superset (still one
/// snapshot in practice).
library;

import 'package:buoy_core/buoy_core.dart';

import 'env_store.dart';

/// The env tool's sync adapter — mirrors envSyncAdapter.ts.
final envSyncAdapter = ToolSyncAdapter(
  version: 1,
  getSnapshot: () => {
    'env': BuoyEnv.instance.vars,
    'requiredEnvVars': [
      for (final r in BuoyEnv.instance.requiredEnvVars) r.toJson(),
    ],
  },
  subscribe: (onChange) => BuoyEnv.instance.subscribe(onChange),
  // Env has no runtime actions (RN parity).
);
