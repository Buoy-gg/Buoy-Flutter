/// Ports packages/shared/src/dataViewer/lineDiff.ts — line-by-line diff
/// computation for the [SplitDiffViewer]. Pure logic (no Flutter imports) so it
/// can be unit-tested against the RN algorithm's expected output.
///
/// Mirrors the RN implementation exactly: 2-space pretty-printed JSON lines
/// (empty lines dropped except first/last), Myers' O(ND) line matcher over keys
/// that ignore the trailing comma, a 3-char "starts similarly" modification
/// heuristic applied only within an unmatched hunk, and word/char-level diff via
/// a small look-ahead LCS (window 5).
library;

import 'dart:convert';
import 'dart:typed_data';

/// RN `DiffType` (string enum). `unchanged` is the DEFAULT value.
enum DiffType { unchanged, added, removed, modified }

/// Marks one side of a diff as "this value did not exist" (RN `ABSENT_VALUE`).
///
/// Deliberately distinct from `null`, `[]`, `{}` and `''` — those are real
/// stored values and diff normally. An absent side contributes zero lines, so a
/// key that was just created reads as purely added rather than as an edit of
/// the literal text `null`.
class AbsentDiffValue {
  const AbsentDiffValue();

  @override
  String toString() => '<absent>';
}

/// The singleton absent marker. Pass this as `oldValue`/`newValue`.
const AbsentDiffValue absentValue = AbsentDiffValue();

/// True when a diff side represents a value that did not exist.
bool isAbsent(Object? value) => value is AbsentDiffValue;

/// A word/char run within a modified line.
class WordDiff {
  const WordDiff({required this.value, required this.type});
  final String value;
  final DiffType type;
}

/// One row of the computed line diff (RN `LineDiffInfo`). [leftContent]/
/// [rightContent] are either a `String` or a `List<WordDiff>` (word-level).
class LineDiffInfo {
  const LineDiffInfo({
    this.leftLineNumber,
    this.rightLineNumber,
    required this.type,
    this.leftContent,
    this.rightContent,
    this.leftRaw,
    this.rightRaw,
  });

  final int? leftLineNumber;
  final int? rightLineNumber;
  final DiffType type;

  /// `String` or `List<WordDiff>`.
  final Object? leftContent;

  /// `String` or `List<WordDiff>`.
  final Object? rightContent;
  final String? leftRaw;
  final String? rightRaw;
}

/// RN `compareMethod` values.
enum DiffCompareMethod { chars, words, lines, trimmedLines }

/// RN `DiffComputeOptions`.
class DiffComputeOptions {
  const DiffComputeOptions({
    this.compareMethod = DiffCompareMethod.words,
    this.disableWordDiff = false,
    this.showDiffOnly = false,
    this.contextLines = 3,
    this.ignoreTrailingComma = true,
  });

  final DiffCompareMethod compareMethod;
  final bool disableWordDiff;
  final bool showDiffOnly;
  final int contextLines;

  /// Ignore the trailing comma when matching lines (default true).
  ///
  /// Appending or inserting into an array/object rewrites the line that used to
  /// be last (`"gengar"` -> `"gengar",`). That is JSON punctuation, not a data
  /// change, so comparing without it stops a one-item push from reporting the
  /// previous last item as modified. Display still uses the raw JSON.
  final bool ignoreTrailingComma;
}

final RegExp _wordSplit = RegExp(r'\S+|\s+');

/// Word/char-level diff within a pair of lines (RN `computeDiffByMethod`).
({List<WordDiff> left, List<WordDiff> right}) _computeDiffByMethod(
  String oldStr,
  String newStr,
  DiffCompareMethod method,
) {
  List<String> oldParts;
  List<String> newParts;

  switch (method) {
    case DiffCompareMethod.chars:
      oldParts = oldStr.split('');
      newParts = newStr.split('');
      break;
    case DiffCompareMethod.words:
      oldParts = _wordSplit.allMatches(oldStr).map((m) => m[0]!).toList();
      newParts = _wordSplit.allMatches(newStr).map((m) => m[0]!).toList();
      break;
    case DiffCompareMethod.trimmedLines:
      oldParts = _wordSplit.allMatches(oldStr.trim()).map((m) => m[0]!).toList();
      newParts = _wordSplit.allMatches(newStr.trim()).map((m) => m[0]!).toList();
      break;
    case DiffCompareMethod.lines:
      return (
        left: [WordDiff(value: oldStr, type: DiffType.removed)],
        right: [WordDiff(value: newStr, type: DiffType.added)],
      );
  }

  final left = <WordDiff>[];
  final right = <WordDiff>[];
  var i = 0;
  var j = 0;

  while (i < oldParts.length && j < newParts.length) {
    if (oldParts[i] == newParts[j]) {
      left.add(WordDiff(value: oldParts[i], type: DiffType.unchanged));
      right.add(WordDiff(value: newParts[j], type: DiffType.unchanged));
      i++;
      j++;
    } else {
      var foundMatch = false;

      // Look ahead for newParts[j] in upcoming oldParts (window 5).
      for (var k = i + 1; k < _min(i + 5, oldParts.length); k++) {
        if (oldParts[k] == newParts[j]) {
          for (var m = i; m < k; m++) {
            left.add(WordDiff(value: oldParts[m], type: DiffType.removed));
          }
          i = k;
          foundMatch = true;
          break;
        }
      }

      if (!foundMatch) {
        for (var k = j + 1; k < _min(j + 5, newParts.length); k++) {
          if (newParts[k] == oldParts[i]) {
            for (var m = j; m < k; m++) {
              right.add(WordDiff(value: newParts[m], type: DiffType.added));
            }
            j = k;
            foundMatch = true;
            break;
          }
        }
      }

      if (!foundMatch) {
        left.add(WordDiff(value: oldParts[i], type: DiffType.removed));
        right.add(WordDiff(value: newParts[j], type: DiffType.added));
        i++;
        j++;
      }
    }
  }

  while (i < oldParts.length) {
    left.add(WordDiff(value: oldParts[i], type: DiffType.removed));
    i++;
  }
  while (j < newParts.length) {
    right.add(WordDiff(value: newParts[j], type: DiffType.added));
    j++;
  }

  return (left: left, right: right);
}

/// RN `objectToLines`: 2-space pretty JSON split into lines, empty lines dropped
/// except the first/last.
List<String> _objectToLines(Object? obj) {
  // A value that never existed has no text at all — not the word "null".
  if (isAbsent(obj)) return <String>[];
  if (obj == null) return ['null'];
  try {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(obj);
    final lines = jsonStr.split('\n');
    final filtered = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed != '') {
        filtered.add(line);
      } else if (i == 0 || i == lines.length - 1) {
        filtered.add(line);
      }
    }
    return filtered;
  } catch (_) {
    return ['$obj'];
  }
}

/// RN `filterDiffWithContext`: keep only changed lines ± [contextLines],
/// merging adjacent/overlapping ranges.
List<LineDiffInfo> _filterDiffWithContext(
  List<LineDiffInfo> diffs,
  int contextLines,
) {
  if (contextLines < 0) return diffs;

  final result = <LineDiffInfo>[];
  final changedIndices = <int>[];
  for (var idx = 0; idx < diffs.length; idx++) {
    if (diffs[idx].type != DiffType.unchanged) changedIndices.add(idx);
  }
  if (changedIndices.isEmpty) return [];

  final ranges = <List<int>>[];
  var currentStart = _max(0, changedIndices[0] - contextLines);
  var currentEnd = _min(diffs.length - 1, changedIndices[0] + contextLines);

  for (var i = 1; i < changedIndices.length; i++) {
    final idx = changedIndices[i];
    final rangeStart = _max(0, idx - contextLines);
    final rangeEnd = _min(diffs.length - 1, idx + contextLines);
    if (rangeStart <= currentEnd + 1) {
      currentEnd = _max(currentEnd, rangeEnd);
    } else {
      ranges.add([currentStart, currentEnd]);
      currentStart = rangeStart;
      currentEnd = rangeEnd;
    }
  }
  ranges.add([currentStart, currentEnd]);

  for (final range in ranges) {
    for (var i = range[0]; i <= range[1]; i++) {
      result.add(diffs[i]);
    }
  }
  return result;
}

final RegExp _trailingComma = RegExp(r',\s*$');

/// RN `normalizeCompareKey`: the key used for matching. Display always uses the
/// raw JSON; only matching sees this.
String _normalizeCompareKey(
  String line,
  DiffCompareMethod compareMethod,
  bool ignoreTrailingComma,
) {
  final base =
      compareMethod == DiffCompareMethod.trimmedLines ? line.trim() : line;
  return ignoreTrailingComma ? base.replaceFirst(_trailingComma, '') : base;
}

/// RN `looksLikeModification`: the original 3-char "starts alike" heuristic.
/// Only applied inside a hunk the line matcher already proved unmatched, so it
/// can no longer pair lines that merely shifted position.
bool _looksLikeModification(String oldLine, String newLine) {
  final oldTrimmed = oldLine.trim();
  final newTrimmed = newLine.trim();
  return oldTrimmed.isNotEmpty &&
      newTrimmed.isNotEmpty &&
      (oldTrimmed.startsWith(_take(newTrimmed, 3)) ||
          newTrimmed.startsWith(_take(oldTrimmed, 3)));
}

enum _OpKind { eq, del, ins }

/// One edit-script entry. [i] indexes the old lines, [j] the new ones; the
/// unused side is -1.
class _LineOp {
  const _LineOp(this.kind, this.i, this.j);
  final _OpKind kind;
  final int i;
  final int j;
}

/// Myers is O(ND) in the number of edits, so near-identical values (the common
/// case — one array push) are close to free and only wildly different values get
/// expensive. Past these bounds we fall back to the pairwise walk.
const int _myersMaxTotalLines = 8000;
const int _myersMaxEditDistance = 1024;

/// Myers' O(ND) diff ("An O(ND) Difference Algorithm and Its Variations", 1986)
/// over line keys — the same algorithm git and `diff` use.
///
/// Returns null when the input is too large or too dissimilar to be worth it,
/// which tells the caller to use the fallback walk.
List<_LineOp>? _myersLineOps(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;
  if (n + m > _myersMaxTotalLines) return null;
  if (n == 0 && m == 0) return <_LineOp>[];

  final max = n + m;
  // +1 of padding on each side so the k-1 / k+1 probes at the frontier stay in
  // bounds without clamping (clamping would corrupt the index arithmetic).
  final offset = max + 1;
  final v = Int32List(2 * max + 3);
  final maxD = _min(max, _myersMaxEditDistance);

  // Frontier snapshot per depth. Only k in [-(d+1), d+1] is ever read back, so
  // each snapshot is O(d) and the whole trace is O(D^2) — not O(D * max).
  final trace = <Int32List>[];

  for (var d = 0; d <= maxD; d++) {
    trace.add(Int32List.fromList(v.sublist(offset - (d + 1), offset + d + 2)));

    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) {
        x = v[k + 1 + offset];
      } else {
        x = v[k - 1 + offset] + 1;
      }
      var y = x - k;

      // Follow the diagonal as far as the lines keep matching.
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }

      v[k + offset] = x;

      if (x >= n && y >= m) {
        return _backtrackOps(trace, n, m);
      }
    }
  }

  return null;
}

/// RN `backtrackOps`: walk the recorded frontiers backwards to recover the
/// edit script.
List<_LineOp> _backtrackOps(List<Int32List> trace, int n, int m) {
  final ops = <_LineOp>[];
  var x = n;
  var y = m;

  for (var d = trace.length - 1; d >= 0; d--) {
    final snapshot = trace[d];
    // Snapshot d covers k in [-(d+1), d+1], so k=0 sits at index d+1.
    final base = d + 1;
    final k = x - y;

    int prevK;
    if (k == -d ||
        (k != d && snapshot[k - 1 + base] < snapshot[k + 1 + base])) {
      prevK = k + 1;
    } else {
      prevK = k - 1;
    }

    final prevX = snapshot[prevK + base];
    final prevY = prevX - prevK;

    while (x > prevX && y > prevY) {
      ops.add(_LineOp(_OpKind.eq, x - 1, y - 1));
      x--;
      y--;
    }

    if (d > 0) {
      if (x == prevX) {
        ops.add(_LineOp(_OpKind.ins, -1, y - 1));
      } else {
        ops.add(_LineOp(_OpKind.del, x - 1, -1));
      }
    }

    x = prevX;
    y = prevY;
  }

  return ops.reversed.toList();
}

/// RN `emitHunk`: one hunk of unmatched lines. Removals and additions are paired
/// off in order and become [DiffType.modified] rows when they look like an edit
/// of the same line; everything left over stays one-sided.
void _emitHunk(
  List<LineDiffInfo> result,
  List<int> dels,
  List<int> inss,
  List<String> oldLines,
  List<String> newLines,
  DiffCompareMethod compareMethod,
  bool disableWordDiff,
) {
  final pairs = _min(dels.length, inss.length);

  for (var k = 0; k < pairs; k++) {
    final i = dels[k];
    final j = inss[k];

    if (!_looksLikeModification(oldLines[i], newLines[j])) {
      result.add(LineDiffInfo(
        leftLineNumber: i + 1,
        type: DiffType.removed,
        leftContent: oldLines[i],
        leftRaw: oldLines[i],
      ));
      result.add(LineDiffInfo(
        rightLineNumber: j + 1,
        type: DiffType.added,
        rightContent: newLines[j],
        rightRaw: newLines[j],
      ));
      continue;
    }

    if (!disableWordDiff && compareMethod != DiffCompareMethod.lines) {
      final wordDiff =
          _computeDiffByMethod(oldLines[i], newLines[j], compareMethod);
      result.add(LineDiffInfo(
        leftLineNumber: i + 1,
        rightLineNumber: j + 1,
        type: DiffType.modified,
        leftContent: wordDiff.left,
        rightContent: wordDiff.right,
        leftRaw: oldLines[i],
        rightRaw: newLines[j],
      ));
    } else {
      result.add(LineDiffInfo(
        leftLineNumber: i + 1,
        rightLineNumber: j + 1,
        type: DiffType.modified,
        leftContent: oldLines[i],
        rightContent: newLines[j],
        leftRaw: oldLines[i],
        rightRaw: newLines[j],
      ));
    }
  }

  for (var k = pairs; k < dels.length; k++) {
    final i = dels[k];
    result.add(LineDiffInfo(
      leftLineNumber: i + 1,
      type: DiffType.removed,
      leftContent: oldLines[i],
      leftRaw: oldLines[i],
    ));
  }

  for (var k = pairs; k < inss.length; k++) {
    final j = inss[k];
    result.add(LineDiffInfo(
      rightLineNumber: j + 1,
      type: DiffType.added,
      rightContent: newLines[j],
      rightRaw: newLines[j],
    ));
  }
}

/// RN `buildRowsFromOps`: turn the edit script into rows, grouping each run of
/// unmatched lines into a hunk so modification pairing stays local.
List<LineDiffInfo> _buildRowsFromOps(
  List<_LineOp> ops,
  List<String> oldLines,
  List<String> newLines,
  DiffCompareMethod compareMethod,
  bool disableWordDiff,
) {
  final result = <LineDiffInfo>[];
  var idx = 0;

  while (idx < ops.length) {
    final op = ops[idx];

    if (op.kind == _OpKind.eq) {
      result.add(LineDiffInfo(
        leftLineNumber: op.i + 1,
        rightLineNumber: op.j + 1,
        type: DiffType.unchanged,
        leftContent: oldLines[op.i],
        rightContent: newLines[op.j],
        leftRaw: oldLines[op.i],
        rightRaw: newLines[op.j],
      ));
      idx++;
      continue;
    }

    final dels = <int>[];
    final inss = <int>[];
    while (idx < ops.length && ops[idx].kind != _OpKind.eq) {
      final hunkOp = ops[idx];
      if (hunkOp.kind == _OpKind.del) {
        dels.add(hunkOp.i);
      } else if (hunkOp.kind == _OpKind.ins) {
        inss.add(hunkOp.j);
      }
      idx++;
    }

    _emitHunk(
      result,
      dels,
      inss,
      oldLines,
      newLines,
      compareMethod,
      disableWordDiff,
    );
  }

  return result;
}

/// RN `pairwiseLineWalk`: fallback used only when the input is past the Myers
/// bounds. Advances both sides in lockstep, so a shifted line reads as changed —
/// the reason it isn't the primary path.
List<LineDiffInfo> _pairwiseLineWalk(
  List<String> oldLines,
  List<String> newLines,
  List<String> oldKeys,
  List<String> newKeys,
  DiffCompareMethod compareMethod,
  bool disableWordDiff,
) {
  final result = <LineDiffInfo>[];
  var i = 0;
  var j = 0;

  while (i < oldLines.length || j < newLines.length) {
    if (i >= oldLines.length) {
      result.add(LineDiffInfo(
        rightLineNumber: j + 1,
        type: DiffType.added,
        rightContent: newLines[j],
        rightRaw: newLines[j],
      ));
      j++;
    } else if (j >= newLines.length) {
      result.add(LineDiffInfo(
        leftLineNumber: i + 1,
        type: DiffType.removed,
        leftContent: oldLines[i],
        leftRaw: oldLines[i],
      ));
      i++;
    } else if (oldKeys[i] == newKeys[j]) {
      result.add(LineDiffInfo(
        leftLineNumber: i + 1,
        rightLineNumber: j + 1,
        type: DiffType.unchanged,
        leftContent: oldLines[i],
        rightContent: newLines[j],
        leftRaw: oldLines[i],
        rightRaw: newLines[j],
      ));
      i++;
      j++;
    } else {
      _emitHunk(
        result,
        [i],
        [j],
        oldLines,
        newLines,
        compareMethod,
        disableWordDiff,
      );
      i++;
      j++;
    }
  }

  return result;
}

/// Compute a line-by-line diff between two values (RN `computeLineDiff`).
///
/// Lines are matched with Myers' O(ND) algorithm over normalized keys, so an
/// insert or append shows up as the one line that actually arrived instead of
/// every line after it shifting into a change.
List<LineDiffInfo> computeLineDiff(
  Object? oldValue,
  Object? newValue, [
  DiffComputeOptions options = const DiffComputeOptions(),
]) {
  final compareMethod = options.compareMethod;
  final disableWordDiff = options.disableWordDiff;
  final showDiffOnly = options.showDiffOnly;
  final contextLines = options.contextLines;
  final ignoreTrailingComma = options.ignoreTrailingComma;

  final oldLines = _objectToLines(oldValue);
  final newLines = _objectToLines(newValue);

  final oldKeys = oldLines
      .map((line) =>
          _normalizeCompareKey(line, compareMethod, ignoreTrailingComma))
      .toList();
  final newKeys = newLines
      .map((line) =>
          _normalizeCompareKey(line, compareMethod, ignoreTrailingComma))
      .toList();

  final ops = _myersLineOps(oldKeys, newKeys);
  final result = ops != null
      ? _buildRowsFromOps(
          ops, oldLines, newLines, compareMethod, disableWordDiff)
      : _pairwiseLineWalk(oldLines, newLines, oldKeys, newKeys, compareMethod,
          disableWordDiff);

  if (showDiffOnly) return _filterDiffWithContext(result, contextLines);
  return result;
}

// JS `substring(0, n)` is clamp-safe; Dart `substring` throws past the end.
String _take(String s, int n) => s.length <= n ? s : s.substring(0, n);

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;
