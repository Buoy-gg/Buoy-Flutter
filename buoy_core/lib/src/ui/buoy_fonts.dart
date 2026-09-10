/// The monospace family — the Dart twin of RN's `monoFont`
/// (`packages/floating-tools-core/src/fonts.ts`).
///
/// React Native's `fontFamily: "monospace"` is an ANDROID family name; iOS has
/// no family called that and silently falls back to the system font, which is
/// why every "monospace" label in Buoy was proportional there. Flutter, in
/// contrast, DOES resolve `monospace` on iOS — to a face with much taller
/// metrics — so the two frameworks drew different type for the same style. The
/// cross-framework parity sheet measured it: `badges/pill-md` came out 5.6 pt
/// wider and 4 pt taller on Flutter than on RN.
///
/// Both sides now NAME Menlo, which ships with every Apple OS and is the one
/// family React Native, Flutter and SwiftUI can all ask for. Android has no
/// Menlo, so [buoyMonoFallback] carries it back to the generic family there —
/// and because both are compile-time constants, a `const TextStyle` stays const:
///
/// ```dart
/// const TextStyle(
///   fontFamily: buoyMonoFont,
///   fontFamilyFallback: buoyMonoFallback,
/// )
/// ```
const String buoyMonoFont = 'Menlo';

/// See [buoyMonoFont] — Android (and anything else without Menlo) lands here.
const List<String> buoyMonoFallback = <String>['monospace'];
