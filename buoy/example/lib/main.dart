// Minimal Buoy network-inspector wiring: capture all HTTP traffic, stream it
// to Buoy Desktop, and mount the in-app panel behind a floating bubble.
import 'package:buoy/buoy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) {
    // 1. Capture every dart:io HTTP request (package:http, dio, Image.network).
    BuoyHttpOverrides.install();

    // 2. Stream captured traffic to the Buoy Desktop dashboard.
    BuoySyncClient(
      deviceName: 'My App',
      deviceId: 'my-app',
      platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      tools: {'network': networkSyncAdapter},
    ).connect();

    // 3. Keep capture on for the in-app panel even when desktop isn't watching.
    NetworkEventStore.instance.subscribe(() {});
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const Scaffold(body: Center(child: Text('Your app'))),
      // 4. In-app panel: register the tool with the floating devtools shell.
      builder: (context, child) => BuoyDevTools(
        tools: [
          BuoyTool(
            id: 'network',
            name: 'Network',
            description: 'Inspect HTTP requests',
            color: const Color(0xFF38BDF8),
            icon: Icons.swap_vert,
            modalBuilder: (context, storage, onClose, onMinimize) =>
                NetworkModal(
              storage: storage,
              onClose: onClose,
              onMinimize: onMinimize,
            ),
          ),
        ],
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
