// Buoy console capture — wiring:
// 1. BuoyConsole.runZoned wraps runApp so `print` is captured (a Zone is the
//    only way to intercept print). debugPrint + errors are captured too.
// 2. registerBuoyConsole() registers the tool + sync adapter.
// 3. BuoyDevTools mounts the in-app menu and starts desktop sync.
import 'package:buoy_console/buoy_console.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) registerBuoyConsole();
  BuoyConsole.runZoned(() => runApp(const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => debugPrint('Hello from Buoy console'),
            child: const Text('Log something'),
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
