/// Buoy storage inspector for Flutter.
///
/// Browse and monitor `shared_preferences` (plus optional secure/MMKV backends)
/// in an in-app panel that streams live to Buoy Desktop. Ports `@buoy-gg/storage`
/// 1:1: register [storageSyncAdapter] via [registerBuoyStorage] and mount
/// [StorageModal] through a [BuoyTool]. Use [BuoyPrefs] for owned writes so they
/// surface instantly in the Events stream.
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

export 'src/register.dart';
export 'src/storage_capture.dart'
    show
        StorageEvent,
        StorageEventStore,
        BuoyPrefs,
        BuoySecureBackend,
        BuoySecureWritableBackend,
        BuoyMmkvBackend,
        MmkvEntry,
        SecureEntry,
        registerBuoySecureBackend,
        registerBuoyMmkvBackend,
        readBuoyMmkvEntries,
        readBuoySecureEntries,
        mmkvSetAction,
        secureBiometricPlaceholder;
export 'src/storage_sync_adapter.dart' show storageSyncAdapter, clearAppStorage;
export 'src/storage_tool/storage_modal.dart' show StorageModal;
