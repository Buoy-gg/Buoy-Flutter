/// Ports packages/images/src/capture/actions.ts + overrides.ts.
///
/// The "we own the props" tier: because [BuoyImage] controls every wrapped
/// image's rendered source/style, anything the widget accepts is a simulation —
/// forced errors, forced loading (hang), URL swaps, blanking, a locate-flash
/// border, and app-wide modes (offline / cold / blank images). Plus per-image
/// reload/retry via a nonce the wrapper watches.
///
/// Re-render plumbing mirrors RN: every mutation bumps a per-record or global
/// version; [BuoyImage] rebuilds when its record's version (or the global
/// version) changes.
library;

import 'images_store.dart';
import 'image_record.dart';

/// The override source kinds (RN OverrideSource).
enum OverrideKind { url, error, hang, blank }

class OverrideSource {
  const OverrideSource(this.kind, {this.uri});
  final OverrideKind kind;
  final String? uri;
}

class ImageOverride {
  const ImageOverride({required this.source, required this.label});
  final OverrideSource source;
  final String label;
}

enum NetworkMode { normal, offline, cold }

class ActionResult {
  const ActionResult(this.ok, this.message);
  final bool ok;
  final String message;
  Map<String, Object?> toJson() => {'ok': ok, 'message': message};
}

/// Global-mode snapshot for the adapter/report.
typedef GlobalModes = ({String network, bool blank});

class ImagesActions {
  ImagesActions._();
  static final ImagesActions instance = ImagesActions._();

  final List<void Function()> _actionListeners = [];
  final Map<int, ImageOverride> _overrides = {};
  final Map<int, int> _flashUntil = {};
  final Map<int, int> _recordVersions = {};
  final Map<int, ({int nonce, bool bust})> _reloadRequests = {};
  int _globalVersion = 0;
  int _versionCounter = 0;

  NetworkMode _networkMode = NetworkMode.normal;
  bool _blank = false;

  // ── version bus ────────────────────────────────────────────────────────

  void Function() subscribeActions(void Function() listener) {
    _actionListeners.add(listener);
    return () => _actionListeners.remove(listener);
  }

  void _emit() {
    for (final l in List.of(_actionListeners)) {
      l();
    }
  }

  /// Bump one record's render version (re-renders just that image).
  void touchRecord(int recordId) {
    _recordVersions[recordId] = ++_versionCounter;
    _emit();
  }

  /// Bump the global render version (re-renders every wrapped image).
  void touchGlobal() {
    _globalVersion = ++_versionCounter;
    _emit();
  }

  /// Snapshot for a wrapper's render subscription (max of record + global).
  int getRenderVersion(int? recordId) {
    final record = recordId != null ? (_recordVersions[recordId] ?? 0) : 0;
    return record > _globalVersion ? record : _globalVersion;
  }

  // ── per-record overrides ───────────────────────────────────────────────

  void setOverride(int recordId, ImageOverride override) {
    _overrides[recordId] = override;
    final record = ImagesStore.instance.getRecord(recordId);
    if (record != null) {
      record.overrideLabel = override.label;
      ImagesStore.instance.touch();
    }
    touchRecord(recordId);
  }

  void clearOverride(int recordId) {
    _overrides.remove(recordId);
    final record = ImagesStore.instance.getRecord(recordId);
    if (record != null) {
      record.overrideLabel = null;
      ImagesStore.instance.touch();
    }
    touchRecord(recordId);
  }

  ImageOverride? getOverride(int? recordId) =>
      recordId == null ? null : _overrides[recordId];

  // ── mass actions ───────────────────────────────────────────────────────

  int setOverrideForAllMounted(OverrideSource source, String label) {
    var count = 0;
    for (final record in ImagesStore.instance.getSnapshot()) {
      if (!record.mounted) continue;
      setOverride(record.id, ImageOverride(source: source, label: label));
      count++;
    }
    return count;
  }

  int clearAllOverrides() {
    final ids = _overrides.keys.toList();
    for (final id in ids) {
      clearOverride(id);
    }
    return ids.length;
  }

  int flashAllMounted({int durationMs = 2500}) {
    var count = 0;
    for (final record in ImagesStore.instance.getSnapshot()) {
      if (!record.mounted) continue;
      flashRecord(record.id, durationMs: durationMs);
      count++;
    }
    return count;
  }

  void flashRecord(int recordId, {int durationMs = 2500}) {
    _flashUntil[recordId] =
        DateTime.now().millisecondsSinceEpoch + durationMs;
    touchRecord(recordId);
    Future.delayed(Duration(milliseconds: durationMs + 50), () {
      _flashUntil.remove(recordId);
      touchRecord(recordId);
    });
  }

  bool isFlashing(int recordId) {
    final until = _flashUntil[recordId];
    return until != null && until > DateTime.now().millisecondsSinceEpoch;
  }

  // ── global simulation modes ────────────────────────────────────────────

  void setNetworkMode(NetworkMode mode) {
    _networkMode = mode;
    touchGlobal();
  }

  void setBlankImages(bool enabled) {
    _blank = enabled;
    touchGlobal();
  }

  NetworkMode get networkMode => _networkMode;
  bool get blankImages => _blank;
  GlobalModes get globalModes => (network: _networkMode.name, blank: _blank);

  // ── reload/retry bus (consumed by the wrapper) ─────────────────────────

  int getReloadNonce(int? recordId) =>
      recordId == null ? 0 : (_reloadRequests[recordId]?.nonce ?? 0);

  bool getReloadBust(int? recordId) =>
      recordId == null ? false : (_reloadRequests[recordId]?.bust ?? false);

  void _requestReload(int recordId, bool bust) {
    final prev = _reloadRequests[recordId];
    _reloadRequests[recordId] = (nonce: (prev?.nonce ?? 0) + 1, bust: bust);
    touchRecord(recordId);
  }

  /// Marked consumed once the load settles; the wrapper reverts the bust flag.
  void settleReloadRequest(int recordId) {
    final req = _reloadRequests[recordId];
    if (req != null && req.bust) {
      _reloadRequests[recordId] = (nonce: req.nonce, bust: false);
    }
  }

  void dropActionState(int recordId) {
    _reloadRequests.remove(recordId);
    _overrides.remove(recordId);
    _flashUntil.remove(recordId);
    _recordVersions.remove(recordId);
  }

  // ── high-level dispatchers ─────────────────────────────────────────────

  /// Fresh load attempt for a mounted image (no cache bypass).
  ActionResult retryRecord(ImageRecord record) {
    if (!record.mounted) {
      return const ActionResult(false, 'Instance unmounted — cannot reload');
    }
    _requestReload(record.id, false);
    return const ActionResult(true, 'Remounting image');
  }

  /// Bypass-cache reload: evicts from the Flutter image cache, then remounts.
  ActionResult hardReloadRecord(ImageRecord record) {
    if (!record.mounted) {
      return const ActionResult(false, 'Instance unmounted — cannot reload');
    }
    _requestReload(record.id, true);
    return const ActionResult(true, 'Refetching with cache bypassed');
  }

  ActionResult hardReloadAllMounted() {
    var count = 0;
    for (final record in ImagesStore.instance.getSnapshot()) {
      if (!record.mounted) continue;
      if (hardReloadRecord(record).ok) count++;
    }
    final plural = count == 1 ? '' : 's';
    return ActionResult(count > 0, 'Hard-reloading $count mounted image$plural');
  }
}
