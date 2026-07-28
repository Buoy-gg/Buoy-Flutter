/// Buoy user-impersonation tool for Flutter.
///
/// Test your app as any user/role without logging out. Search identities,
/// activate an override, and read the injected impersonation header
/// (`BuoyImpersonate.instance.impersonationHeaders`) from your HTTP client —
/// mirrored live to Buoy Desktop. A 1:1 port of `@buoy-gg/impersonate`.
///
/// Because user search + data-nuke callbacks are app-supplied, register WITH
/// config: `registerBuoyImpersonate(onSearchUsers: (q) async => ...)`. The
/// `buoy` umbrella registers the tool for the dial; your call attaches search.
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

export 'src/register.dart' show registerBuoyImpersonate, ImpersonateToolConfig;
export 'src/impersonate_store.dart'
    show
        BuoyImpersonate,
        NukeCallback,
        impersonateStorageKey,
        isImpersonating,
        getImpersonatedUserId;
export 'src/impersonate_types.dart'
    show
        ImpersonateUser,
        HistoryEntry,
        DataNukeSettings,
        ImpersonationState,
        ImpersonateDefaults;
export 'src/impersonate_sync_adapter.dart'
    show impersonateSyncAdapter, SearchUsersHandler, registerImpersonateSearchUsers;
export 'src/impersonate_tool/impersonate_modal.dart' show ImpersonateModal;
