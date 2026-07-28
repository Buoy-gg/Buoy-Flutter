/// Buoy Riverpod state inspector for Flutter.
///
/// The state-inspector tool for Flutter: Riverpod is the closest analog to Jotai
/// (atom-like providers), so this ports the `@buoy-gg/jotai` tool's UI — every
/// change shows `prev → next`, per-provider history, live values, and tree/split
/// diffs — onto a [BuoyRiverpodObserver] backend. A NEW tool id (`riverpod`), not
/// an RN mirror.
///
/// Setup: call [registerBuoyRiverpod] (or use the `buoy` umbrella) and add
/// [buoyRiverpodObserver] to your `ProviderScope`:
///
/// ```dart
/// ProviderScope(
///   observers: const [buoyRiverpodObserver],
///   child: MyApp(),
/// )
/// ```
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

export 'src/register.dart' show registerBuoyRiverpod, riverpodIconColor;
export 'src/riverpod_observer.dart'
    show BuoyRiverpodObserver, buoyRiverpodObserver;
export 'src/riverpod_state_store.dart' show riverpodStateStore;
export 'src/riverpod_sync_adapter.dart' show riverpodSyncAdapter;
export 'src/riverpod_tool/riverpod_modal.dart' show RiverpodModal;
