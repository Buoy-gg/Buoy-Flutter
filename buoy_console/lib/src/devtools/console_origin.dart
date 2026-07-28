/// Ports packages/console/src/devtools/origin.ts.
///
/// Attributes a console call to *where it came from* and provides the lnav-style
/// colored connecting-bracket helpers. RN captures three signals (component /
/// function / callSite). Dart has no React owner-stack analog, so `component` is
/// always null here — the shipped grouping dimension is `function`, so it is
/// unused. `functionName` + `callSite` come from parsing the Dart stack trace.
library;

import 'package:flutter/painting.dart';

/// Which origin dimension to group/color rows by.
enum GroupDimension { component, callsite, function, off }

/// Where a log came from.
class LogOrigin {
  const LogOrigin({
    this.component,
    this.functionName,
    this.callSite,
    this.file,
    this.line,
  });

  final String? component;
  final String? functionName;
  final String? callSite;
  final String? file;
  final int? line;

  Map<String, Object?> toJson() => {
        if (component != null) 'component': component,
        if (functionName != null) 'functionName': functionName,
        if (callSite != null) 'callSite': callSite,
        if (file != null) 'file': file,
        if (line != null) 'line': line,
      };
}

class _RawFrame {
  const _RawFrame({this.member, this.file, this.line, this.uri});
  final String? member;
  final String? file;
  final int? line;
  final String? uri;
}

/// Our own capture frames + the Dart print/zone machinery, skipped so the first
/// remaining frame is the real caller (framework internals sit deeper).
bool _isInternalFrame(_RawFrame frame) {
  final uri = frame.uri ?? '';
  if (uri.contains('buoy_console')) return true;
  if (uri.startsWith('dart:')) return true;
  return false;
}

/// Parse a Dart VM stack string into frames.
/// Format: `#1      Some.member (package:app/file.dart:12:5)`.
List<_RawFrame> _parseFrames(String stack) {
  final frames = <_RawFrame>[];
  final re = RegExp(r'^#\d+\s+(.+?)\s+\((.+?):(\d+)(?::(\d+))?\)$');
  for (final raw in stack.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = re.firstMatch(line);
    if (m == null) continue;
    frames.add(_RawFrame(
      member: m.group(1),
      uri: m.group(2),
      file: m.group(2),
      line: int.tryParse(m.group(3) ?? ''),
    ));
  }
  return frames;
}

String? _basename(String? uri) {
  if (uri == null) return null;
  final noQuery = uri.split('?').first;
  final parts = noQuery.split('/');
  return parts.isEmpty ? noQuery : parts.last;
}

String? _cleanMember(String? member) {
  if (member == null) return null;
  final f = member.trim();
  if (f.isEmpty || f == '<anonymous closure>' || f == 'new') return null;
  return f;
}

/// Derive the origin of a log from its captured Dart stack trace.
LogOrigin? parseOrigin(StackTrace? stack) {
  if (stack == null) return null;
  final frames = _parseFrames(stack.toString());
  _RawFrame? appFrame;
  for (final f in frames) {
    if (!_isInternalFrame(f)) {
      appFrame = f;
      break;
    }
  }
  if (appFrame == null) return null;

  final functionName = _cleanMember(appFrame.member);
  final file = _basename(appFrame.file);
  final line = appFrame.line;
  final callSite = (file != null && line != null) ? '$file:$line' : null;

  if (functionName == null && callSite == null) return null;
  return LogOrigin(
    functionName: functionName,
    callSite: callSite,
    file: file,
    line: line,
  );
}

// ─── Grouping by dimension ───────────────────────────────────────────────────

/// Stable key used to group consecutive rows (null = ungrouped).
String? sourceKey(LogOrigin? origin, GroupDimension dim) {
  if (dim == GroupDimension.off) return null;
  if (origin == null) return '—unknown—';
  if (dim == GroupDimension.component) {
    return origin.component ??
        origin.functionName ??
        origin.callSite ??
        '—unknown—';
  }
  if (dim == GroupDimension.function) {
    return origin.functionName ??
        origin.callSite ??
        origin.component ??
        '—anonymous—';
  }
  return origin.callSite ?? origin.functionName ?? '—unknown—';
}

/// Human label shown next to the row.
String sourceLabel(LogOrigin? origin, GroupDimension dim) {
  if (origin == null) return '(unknown)';
  if (dim == GroupDimension.component) {
    if (origin.component != null) return origin.component!;
    if (origin.functionName != null) return 'ƒ ${origin.functionName}';
    return origin.callSite ?? '(unknown)';
  }
  if (dim == GroupDimension.function) {
    if (origin.functionName != null) return origin.functionName!;
    return origin.callSite ?? '(anonymous)';
  }
  if (dim == GroupDimension.callsite) {
    if (origin.functionName != null && origin.callSite != null) {
      return '${origin.functionName} · ${origin.callSite}';
    }
    return origin.callSite ??
        (origin.functionName != null ? 'ƒ ${origin.functionName}' : '(unknown)');
  }
  return '';
}

// ─── Color + bracket ─────────────────────────────────────────────────────────

int _hashString(String s) {
  var h = 0;
  for (var i = 0; i < s.length; i++) {
    h = (h * 31 + s.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  // Emulate JS `| 0` signed 32-bit → abs.
  if (h >= 0x80000000) h -= 0x100000000;
  return h.abs();
}

/// Stable, readable color for a source key (bright enough for a dark surface).
/// Mirrors RN `hsl(hue, 70%, 66%)`.
Color colorForKey(String key) {
  final hue = (_hashString(key) % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.70, 0.66).toColor();
}

enum Bracket { top, mid, bottom, single }

/// lnav gutter glyph: ┌ run-start · │ run-middle · └ run-end · ─ single.
String bracketGlyph(Bracket bracket) {
  switch (bracket) {
    case Bracket.top:
      return '┌';
    case Bracket.bottom:
      return '└';
    case Bracket.single:
      return '─';
    case Bracket.mid:
      return '│';
  }
}
