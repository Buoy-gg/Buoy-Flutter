/// Ports packages/external-sync/src/crashFlush.ts.
///
/// A "push this tool's snapshot RIGHT NOW" seam.
///
/// Why it exists: the device sync bridge pushes snapshots on a 200ms throttle,
/// but the moment worth capturing most — a crash — is the moment the app stops
/// running that throttle. The pending snapshot never goes out, so the crash
/// never reaches the dashboard or the MCP server, and the app just looks like
/// it stopped answering.
///
/// A tool that knows it is about to lose the app (see buoy_console's error
/// hooks) calls [flushToolSyncNow] synchronously from its error handler, while
/// the socket is still attached, and the snapshot goes out immediately.
///
/// RN deviation: the RN version hangs this registry off `globalThis` because
/// its tools deliberately have no import edge to `@buoy-gg/external-sync`
/// (their adapters are duck-typed and found by auto-discovery). Flutter tool
/// packages already depend on `buoy_core` for [ToolSyncAdapter], so a plain
/// library-level registry does the same job without the global.
library;

/// Emit `toolId`'s current snapshot now, bypassing the throttle.
typedef ToolFlusher = void Function(String toolId);

/// A SET, not a single slot: a second bridge can be attached (or an attach can
/// run before the previous one's teardown) so two are briefly live at once. A
/// last-writer-wins slot would let the second registration silently disable the
/// first's crash flush — failing in exactly the moment it is the only thing
/// that gets the crash out, with no error and no log.
final Set<ToolFlusher> _flushers = <ToolFlusher>{};

/// Install a bridge's flusher. Called by [BuoySyncClient] on connect.
void registerToolFlusher(ToolFlusher flush) => _flushers.add(flush);

/// Remove one bridge's flusher, leaving any others intact.
void unregisterToolFlusher(ToolFlusher flush) => _flushers.remove(flush);

/// Push a tool's snapshot immediately through every attached sync bridge.
/// Never throws — a crash path must not crash.
void flushToolSyncNow(String toolId) {
  try {
    for (final flush in List<ToolFlusher>.of(_flushers)) {
      try {
        flush(toolId);
      } catch (_) {
        // One bad bridge must not stop the others.
      }
    }
  } catch (_) {
    // Best-effort by design.
  }
}
