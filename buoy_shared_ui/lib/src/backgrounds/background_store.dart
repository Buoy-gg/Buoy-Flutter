/// Ports packages/shared/src/ui/backgrounds/backgroundStore.ts — the
/// persisted background selection, shared by every tool.
///
/// A singleton rather than an inherited widget so a tool anywhere in the tree
/// reads the same choice without a provider having to wrap it: listen /
/// notify, best-effort persistence, a dirty flag so a slow initial read can't
/// clobber a choice the user already made.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/foundation.dart';

import '../storage/dev_tools_storage_keys.dart';
import 'registry.dart';
import 'types.dart';

/// v3: bumped on RN when the default became "off" (backgrounds are opt-in).
/// Same key as RN so the two builds' persistence stays interchangeable.
const String backgroundStorageKey = '${DevToolsStorageKeys.base}_tool_background_v3';

class BackgroundStore extends ChangeNotifier {
  BackgroundStore._();

  static final BackgroundStore instance = BackgroundStore._();

  BackgroundId _id = defaultBackground;

  /// Motion is deliberately NOT persisted: every session starts animated.
  /// `setMotion` survives as a session-only seam (a tool forcing stillness).
  bool _motion = true;
  Future<void>? _load;
  bool _dirty = false;
  final BuoyStorage _storage = BuoyStorage();

  BackgroundId get id => _id;
  bool get motion => _motion;
  int get index => presetIndex(_id);
  int get count => backgroundPresets.length;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _load ??= _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      final raw = await _storage.loadJson(backgroundStorageKey);
      if (raw == null || _dirty) return;
      final stored = raw['id'];
      // The standalone Meteors preset was folded into Deep Field on RN —
      // re-home anyone still persisted on it rather than dropping them.
      final name = stored == 'meteors' ? 'deepfield' : stored;
      final id = BackgroundId.values.cast<BackgroundId?>().firstWhere(
            (v) => v!.name == name,
            orElse: () => null,
          );
      if (id != null && id != _id) {
        _id = id;
        notifyListeners();
      }
    } catch (_) {
      // A missing or corrupt entry just means "use the default".
    }
  }

  /// Test seam: forget the dirty flag and re-read the persisted pick (the
  /// store is a process singleton, and the e2e harness resets preferences
  /// between tests).
  @visibleForTesting
  Future<void> reload() async {
    _dirty = false;
    _load = null;
    await (_load = _loadOnce());
  }

  void _persist() {
    _dirty = true;
    _storage.saveJson(backgroundStorageKey, {'id': _id.name}).catchError((_) {});
  }

  void setId(BackgroundId id) {
    if (_id == id) return;
    _id = id;
    _persist();
    notifyListeners();
  }

  /// Step through the catalogue; `delta` is +1 (next) or -1 (previous).
  void step(int delta) => setId(presetAt(index + delta).id);
  void next() => step(1);
  void previous() => step(-1);

  void setMotion(bool motion) {
    if (_motion == motion) return;
    _motion = motion;
    notifyListeners();
  }
}
