/// Buoy environment-variable debugger for Flutter.
///
/// Inspect and validate your app's env vars on-device — required-variable
/// checks, type detection, per-variable status badges, and a 0–100% health
/// score — mirrored live to Buoy Desktop. A 1:1 port of `@buoy-gg/env`.
///
/// Flutter has no enumerable `process.env`, so register your env map explicitly:
/// call [registerBuoyEnv] with `vars` (and optional `requiredEnvVars`), or wire
/// it through the `buoy` umbrella and configure via [BuoyEnv]. Optional
/// `flutter_dotenv` integration needs no dependency: `registerBuoyEnv(vars:
/// dotenv.env)`.
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

export 'src/register.dart';
export 'src/env_store.dart' show BuoyEnv;
export 'src/env_sync_adapter.dart' show envSyncAdapter;
export 'src/env_types.dart'
    show
        EnvVarType,
        RequiredEnvVar,
        EnvVarInfo,
        EnvVarStatus,
        EnvVarStats,
        EnvVarBuilder,
        envVar,
        createEnvVarConfig;
export 'src/env_validation.dart'
    show
        getEnvVarType,
        processEnvVars,
        calculateStats,
        healthPercentage,
        healthStatusLabel,
        ProcessedEnvVars;
export 'src/env_tool/env_modal.dart' show EnvVarsModal;
