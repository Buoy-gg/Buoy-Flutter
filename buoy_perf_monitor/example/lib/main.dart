// Buoy performance monitor — one line of wiring:
// registerBuoyPerfMonitor() installs the sampler + registers the tool and its
// HUD overlay; BuoyDevTools mounts the in-app menu and starts desktop sync.
import 'package:buoy_perf_monitor/buoy_perf_monitor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) registerBuoyPerfMonitor();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const Scaffold(body: Center(child: Text('Your app'))),
      builder: (context, child) => BuoyDevTools(
        deviceName: 'My App',
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
