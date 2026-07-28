/// Ports packages/impersonate/src/impersonate/types/types.ts.
///
/// The impersonation data model — [User], [HistoryEntry], [DataNukeSettings],
/// [ImpersonationState], and the developer-defaults config [ImpersonateDefaults].
/// JSON field names are byte-for-byte identical to the RN source so the persisted
/// blob (`@buoy/impersonate/state`) and the sync-adapter snapshot line up with
/// Buoy Desktop and the MCP server.
library;

/// A user that can be impersonated. `id` is the value sent in the impersonation
/// header. RN: `User`.
class ImpersonateUser {
  const ImpersonateUser({
    required this.id,
    this.displayName,
    this.email,
    this.avatarUrl,
    this.metadata,
  });

  /// Unique user identifier — sent in the impersonation header.
  final String id;

  /// Display name for UI (falls back to email, then id).
  final String? displayName;
  final String? email;

  /// URL to the user's avatar image.
  final String? avatarUrl;

  /// Extra key/value pairs shown on the UserCard (e.g. `role`).
  final Map<String, Object?>? metadata;

  Map<String, Object?> toJson() => {
    'id': id,
    if (displayName != null) 'displayName': displayName,
    if (email != null) 'email': email,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    if (metadata != null) 'metadata': metadata,
  };

  static ImpersonateUser fromJson(Map<String, Object?> json) => ImpersonateUser(
    id: json['id'] as String,
    displayName: json['displayName'] as String?,
    email: json['email'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
  );

  @override
  bool operator ==(Object other) =>
      other is ImpersonateUser &&
      other.id == id &&
      other.displayName == displayName &&
      other.email == email &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(id, displayName, email, avatarUrl);
}

/// A history entry with the ISO timestamp of when the impersonation started.
/// RN: `HistoryEntry`.
class HistoryEntry {
  const HistoryEntry({required this.user, required this.lastUsedAt});

  final ImpersonateUser user;

  /// When the impersonation started (ISO-8601 string).
  final String lastUsedAt;

  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'lastUsedAt': lastUsedAt,
  };

  static HistoryEntry fromJson(Map<String, Object?> json) => HistoryEntry(
    user: ImpersonateUser.fromJson((json['user'] as Map).cast<String, Object?>()),
    lastUsedAt: json['lastUsedAt'] as String,
  );
}

/// Which data stores to clear on impersonation change. RN: `DataNukeSettings`.
class DataNukeSettings {
  const DataNukeSettings({
    required this.reactQuery,
    required this.redux,
    required this.asyncStorage,
    required this.mmkv,
  });

  final bool reactQuery;
  final bool redux;

  /// Clear app data (dangerous — default off).
  final bool asyncStorage;

  /// Clear MMKV (dangerous — default off).
  final bool mmkv;

  /// RN `DEFAULT_DATA_NUKE_SETTINGS`: reactQuery/redux on, storage off.
  static const DataNukeSettings defaults = DataNukeSettings(
    reactQuery: true,
    redux: true,
    asyncStorage: false,
    mmkv: false,
  );

  DataNukeSettings copyWith({
    bool? reactQuery,
    bool? redux,
    bool? asyncStorage,
    bool? mmkv,
  }) => DataNukeSettings(
    reactQuery: reactQuery ?? this.reactQuery,
    redux: redux ?? this.redux,
    asyncStorage: asyncStorage ?? this.asyncStorage,
    mmkv: mmkv ?? this.mmkv,
  );

  Map<String, Object?> toJson() => {
    'reactQuery': reactQuery,
    'redux': redux,
    'asyncStorage': asyncStorage,
    'mmkv': mmkv,
  };

  /// Merge a partial JSON map (missing keys keep [this]'s values) — RN's
  /// `{ ...current, ...parsed.dataNukeSettings }` spread.
  DataNukeSettings mergeJson(Map<String, Object?>? json) {
    if (json == null) return this;
    return DataNukeSettings(
      reactQuery: json['reactQuery'] as bool? ?? reactQuery,
      redux: json['redux'] as bool? ?? redux,
      asyncStorage: json['asyncStorage'] as bool? ?? asyncStorage,
      mmkv: json['mmkv'] as bool? ?? mmkv,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DataNukeSettings &&
      other.reactQuery == reactQuery &&
      other.redux == redux &&
      other.asyncStorage == asyncStorage &&
      other.mmkv == mmkv;

  @override
  int get hashCode => Object.hash(reactQuery, redux, asyncStorage, mmkv);
}

/// The impersonation state held by [BuoyImpersonate]. RN: `ImpersonationState`.
class ImpersonationState {
  const ImpersonationState({
    this.isActive = false,
    this.isPaused = false,
    this.currentUser,
    this.headerKey = defaultHeaderKey,
    this.ignorePatterns = const [],
    this.dataNukeSettings = DataNukeSettings.defaults,
    this.showBanner = true,
    this.history = const [],
  });

  /// RN `DEFAULT_STATE.headerKey`.
  static const String defaultHeaderKey = 'x-impersonate-user-id';

  final bool isActive;
  final bool isPaused;
  final ImpersonateUser? currentUser;
  final String headerKey;

  /// URL patterns excluded from header injection (regex strings).
  final List<String> ignorePatterns;
  final DataNukeSettings dataNukeSettings;
  final bool showBanner;

  /// Recently impersonated users (max 10). RN `MAX_HISTORY`.
  final List<HistoryEntry> history;

  ImpersonationState copyWith({
    bool? isActive,
    bool? isPaused,
    ImpersonateUser? currentUser,
    bool clearCurrentUser = false,
    String? headerKey,
    List<String>? ignorePatterns,
    DataNukeSettings? dataNukeSettings,
    bool? showBanner,
    List<HistoryEntry>? history,
  }) => ImpersonationState(
    isActive: isActive ?? this.isActive,
    isPaused: isPaused ?? this.isPaused,
    currentUser: clearCurrentUser ? null : (currentUser ?? this.currentUser),
    headerKey: headerKey ?? this.headerKey,
    ignorePatterns: ignorePatterns ?? this.ignorePatterns,
    dataNukeSettings: dataNukeSettings ?? this.dataNukeSettings,
    showBanner: showBanner ?? this.showBanner,
    history: history ?? this.history,
  );

  Map<String, Object?> toJson() => {
    'isActive': isActive,
    'isPaused': isPaused,
    'currentUser': currentUser?.toJson(),
    'headerKey': headerKey,
    'ignorePatterns': ignorePatterns,
    'dataNukeSettings': dataNukeSettings.toJson(),
    'showBanner': showBanner,
    'history': [for (final h in history) h.toJson()],
  };
}

/// Developer-configurable defaults (override hardcoded, overridden by persisted).
/// RN: `ImpersonateDefaults`.
class ImpersonateDefaults {
  const ImpersonateDefaults({
    this.headerKey,
    this.dataNukeSettings,
    this.showBanner,
  });

  final String? headerKey;

  /// Partial overrides merged over [DataNukeSettings.defaults].
  final Map<String, Object?>? dataNukeSettings;
  final bool? showBanner;
}
