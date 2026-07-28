/// Ports packages/env-tools/src/env/types/types.ts + utils/helpers.ts.
///
/// Pure Dart (no Flutter imports) so the validation model is unit-testable and
/// the wire shapes stay 1:1 with the RN adapter. Holds the env var type enum,
/// the [RequiredEnvVar] config (RN's `string | {key,expectedValue} |
/// {key,expectedType}` union), the processed [EnvVarInfo]/[EnvVarStats], and the
/// fluent `envVar()` builder.
library;

/// Ports `EnvVarType` — the types [getEnvVarType] can report. RN is a string
/// union `string|number|boolean|array|object|url`; `unknown` is the detector's
/// fallback. Serialized as the lowercase name (RN parity).
enum EnvVarType {
  string,
  number,
  boolean,
  array,
  object,
  url,
  unknown;

  /// The RN wire/label string (`"string"`, `"url"`, …).
  String get wire => name;

  /// Parse the RN wire string back to an [EnvVarType] (unknown on no match).
  static EnvVarType fromWire(String value) {
    for (final t in EnvVarType.values) {
      if (t.name == value) return t;
    }
    return EnvVarType.unknown;
  }
}

/// Ports the `RequiredEnvVar` union. RN allows three shapes; Dart models them as
/// one class with three named constructors and an RN-shaped [toJson]:
/// - [RequiredEnvVar.exists] → serializes to a bare `String` (the key).
/// - [RequiredEnvVar.value] → `{key, expectedValue, description?}`.
/// - [RequiredEnvVar.type] → `{key, expectedType, description?}`.
class RequiredEnvVar {
  const RequiredEnvVar._({required this.key, this.description})
      : expectedValue = null,
        expectedType = null;

  /// Just check the variable exists (RN: a bare string).
  const RequiredEnvVar.exists(this.key)
      : expectedValue = null,
        expectedType = null,
        description = null;

  /// Check the variable equals [expectedValue].
  const RequiredEnvVar.value(this.key, String this.expectedValue,
      {this.description})
      : expectedType = null;

  /// Check the variable's detected type equals [expectedType].
  const RequiredEnvVar.type(this.key, EnvVarType this.expectedType,
      {this.description})
      : expectedValue = null;

  final String key;
  final String? expectedValue;
  final EnvVarType? expectedType;
  final String? description;

  /// RN-shaped JSON for the sync snapshot: a bare String when it's a pure
  /// existence check, else an object with `expectedValue` or `expectedType`.
  Object toJson() {
    if (expectedValue == null && expectedType == null) return key;
    final map = <String, Object>{'key': key};
    if (expectedValue != null) map['expectedValue'] = expectedValue!;
    if (expectedType != null) map['expectedType'] = expectedType!.wire;
    if (description != null) map['description'] = description!;
    return map;
  }

  /// Inverse of [toJson] — mirrors what the desktop would send (String or map).
  static RequiredEnvVar fromJson(Object json) {
    if (json is String) return RequiredEnvVar.exists(json);
    final map = json as Map;
    final key = map['key'] as String;
    final desc = map['description'] as String?;
    if (map['expectedValue'] != null) {
      return RequiredEnvVar.value(key, map['expectedValue'] as String,
          description: desc);
    }
    if (map['expectedType'] != null) {
      return RequiredEnvVar.type(
          key, EnvVarType.fromWire(map['expectedType'] as String),
          description: desc);
    }
    return RequiredEnvVar._(key: key, description: desc);
  }
}

/// Ports the `EnvVarInfo.status` union — a variable's validation state.
enum EnvVarStatus {
  requiredPresent,
  requiredMissing,
  requiredWrongValue,
  requiredWrongType,
  optionalPresent,
}

/// Ports `EnvVarInfo` — a processed variable annotated with validation state.
class EnvVarInfo {
  const EnvVarInfo({
    required this.key,
    required this.value,
    required this.status,
    required this.category,
    this.expectedValue,
    this.expectedType,
    this.description,
  });

  final String key;

  /// The collected string value, or null when the required var is missing.
  final String? value;
  final String? expectedValue;
  final EnvVarType? expectedType;
  final String? description;
  final EnvVarStatus status;

  /// `"required"` or `"optional"` (RN parity).
  final String category;
}

/// Ports `EnvVarStats` — aggregate counts for the health header + filter cards.
class EnvVarStats {
  const EnvVarStats({
    required this.totalCount,
    required this.requiredCount,
    required this.missingCount,
    required this.wrongValueCount,
    required this.wrongTypeCount,
    required this.presentRequiredCount,
    required this.optionalCount,
  });

  final int totalCount;
  final int requiredCount;
  final int missingCount;
  final int wrongValueCount;
  final int wrongTypeCount;
  final int presentRequiredCount;
  final int optionalCount;
}

/// Ports helpers.ts `EnvVarBuilder` — the fluent builder returned by [envVar].
/// A type and a value are mutually exclusive (RN clears the other). `.build()`
/// with neither type nor value collapses to a pure existence check.
class EnvVarBuilder {
  EnvVarBuilder(this._key);

  final String _key;
  EnvVarType? _expectedType;
  String? _expectedValue;
  String? _description;

  /// Just check the variable exists.
  RequiredEnvVar exists() => RequiredEnvVar.exists(_key);

  /// Check for a specific value (clears any expected type — RN parity).
  EnvVarBuilder withValue(String value) {
    _expectedValue = value;
    _expectedType = null;
    return this;
  }

  /// Check for a specific type (clears any expected value — RN parity).
  /// Accepts an [EnvVarType] or its wire string (e.g. `'boolean'`, `'url'`).
  EnvVarBuilder withType(Object type) {
    _expectedType =
        type is EnvVarType ? type : EnvVarType.fromWire(type as String);
    _expectedValue = null;
    return this;
  }

  /// Add a documentation description.
  EnvVarBuilder withDescription(String desc) {
    _description = desc;
    return this;
  }

  /// Build the final [RequiredEnvVar].
  RequiredEnvVar build() {
    if (_expectedValue != null) {
      return RequiredEnvVar.value(_key, _expectedValue!,
          description: _description);
    }
    if (_expectedType != null) {
      return RequiredEnvVar.type(_key, _expectedType!,
          description: _description);
    }
    return RequiredEnvVar._(key: _key, description: _description);
  }
}

/// Ports helpers.ts `envVar()` — start a fluent [RequiredEnvVar] definition.
EnvVarBuilder envVar(String key) => EnvVarBuilder(key);

/// Ports helpers.ts `createEnvVarConfig()` — an identity pass-through that lets
/// teams co-locate their required-var definitions. Accepts bare key strings
/// (coerced to existence checks) or [RequiredEnvVar]s.
List<RequiredEnvVar> createEnvVarConfig(List<Object> vars) {
  return [
    for (final v in vars)
      v is RequiredEnvVar ? v : RequiredEnvVar.exists(v as String),
  ];
}
