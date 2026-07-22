import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';

import 'network_capture.dart';
import 'network_tool/network_modal.dart';

bool _registered = false;

/// One-call setup for the network tool: installs the HTTP capture hook,
/// keeps the in-app store live, and registers the tool + sync adapter with
/// [Buoy]. Idempotent. Called automatically by the `buoy` umbrella widget;
/// apps depending on `buoy_network` directly call it once before `runApp`
/// (or let `BuoyDevTools` mount trigger it via the umbrella).
void registerBuoyNetwork({bool installHttpOverrides = true}) {
  if (_registered) return;
  _registered = true;

  if (installHttpOverrides) BuoyHttpOverrides.install();

  // Keep capture on for the in-app panel even when no desktop is watching.
  NetworkEventStore.instance.subscribe(() {});

  Buoy.registerTool(
    BuoyTool(
      id: 'network',
      name: 'Network',
      description: 'Inspect HTTP requests',
      color: const Color(0xFF38BDF8),
      icon: Icons.swap_vert,
      modalBuilder: (context, storage, onClose, onMinimize) => NetworkModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: networkSyncAdapter,
  );
}
