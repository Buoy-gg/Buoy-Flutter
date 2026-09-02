/// Ports packages/impersonate/src/preset.tsx (`createImpersonateTool` +
/// `ImpersonateIcon`) — the one-call registration of the impersonate tool +
/// sync adapter with [Buoy].
///
/// Because user search + the data-nuke callbacks are app-supplied, the `buoy`
/// umbrella can only register the TOOL arglessly (for the dial; search then
/// shows a "not configured" warning). The app calls this WITH config to wire
/// everything:
///
/// ```dart
/// registerBuoyImpersonate(
///   onSearchUsers: (query) async => api.searchUsers(query),
///   onClearReactQuery: () => ref.invalidate(...),
///   defaults: const ImpersonateDefaults(headerKey: 'x-admin-impersonate'),
/// );
/// ```
///
/// Both orders compose — the umbrella registers the tool, then the app's call
/// attaches the callbacks. Read the injected header via
/// `BuoyImpersonate.instance.impersonationHeaders`.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart' show installToolBackground;
import 'package:flutter/material.dart';

import 'impersonate_store.dart';
import 'impersonate_sync_adapter.dart';
import 'impersonate_tool/impersonate_modal.dart';
import 'impersonate_types.dart';

bool _registered = false;

/// Live tool config the [ImpersonateModal] reads (search availability, whether
/// the settings tab shows, and which nuke integrations were configured). Set by
/// [registerBuoyImpersonate].
class ImpersonateToolConfig {
  ImpersonateToolConfig._();
  static final ImpersonateToolConfig instance = ImpersonateToolConfig._();

  SearchUsersHandler? onSearchUsers;
  bool showSettingsTab = true;

  /// Whether each data-nuke integration was configured (RN's auto-detection is
  /// RN-runtime specific; here "detected" = a callback was passed).
  bool reactQueryConfigured = false;
  bool reduxConfigured = false;
  bool asyncStorageConfigured = false;
  bool mmkvConfigured = false;

  bool get searchAvailable => onSearchUsers != null;
}

/// Register the impersonate tool. Pass [onSearchUsers] (and optional nuke
/// callbacks / [defaults] / [showSettingsTab]) to fully wire it; call arg-less
/// (e.g. from the umbrella) to just show the tool in the dial. Idempotent —
/// config is re-appliable on later calls.
void registerBuoyImpersonate({
  SearchUsersHandler? onSearchUsers,
  NukeCallback? onClearReactQuery,
  NukeCallback? onClearRedux,
  NukeCallback? onClearAsyncStorage,
  NukeCallback? onClearMMKV,
  ImpersonateDefaults? defaults,
  bool showSettingsTab = true,
}) {
  // Night modals draw the shared ToolBackground; publish it once (idempotent).
  installToolBackground();
  final config = ImpersonateToolConfig.instance;
  if (onSearchUsers != null) config.onSearchUsers = onSearchUsers;
  config.showSettingsTab = showSettingsTab;
  config.reactQueryConfigured = onClearReactQuery != null;
  config.reduxConfigured = onClearRedux != null;
  config.asyncStorageConfigured = onClearAsyncStorage != null;
  config.mmkvConfigured = onClearMMKV != null;

  if (defaults != null) BuoyImpersonate.instance.setDeveloperDefaults(defaults);

  BuoyImpersonate.instance.registerNukeCallbacks(
    reactQuery: onClearReactQuery,
    redux: onClearRedux,
    asyncStorage: onClearAsyncStorage,
    mmkv: onClearMMKV,
  );

  // Make the app's user search available to the zero-config sync adapter.
  registerImpersonateSearchUsers(onSearchUsers);

  // Restore persisted impersonation state up-front (fire and forget; idempotent).
  BuoyImpersonate.instance.initialize();

  if (_registered) return;
  _registered = true;

  Buoy.registerTool(
    BuoyTool(
      // RN preset id 'impersonate'; ImpersonateIcon color #F59E0B (amber). RN
      // icon is a "mask/person" glyph → drama masks (disguise) is the analog.
      id: 'impersonate',
      name: 'IMPERSONATE',
      description: 'User impersonation for admin testing',
      color: const Color(0xFFF59E0B),
      icon: (size, _) => BuoyIcon(impersonateIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => ImpersonateModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: impersonateSyncAdapter,
  );
}
