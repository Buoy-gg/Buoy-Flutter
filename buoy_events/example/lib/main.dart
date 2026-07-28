// Buoy unified events timeline — wiring:
// 1. Register the source tools (network/storage/routes) so their event-source
//    adapters populate buoy_shared_ui's registry.
// 2. registerBuoyEvents() registers the aggregator tool + its sync adapter.
// 3. BuoyDevTools (from the `buoy` umbrella) mounts the in-app menu and starts
//    desktop sync. In a real app you'd use the umbrella, which does all of the
//    above for you.
import 'package:buoy_events/buoy_events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) {
    // In a real app: registerBuoyNetwork(); registerBuoyStorage();
    // registerBuoyRoutes(); (their adapters feed the timeline).
    registerBuoyEvents();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Buoy events timeline example')),
      ),
    );
  }
}
