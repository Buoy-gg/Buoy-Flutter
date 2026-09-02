/// Ports packages/license/src/config.ts, api.ts (validate-key only) and
/// tier.ts — the Keygen round-trip that decides which tier a key grants.
/// Scope A of FLUTTER_TIER_PORT.md.
///
/// PROPRIETARY — Buoy Pro license enforcement. NOT open source. This file is
/// part of the technological measure that controls access to paid Buoy Pro
/// features; altering it so that Pro features unlock without a valid license
/// is a breach of the Buoy EULA (https://buoy.gg/terms).
///
/// Deliberately dependency-free: one POST over `dart:io`'s [HttpClient], so
/// buoy_core keeps its two runtime dependencies (shared_preferences,
/// socket_io_client).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The three tiers, mirroring RN's `BuoyTier`.
///
///  - [anonymous] — no credential, or one that failed validation.
///  - [free] — a validated key on the Free policy.
///  - [pro] — a validated key on the Solo or Business policy.
enum BuoyTier { anonymous, free, pro }

/// Keygen account + policy ids (RN `KEYGEN_CONFIG` / `KEYGEN_POLICIES`).
///
/// None of these are secrets — a policy id identifies a plan, it doesn't grant
/// anything, and the account id already ships in every RN bundle.
class KeygenConfig {
  KeygenConfig._();

  static const accountId = 'b0eba0e8-e904-4906-b644-38f9aab57bed';
  static const apiUrl = 'https://api.keygen.sh/v1/accounts';

  /// Free tier — issued automatically on first dashboard visit.
  static const policyFree = '394e3351-1249-4f73-807a-703408604c0e';

  /// Solo (sold as "Pro"; the id predates the Solo/Business split).
  static const policySolo = 'fa5d3c8f-5379-40f1-b63e-ab8a974b2f28';

  /// Business — an exact clone of the Solo policy.
  static const policyBusiness = '690c2212-8e54-426f-b4b4-002ee1c0ae2b';

  static Uri get validateKeyUri =>
      Uri.parse('$apiUrl/$accountId/licenses/actions/validate-key');
}

/// The license server did not give us a verdict about the key.
///
/// Keygen answers every *licensing* outcome with HTTP 200 and a `meta.code`
/// (VALID, EXPIRED, NOT_FOUND, ...), so a non-2xx or a transport failure is
/// never a statement about this key — it means we failed to ask (quota 429,
/// 5xx, captive portal, offline). Callers MUST treat this like an offline
/// device: keep whatever the cache already proved and try again later.
class LicenseTransportError implements Exception {
  const LicenseTransportError(this.message, this.status);

  final String message;

  /// HTTP status, or null when the request never got an answer at all.
  final int? status;

  @override
  String toString() => 'LicenseTransportError($status): $message';
}

/// The parsed shape of a validate-key response — only the fields the tier
/// decision needs (RN `parseValidationResult` + the bits `resolveTier` reads).
class KeygenValidation {
  const KeygenValidation({
    required this.valid,
    required this.code,
    this.detail,
    this.hasLicense = false,
    this.policyId,
    this.metadataPlan,
  });

  final bool valid;

  /// `meta.code`: VALID, EXPIRED, SUSPENDED, NOT_FOUND, TOO_MANY_MACHINES, ...
  final String code;
  final String? detail;

  /// `data` is null when the license is invalid (e.g. NOT_FOUND).
  final bool hasLicense;

  /// `data.relationships.policy.data.id`.
  final String? policyId;

  /// `data.attributes.metadata.plan`.
  final String? metadataPlan;

  static KeygenValidation fromJson(Map<String, Object?> json) {
    final meta = _asMap(json['meta']) ?? const {};
    final data = _asMap(json['data']);
    final policy = _asMap(_asMap(_asMap(data?['relationships'])?['policy'])?['data']);
    final metadata = _asMap(_asMap(data?['attributes'])?['metadata']);
    return KeygenValidation(
      valid: meta['valid'] == true,
      code: (meta['code'] as String?) ?? 'UNKNOWN',
      detail: meta['detail'] as String?,
      hasLicense: data != null,
      policyId: policy?['id'] as String?,
      metadataPlan: metadata?['plan'] as String?,
    );
  }
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

/// POST validate-key. No `Authorization` header — the key in the body IS the
/// auth. Throws [LicenseTransportError] for anything that is not a verdict.
Future<KeygenValidation> validateLicenseKey(
  String licenseKey, {
  HttpClient Function()? clientFactory,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final client = (clientFactory ?? HttpClient.new)()..connectionTimeout = timeout;
  try {
    final HttpClientResponse response;
    final String body;
    try {
      final request = await client.postUrl(KeygenConfig.validateKeyUri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.api+json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.api+json');
      request.write(jsonEncode({'meta': {'key': licenseKey}}));
      response = await request.close().timeout(timeout);
      body = await response.transform(utf8.decoder).join().timeout(timeout);
    } on LicenseTransportError {
      rethrow;
    } catch (error) {
      // Offline, DNS, TLS, timeout: the request never completed.
      throw LicenseTransportError(error.toString(), null);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LicenseTransportError(_describeFailure(body, response.statusCode), response.statusCode);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      // 200 with a body that isn't Keygen's JSON — something is intercepting.
      throw LicenseTransportError('License server returned an unreadable response', response.statusCode);
    }
    final map = _asMap(decoded);
    if (map == null) {
      throw LicenseTransportError('License server returned an unreadable response', response.statusCode);
    }
    return KeygenValidation.fromJson(map);
  } finally {
    client.close(force: true);
  }
}

/// Best-effort detail from a failed response; a proxy's HTML error page is not
/// JSON, so the status is what actually matters.
String _describeFailure(String body, int status) {
  try {
    final errors = _asMap(jsonDecode(body))?['errors'];
    if (errors is List && errors.isNotEmpty) {
      final detail = _asMap(errors.first)?['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
  } catch (_) {}
  return 'HTTP $status';
}

/// Codes that mean the license itself is invalid (RN `isFatalLicenseError`).
bool isFatalLicenseCode(String code) => const {
      'NOT_FOUND',
      'SUSPENDED',
      'EXPIRED',
      'BANNED',
      'PRODUCT_SCOPE_MISMATCH',
    }.contains(code);

/// Which tier a *validated* license grants (RN `resolveTier`).
///
/// The policy is the primary signal because Keygen sets it on every
/// create/upgrade/downgrade; `metadata.plan` is only a fallback for licenses
/// created outside that flow.
///
/// Unrecognized policies resolve to [BuoyTier.pro] **on purpose**: a licence
/// hand-made in the Keygen dashboard (a comp, a support extension, a plan
/// whose id predates this build) has no metadata and an unknown policy — and
/// those are always paid. The opposite default would silently downgrade paying
/// customers every time a policy is added before clients ship. Free keys ARE
/// recognized, which is the case that matters.
BuoyTier resolveTier({String? policyId, String? metadataPlan}) {
  if (policyId == KeygenConfig.policyFree) return BuoyTier.free;
  if (policyId == KeygenConfig.policySolo || policyId == KeygenConfig.policyBusiness) {
    return BuoyTier.pro;
  }
  if (metadataPlan == 'free') return BuoyTier.free;
  return BuoyTier.pro;
}

/// The tier to fall back to on a FATAL verdict (RN `tierAfterFatalError`).
///
/// `EXPIRED` is **free**, not anonymous: the website's `subscription_expired`
/// webhook swaps that same key onto the Free policy, so free is the steady
/// state and anonymous is only the gap before the webhook lands — which would
/// hit a lapsing subscriber at the exact moment they decide whether to
/// re-subscribe. Every other fatal code means "not our key" or a deliberate
/// revocation, and proves no account.
BuoyTier tierAfterFatalError(String code) =>
    code == 'EXPIRED' ? BuoyTier.free : BuoyTier.anonymous;
