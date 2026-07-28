// Buoy image-overlay tool — wiring:
// 1. registerBuoyImageOverlay() registers the tool + mounts the overlay layer.
// 2. (Optional) wrap widgets in BuoyImageTarget so Component Match can find them.
// 3. BuoyDevTools mounts the in-app menu; open the dial → IMG.
import 'package:buoy_image_overlay/buoy_image_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) registerBuoyImageOverlay();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: BuoyImageTarget(
            label: 'Greeting',
            child: const Text('Open the Buoy dial → IMG'),
          ),
        ),
      ),
      builder: (context, child) => BuoyDevTools(
        deviceName: 'My App',
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
