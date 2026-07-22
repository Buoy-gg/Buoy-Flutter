import 'package:flutter/foundation.dart';

import '../../storage.dart';

/// Global modal behavior flags — the Dart analog of RN's module-global
/// `setExpandableWindowControls()` and the AppHost-injected
/// `enableSharedModalDimensions` prop. Applied from persisted settings on
/// boot and live when toggled in the settings modal.

/// iPad-style expandable window controls (RN default: ON for touch).
final expandableWindowControlsEnabled = ValueNotifier<bool>(true);

/// When ON, every JsModal persists mode/size/position to one shared record.
final sharedModalDimensionsEnabled = ValueNotifier<bool>(false);

/// The shared record's key — devToolsStorageKeys.modal.state().
const sharedModalStateKey = '@react_buoy_modal_state';

void applyGlobalModalSettings(BuoyDevToolsSettings settings) {
  expandableWindowControlsEnabled.value = settings.expandableWindowControls;
  sharedModalDimensionsEnabled.value = settings.enableSharedModalDimensions;
}
