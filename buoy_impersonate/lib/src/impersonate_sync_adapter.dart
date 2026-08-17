/// Ports packages/impersonate/src/sync/impersonateSyncAdapter.ts.
///
/// Field-for-field mirror of the RN adapter: `version 1`, snapshot =
/// `impersonateStore.getState()` serialized, subscribe on the store, and the
/// same eight actions (searchUsers / start / stop / pause / resume /
/// updateSettings / removeFromHistory / clearHistory). The dashboard mirrors the
/// state and forwards every mutation back as an action, so impersonating from
/// Buoy Desktop behaves exactly like tapping the modal on-device.
library;

import 'package:buoy_core/buoy_core.dart';

import 'impersonate_store.dart';
import 'impersonate_types.dart';

/// The app's user-search callback. RN: `SearchUsersHandler`.
typedef SearchUsersHandler = Future<List<ImpersonateUser>> Function(String query);

// Registered by registerBuoyImpersonate so the zero-config adapter can proxy
// the dashboard's user search. RN: `registeredSearchUsers`.
SearchUsersHandler? _registeredSearchUsers;

/// @internal Called by registerBuoyImpersonate with the app's onSearchUsers.
/// RN: `registerImpersonateSearchUsers`.
void registerImpersonateSearchUsers(SearchUsersHandler? handler) {
  _registeredSearchUsers = handler;
}

Map<String, Object?>? _asMap(Object? params) {
  if (params is Map<String, Object?>) return params;
  if (params is Map) return params.cast<String, Object?>();
  return null;
}

ImpersonateUser _user(Object? params) =>
    ImpersonateUser.fromJson((_asMap(params)!['user'] as Map).cast<String, Object?>());

/// `data:` avatar URLs (and any URL over this) are NOT copied onto the
/// snapshot. UserCard renders initials, not the image, but apps still put
/// base64 photos on `avatarUrl` / dump the API user into `metadata`. Ten
/// history entries of those blow the 2MB emit budget and drop the panel.
const int snapshotUriInlineLimit = 2 * 1024;
const int snapshotMetadataInlineLimit = 16 * 1024;

const Map<String, Object?> metadataOnDevice = {
  '__buoyOmitted': 'user-metadata',
  'note': 'User metadata stays on the device.',
};

/// Summarize a `data:` URL and truncate any other oversized one, rather than
/// dropping it — the dashboard shows what KIND of value is there.
String? toWireUri(String? uri) {
  if (uri == null || uri.isEmpty) return uri;
  if (uri.startsWith('data:')) {
    final comma = uri.indexOf(',');
    final header = comma >= 0
        ? uri.substring(0, comma + 1 < 64 ? comma + 1 : 64)
        : 'data:';
    return '$header[${uri.length} chars]';
  }
  if (uri.length <= snapshotUriInlineLimit) return uri;
  return '${uri.substring(0, snapshotUriInlineLimit)}… '
      '[${uri.length - snapshotUriInlineLimit} more]';
}

Map<String, Object?>? _toWireMetadata(Map<String, Object?>? metadata) {
  if (metadata == null) return metadata;
  if (!isOverWireBudget(metadata, snapshotMetadataInlineLimit)) return metadata;
  // Keep `role` so the user card still badges the impersonated user.
  final role = metadata['role'];
  return role is String
      ? {'role': role, ...metadataOnDevice}
      : {...metadataOnDevice};
}

/// Wire form of one serialized user. Built on the JSON rather than the model so
/// the omission markers (which are Maps, where the model declares a String) do
/// not have to be forced through [ImpersonateUser]'s types — the wire form is a
/// projection of on-device truth, not the truth itself.
Map<String, Object?> _toWireUser(Map<String, Object?> user) {
  final out = Map<String, Object?>.of(user);
  if (out.containsKey('avatarUrl')) {
    out['avatarUrl'] = toWireUri(out['avatarUrl'] as String?);
  }
  if (out.containsKey('metadata')) {
    out['metadata'] = _toWireMetadata(
      (out['metadata'] as Map?)?.cast<String, Object?>(),
    );
  }
  return out;
}

/// RN `toWireState` — cap the current user and every history entry's user.
Map<String, Object?> _toWireState(Map<String, Object?> state) {
  final out = Map<String, Object?>.of(state);
  final current = out['currentUser'];
  if (current is Map) {
    out['currentUser'] = _toWireUser(current.cast<String, Object?>());
  }
  final history = out['history'];
  if (history is List) {
    out['history'] = [
      for (final entry in history)
        if (entry is Map)
          {
            ...entry.cast<String, Object?>(),
            if (entry['user'] is Map)
              'user': _toWireUser((entry['user']! as Map).cast<String, Object?>()),
          }
        else
          entry,
    ];
  }
  return out;
}

/// The impersonate tool's sync adapter — mirrors impersonateSyncAdapter.ts.
/// User search proxies to the handler the app passed to registerBuoyImpersonate;
/// if unconfigured, the action reports a descriptive error to the dashboard.
final impersonateSyncAdapter = ToolSyncAdapter(
  version: 1,
  getSnapshot: () => _toWireState(BuoyImpersonate.instance.state.toJson()),
  subscribe: (onChange) {
    BuoyImpersonate.instance.addListener(onChange);
    return () => BuoyImpersonate.instance.removeListener(onChange);
  },
  actions: {
    'searchUsers': (params) async {
      final handler = _registeredSearchUsers;
      if (handler == null) {
        throw StateError(
          'No onSearchUsers configured — pass it to registerBuoyImpersonate()',
        );
      }
      final query = _asMap(params)?['query'] as String? ?? '';
      final users = await handler(query);
      return [for (final u in users) u.toJson()];
    },
    'startImpersonation': (params) =>
        BuoyImpersonate.instance.startImpersonation(_user(params)),
    'stopImpersonation': (_) => BuoyImpersonate.instance.stopImpersonation(),
    'pauseImpersonation': (_) => BuoyImpersonate.instance.pauseImpersonation(),
    'resumeImpersonation': (_) => BuoyImpersonate.instance.resumeImpersonation(),
    'updateSettings': (params) {
      final settings = _asMap(_asMap(params)?['settings']) ?? const {};
      return BuoyImpersonate.instance.updateSettings(
        headerKey: settings['headerKey'] as String?,
        ignorePatterns:
            (settings['ignorePatterns'] as List?)?.cast<String>(),
        showBanner: settings['showBanner'] as bool?,
        dataNukeSettings: settings['dataNukeSettings'] == null
            ? null
            : BuoyImpersonate.instance.state.dataNukeSettings.mergeJson(
                (settings['dataNukeSettings'] as Map).cast<String, Object?>(),
              ),
      );
    },
    'removeFromHistory': (params) => BuoyImpersonate.instance
        .removeFromHistory(_asMap(params)?['userId'] as String? ?? ''),
    'clearHistory': (_) => BuoyImpersonate.instance.clearHistory(),
  },
);
