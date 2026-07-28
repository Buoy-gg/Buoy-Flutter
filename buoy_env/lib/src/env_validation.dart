/// Ports packages/env-tools/src/env/utils/envTypeDetector.ts + utils.ts.
///
/// Pure Dart (no Flutter imports) — the type-detection + validation + stats +
/// health math, unit-tested against RN-derived expected values.
library;

import 'dart:convert';

import 'env_types.dart';

/// Ports `getEnvVarType` — detect the type of a collected value. On device the
/// values are always strings (the app hands us `Map<String,String>`), matching
/// RN's post-`displayValue` string map, so the string-analysis branch is what
/// runs in practice; the leading non-string checks are kept for parity.
///
/// Order (RN): bool/number Dart types → List → Map → then for strings:
/// `{…}`/`[…]` JSON → object/array (else string); the boolean words
/// (true/false/enabled/disabled/yes/no/on/off) → boolean; numeric string →
/// number; http(s) → url; contains `,` → array; else string.
EnvVarType getEnvVarType(Object? value) {
  if (value is bool) return EnvVarType.boolean;
  if (value is num) return EnvVarType.number;
  if (value is List) return EnvVarType.array;
  if (value is Map) return EnvVarType.object;

  if (value is String) {
    final str = value;

    // Looks like JSON?
    if ((str.startsWith('{') && str.endsWith('}')) ||
        (str.startsWith('[') && str.endsWith(']'))) {
      try {
        final parsed = jsonDecode(str);
        return parsed is List ? EnvVarType.array : EnvVarType.object;
      } catch (_) {
        return EnvVarType.string;
      }
    }

    // Boolean-like string.
    final lower = str.toLowerCase();
    if (lower == 'true' ||
        lower == 'false' ||
        lower == 'enabled' ||
        lower == 'disabled' ||
        lower == 'yes' ||
        lower == 'no' ||
        lower == 'on' ||
        lower == 'off') {
      return EnvVarType.boolean;
    }

    // Number-like string (RN: !isNaN(Number(str)) && trim !== "").
    if (str.trim().isNotEmpty && _isNumeric(str)) {
      return EnvVarType.number;
    }

    // URL.
    if (str.startsWith('http://') || str.startsWith('https://')) {
      return EnvVarType.url;
    }

    // Comma-separated array.
    if (str.contains(',')) return EnvVarType.array;

    return EnvVarType.string;
  }

  return EnvVarType.unknown;
}

/// Mirrors JS `!isNaN(Number(str))`: JS `Number("")` is 0, but the caller guards
/// empty; `Number` also accepts leading/trailing whitespace, hex (`0x`), `Infinity`.
/// `num.tryParse` covers the decimal/scientific cases that matter here; hex and
/// Infinity are vanishingly rare for env values, so this stays faithful in
/// practice while remaining pure.
bool _isNumeric(String str) {
  final trimmed = str.trim();
  if (trimmed.isEmpty) return false;
  if (num.tryParse(trimmed) != null) return true;
  if (trimmed == 'Infinity' || trimmed == '-Infinity') return true;
  if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
    return int.tryParse(trimmed.substring(2), radix: 16) != null;
  }
  return false;
}

/// The result of [processEnvVars] — categorized, validated variables.
class ProcessedEnvVars {
  const ProcessedEnvVars({required this.requiredVars, required this.optionalVars});

  final List<EnvVarInfo> requiredVars;
  final List<EnvVarInfo> optionalVars;
}

const Map<EnvVarStatus, int> _statusOrder = {
  EnvVarStatus.requiredMissing: 0,
  EnvVarStatus.requiredWrongValue: 1,
  EnvVarStatus.requiredWrongType: 2,
  EnvVarStatus.requiredPresent: 3,
  EnvVarStatus.optionalPresent: 4,
};

/// Ports utils.ts `processEnvVars` — combine the collected values with the
/// required-var config into categorized [EnvVarInfo]s. `collected` is the
/// device env map (already strings). Required-var status resolution + the
/// `sk_*` / `production or development` expected-value special cases are 1:1.
ProcessedEnvVars processEnvVars(
  Map<String, String> collected,
  List<RequiredEnvVar> requiredEnvVars,
) {
  final requiredVarInfos = <EnvVarInfo>[];
  final optionalVarInfos = <EnvVarInfo>[];
  final processedKeys = <String>{};

  for (final req in requiredEnvVars) {
    final key = req.key;
    final expectedValue = req.expectedValue;
    final expectedType = req.expectedType;
    final description = req.description;

    processedKeys.add(key);
    final isPresent = collected.containsKey(key);
    final actualValue = collected[key];

    EnvVarStatus status;
    if (!isPresent) {
      status = EnvVarStatus.requiredMissing;
    } else if (expectedValue != null) {
      bool valueMatches;
      if (expectedValue == 'sk_*') {
        valueMatches = actualValue!.startsWith('sk_');
      } else if (expectedValue == 'production or development') {
        valueMatches =
            actualValue == 'production' || actualValue == 'development';
      } else {
        valueMatches = actualValue == expectedValue;
      }
      status = valueMatches
          ? EnvVarStatus.requiredPresent
          : EnvVarStatus.requiredWrongValue;
    } else if (expectedType != null &&
        getEnvVarType(actualValue).wire.toLowerCase() !=
            expectedType.wire.toLowerCase()) {
      status = EnvVarStatus.requiredWrongType;
    } else {
      status = EnvVarStatus.requiredPresent;
    }

    requiredVarInfos.add(EnvVarInfo(
      key: key,
      value: actualValue,
      expectedValue: expectedValue,
      expectedType: expectedType,
      description: description,
      status: status,
      category: 'required',
    ));
  }

  collected.forEach((key, value) {
    if (!processedKeys.contains(key)) {
      optionalVarInfos.add(EnvVarInfo(
        key: key,
        value: value,
        status: EnvVarStatus.optionalPresent,
        category: 'optional',
      ));
    }
  });

  requiredVarInfos.sort((a, b) {
    final oa = _statusOrder[a.status]!;
    final ob = _statusOrder[b.status]!;
    if (oa != ob) return oa - ob;
    return a.key.compareTo(b.key);
  });
  optionalVarInfos.sort((a, b) => a.key.compareTo(b.key));

  return ProcessedEnvVars(
    requiredVars: requiredVarInfos,
    optionalVars: optionalVarInfos,
  );
}

/// Ports utils.ts `calculateStats`.
EnvVarStats calculateStats(
  List<EnvVarInfo> requiredVars,
  List<EnvVarInfo> optionalVars,
  Map<String, String> totalEnvVars,
) {
  int count(EnvVarStatus s) =>
      requiredVars.where((v) => v.status == s).length;
  return EnvVarStats(
    totalCount: totalEnvVars.length,
    requiredCount: requiredVars.length,
    missingCount: count(EnvVarStatus.requiredMissing),
    wrongValueCount: count(EnvVarStatus.requiredWrongValue),
    wrongTypeCount: count(EnvVarStatus.requiredWrongType),
    presentRequiredCount: count(EnvVarStatus.requiredPresent),
    optionalCount: optionalVars.length,
  );
}

/// Health % (EnvVarsModal): present-required / required, rounded; 100 when there
/// are no required vars.
int healthPercentage(EnvVarStats stats) {
  if (stats.requiredCount <= 0) return 100;
  return (stats.presentRequiredCount / stats.requiredCount * 100).round();
}

/// Health status label (EnvVarsModal): 100 HEALTHY / ≥75 WARNING / ≥50 ERROR /
/// else CRITICAL.
String healthStatusLabel(int pct) {
  if (pct == 100) return 'HEALTHY';
  if (pct >= 75) return 'WARNING';
  if (pct >= 50) return 'ERROR';
  return 'CRITICAL';
}
