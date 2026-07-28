import 'package:buoy_impersonate/buoy_impersonate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_impersonate/src/impersonate_tool/user_avatar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const admin = ImpersonateUser(
    id: 'usr_admin_01',
    displayName: 'Professor Oak',
    email: 'oak@pokedex.dev',
    metadata: {'role': 'admin', 'canEditDex': true},
  );
  const member = ImpersonateUser(id: 'usr_member_02', displayName: 'Ash');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await BuoyImpersonate.instance.resetForTest();
  });

  group('types JSON round-trip', () {
    test('User survives toJson/fromJson including metadata', () {
      final json = admin.toJson();
      expect(json['id'], 'usr_admin_01');
      expect(json['displayName'], 'Professor Oak');
      expect((json['metadata'] as Map)['role'], 'admin');
      expect(ImpersonateUser.fromJson(json), admin);
    });

    test('ImpersonationState snapshot has the exact RN keys', () {
      const state = ImpersonationState(
        isActive: true,
        currentUser: admin,
        history: [HistoryEntry(user: admin, lastUsedAt: '2026-01-01T00:00:00Z')],
      );
      final json = state.toJson();
      expect(json.keys, containsAll(<String>[
        'isActive',
        'isPaused',
        'currentUser',
        'headerKey',
        'ignorePatterns',
        'dataNukeSettings',
        'showBanner',
        'history',
      ]));
      expect(json['headerKey'], 'x-impersonate-user-id');
      expect((json['dataNukeSettings'] as Map).keys, containsAll(<String>[
        'reactQuery',
        'redux',
        'asyncStorage',
        'mmkv',
      ]));
      expect((json['history'] as List).first, {
        'user': admin.toJson(),
        'lastUsedAt': '2026-01-01T00:00:00Z',
      });
    });

    test('DataNukeSettings defaults match RN (rq/redux on, storage off)', () {
      expect(DataNukeSettings.defaults.reactQuery, true);
      expect(DataNukeSettings.defaults.redux, true);
      expect(DataNukeSettings.defaults.asyncStorage, false);
      expect(DataNukeSettings.defaults.mmkv, false);
    });
  });

  group('store actions', () {
    test('startImpersonation activates + records history + exposes header', () async {
      final store = BuoyImpersonate.instance;
      expect(store.isImpersonating, false);
      expect(store.impersonationHeaders, isEmpty);

      await store.startImpersonation(admin);

      expect(store.state.isActive, true);
      expect(store.state.currentUser, admin);
      expect(store.isImpersonating, true);
      expect(store.impersonatedUserId, 'usr_admin_01');
      expect(store.impersonationHeaders, {'x-impersonate-user-id': 'usr_admin_01'});
      expect(store.state.history.length, 1);
      expect(store.state.history.first.user, admin);
    });

    test('stopImpersonation clears active + header (history kept)', () async {
      final store = BuoyImpersonate.instance;
      await store.startImpersonation(admin);
      await store.stopImpersonation();
      expect(store.state.isActive, false);
      expect(store.state.currentUser, isNull);
      expect(store.isImpersonating, false);
      expect(store.impersonationHeaders, isEmpty);
      expect(store.state.history.length, 1); // history preserved
    });

    test('pause suppresses header injection without ending session', () async {
      final store = BuoyImpersonate.instance;
      await store.startImpersonation(admin);
      await store.pauseImpersonation();
      expect(store.state.isActive, true);
      expect(store.state.isPaused, true);
      expect(store.isImpersonating, false); // paused → no header
      expect(store.impersonationHeaders, isEmpty);
      await store.resumeImpersonation();
      expect(store.isImpersonating, true);
    });

    test('history dedupes by id and caps at 10', () async {
      final store = BuoyImpersonate.instance;
      for (var i = 0; i < 12; i++) {
        await store.startImpersonation(ImpersonateUser(id: 'u$i'));
      }
      expect(store.state.history.length, 10);
      // Most recent first.
      expect(store.state.history.first.user.id, 'u11');

      // Re-selecting an existing user moves it to front without growing.
      await store.startImpersonation(const ImpersonateUser(id: 'u5'));
      expect(store.state.history.length, 10);
      expect(store.state.history.first.user.id, 'u5');
      expect(
        store.state.history.where((e) => e.user.id == 'u5').length,
        1,
      );
    });

    test('removeFromHistory + clearHistory', () async {
      final store = BuoyImpersonate.instance;
      await store.startImpersonation(admin);
      await store.startImpersonation(member);
      await store.removeFromHistory(admin.id);
      expect(store.state.history.any((e) => e.user.id == admin.id), false);
      await store.clearHistory();
      expect(store.state.history, isEmpty);
    });

    test('updateSettings changes headerKey used in injected header', () async {
      final store = BuoyImpersonate.instance;
      await store.startImpersonation(admin);
      await store.updateSettings(headerKey: 'x-admin-impersonate');
      expect(store.impersonationHeaders, {'x-admin-impersonate': 'usr_admin_01'});
    });
  });

  group('persistence round-trip', () {
    test('active session + settings survive a cold restart', () async {
      final store = BuoyImpersonate.instance;
      await store.initialize();
      await store.updateSettings(headerKey: 'x-imp');
      await store.startImpersonation(admin);

      // Simulate cold restart: reset the singleton, reload from prefs.
      await store.resetForTest();
      expect(store.state.isActive, false);
      await store.initialize();

      expect(store.state.isActive, true);
      expect(store.state.currentUser?.id, 'usr_admin_01');
      expect(store.state.headerKey, 'x-imp');
      expect(store.isImpersonating, true);
      expect(store.state.history.length, 1);
    });

    test('persisted blob is stored under the exact RN key', () async {
      await BuoyImpersonate.instance.initialize();
      await BuoyImpersonate.instance.startImpersonation(admin);
      final prefs = await SharedPreferences.getInstance();
      expect(impersonateStorageKey, '@buoy/impersonate/state');
      expect(prefs.getString(impersonateStorageKey), isNotNull);
    });
  });

  group('developer defaults precedence', () {
    test('defaults apply before initialize; persisted wins after', () async {
      final store = BuoyImpersonate.instance;
      store.setDeveloperDefaults(
        const ImpersonateDefaults(headerKey: 'x-dev-default', showBanner: false),
      );
      await store.initialize();
      expect(store.state.headerKey, 'x-dev-default');
      expect(store.state.showBanner, false);
    });
  });

  group('sync adapter wire shape', () {
    test('version + snapshot keys mirror RN adapter', () {
      expect(impersonateSyncAdapter.version, 1);
      final snap = impersonateSyncAdapter.getSnapshot() as Map<String, Object?>;
      expect(snap['isActive'], false);
      expect(snap.containsKey('history'), true);
    });

    test('action names match RN exactly', () {
      expect(impersonateSyncAdapter.actions.keys, containsAll(<String>[
        'searchUsers',
        'startImpersonation',
        'stopImpersonation',
        'pauseImpersonation',
        'resumeImpersonation',
        'updateSettings',
        'removeFromHistory',
        'clearHistory',
      ]));
    });

    test('remote startImpersonation action drives the store', () async {
      await impersonateSyncAdapter.actions['startImpersonation']!({
        'user': admin.toJson(),
      });
      expect(BuoyImpersonate.instance.impersonatedUserId, 'usr_admin_01');
      await impersonateSyncAdapter.actions['stopImpersonation']!(null);
      expect(BuoyImpersonate.instance.isImpersonating, false);
    });

    test('searchUsers proxies the registered handler', () async {
      registerImpersonateSearchUsers((q) async => [admin, member]);
      final result = await impersonateSyncAdapter.actions['searchUsers']!({
        'query': 'oak',
      });
      expect((result as List).length, 2);
      expect((result.first as Map)['id'], 'usr_admin_01');
      registerImpersonateSearchUsers(null);
    });

    test('searchUsers throws a descriptive error when unconfigured', () async {
      registerImpersonateSearchUsers(null);
      expect(
        () => impersonateSyncAdapter.actions['searchUsers']!({'query': 'x'}),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('UserAvatar parity', () {
    test('getInitials matches RN (email → first letter, name → two)', () {
      expect(getInitials('oak@pokedex.dev'), 'O');
      expect(getInitials('Professor Oak'), 'PO');
      expect(getInitials('Ash'), 'A');
      expect(getInitials(''), '?');
    });

    test('getAvatarColor is deterministic and in-palette', () {
      final c1 = getAvatarColor('usr_admin_01');
      final c2 = getAvatarColor('usr_admin_01');
      expect(c1, c2);
      expect(avatarColors.contains(c1), true);
    });
  });
}
