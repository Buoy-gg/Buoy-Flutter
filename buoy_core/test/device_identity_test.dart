import 'package:buoy_core/buoy_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The default device identity must be unique per install and stable across
/// launches — the old default (slugified name) made every device on a build
/// the same device to the broker. See DEVICE_IDENTITY_COLLISION.md.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetInstallIdForTests();
  });

  test('generateInstallId is 8 lowercase hex chars and not constant', () {
    final a = generateInstallId();
    expect(a, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(generateInstallId(), isNot(a));
  });

  test('tail lands in the id and its last 4 chars in the name', () {
    final id = buildDeviceIdentity(platform: 'ios', installId: '3f9a2c1d');
    expect(id.deviceId, 'flutter-app-ios-3f9a2c1d');
    expect(id.deviceName, 'Flutter App (ios · 2c1d)');
  });

  test('an explicit name is verbatim; a pinned id drops the tail', () {
    final named = buildDeviceIdentity(
      platform: 'android',
      installId: '3f9a2c1d',
      deviceName: 'QA Pixel',
    );
    expect(named.deviceName, 'QA Pixel');
    expect(named.deviceId, 'qa-pixel-android-3f9a2c1d');
    final pinned = buildDeviceIdentity(
      platform: 'ios',
      installId: '3f9a2c1d',
      deviceId: 'qa-phone-1',
    );
    expect(pinned.deviceId, 'qa-phone-1');
    expect(pinned.deviceName, 'Flutter App (ios)');
  });

  test('loadInstallId mints once and restores from SharedPreferences', () async {
    final first = await loadInstallId();
    resetInstallIdForTests();
    final second = await loadInstallId();
    expect(second, first);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('@react_buoy_sync_device_id'), first);
  });
}
