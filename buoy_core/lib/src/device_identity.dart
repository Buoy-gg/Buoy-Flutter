import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants.dart';

/// How this app introduces itself to the Buoy Desktop broker — the Dart
/// mirror of RN's `deviceIdentity.ts`.
///
/// The default id used to be the slugified device name — a BUILD identity —
/// so every device running one build registered under the same id and the
/// broker handed that identity to whichever connected last (see
/// DEVICE_IDENTITY_COLLISION.md). Now the id carries a per-install tail
/// minted once and persisted in SharedPreferences:
///
///   deviceId   = `<slug>-<platform>-<8 hex>`      e.g. flutter-app-ios-3f9a2c1d
///   deviceName = `<label> (<platform> · <last 4>)` e.g. Flutter App (ios · 2c1d)
///
/// An explicit `deviceId` bypasses the tail; whoever pins an id owns its
/// uniqueness. An explicit `deviceName` is used verbatim.
class DeviceIdentity {
  const DeviceIdentity({required this.deviceName, required this.deviceId});
  final String deviceName;
  final String deviceId;
}

const int installIdLength = 8;

/// 8 lowercase hex chars — readable in logs, random enough for a LAN.
String generateInstallId([Random? random]) {
  final rng = random ?? Random();
  final buffer = StringBuffer();
  for (var i = 0; i < installIdLength; i++) {
    buffer.write(rng.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
}

String _slugify(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'(^-|-$)'), '');

/// Pure: turns the inputs into the id/name pair the broker sees.
DeviceIdentity buildDeviceIdentity({
  required String platform,
  required String installId,
  String? deviceName,
  String? deviceId,
}) {
  const defaultLabel = 'Flutter App';
  final label = deviceName ?? defaultLabel;
  final slug = _slugify(label).isEmpty ? 'buoy' : _slugify(label);
  if (deviceId != null) {
    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: deviceName ?? '$defaultLabel ($platform)',
    );
  }
  return DeviceIdentity(
    deviceId: '$slug-$platform-$installId',
    deviceName: deviceName ??
        '$defaultLabel ($platform · ${installId.substring(installId.length - 4)})',
  );
}

Future<String>? _installId;

/// The persisted per-install tail: read it, or mint and store it on the first
/// dial. Storage failures degrade to a fresh in-memory id rather than
/// blocking the socket. Memoized per isolate.
Future<String> loadInstallId() => _installId ??= _load();

Future<String> _load() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(BuoyStorageKeys.syncDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = generateInstallId();
    await prefs.setString(BuoyStorageKeys.syncDeviceId, fresh);
    return fresh;
  } catch (_) {
    return generateInstallId();
  }
}

/// Tests only.
void resetInstallIdForTests() => _installId = null;
