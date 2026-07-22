// Buoy network inspector — two lines of wiring:
// 1. registerBuoyNetwork() installs capture + registers the tool.
// 2. BuoyDevTools mounts the in-app menu and starts desktop sync.
import 'package:buoy_network/buoy_network.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) registerBuoyNetwork();
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
