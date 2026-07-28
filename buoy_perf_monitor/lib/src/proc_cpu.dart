/// Pure-Dart Android process-CPU reader (`/proc/self/stat`).
///
/// No native code — `dart:io` `File` reads the kernel's per-process stat line.
/// Fields 14 (utime) + 15 (stime) are the process's user + system jiffies; a
/// delta over the sample interval ÷ clock-ticks ÷ cores gives process CPU%.
/// iOS has no `/proc`, so this is Android-only (the controller reports 0 on
/// iOS — an honest, in-schema value all consumers already tolerate).
///
/// The parser is factored out as a pure function so it can be unit-tested
/// against a fixture stat string without a device.
library;

/// Parses `/proc/self/stat` and returns `utime + stime` in jiffies, or null if
/// the line is malformed.
///
/// The line format is `pid (comm) state ppid ...`. `comm` can contain spaces
/// and parentheses, so we split on the LAST `')'` and index into the
/// remaining space-separated fields. After `comm`, field indices restart at
/// `state` (field 3); utime = field 14, stime = field 15 → offsets 11 and 12
/// into the post-`comm` token list (0-based: state=0, ppid=1, …, utime=11,
/// stime=12).
int? parseProcSelfStatJiffies(String stat) {
  final rparen = stat.lastIndexOf(')');
  if (rparen < 0 || rparen + 2 > stat.length) return null;
  final rest = stat.substring(rparen + 1).trim();
  if (rest.isEmpty) return null;
  final fields = rest.split(RegExp(r'\s+'));
  // Need utime (index 11) and stime (index 12) after `comm`.
  if (fields.length < 13) return null;
  final utime = int.tryParse(fields[11]);
  final stime = int.tryParse(fields[12]);
  if (utime == null || stime == null) return null;
  return utime + stime;
}

/// Computes process CPU% from a jiffies delta over a wall-clock interval.
///
/// [deltaJiffies] = jiffies consumed since last read; [intervalMs] = elapsed
/// wall time; [clockTicksPerSec] = `_SC_CLK_TCK` (100 on Android); [cores] =
/// online CPU count. Result is clamped to `[0, 100]`. Returns 0 for a
/// non-positive interval (first read / clock skew).
double procCpuPercent({
  required int deltaJiffies,
  required int intervalMs,
  required int clockTicksPerSec,
  required int cores,
}) {
  if (intervalMs <= 0 || clockTicksPerSec <= 0 || cores <= 0) return 0;
  final intervalSec = intervalMs / 1000.0;
  final cpuSeconds = deltaJiffies / clockTicksPerSec;
  final pct = (cpuSeconds / (intervalSec * cores)) * 100.0;
  if (pct.isNaN || pct < 0) return 0;
  return pct > 100 ? 100 : pct;
}
