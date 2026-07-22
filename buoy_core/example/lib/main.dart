// Minimal buoy_core wiring: the floating devtools shell plus a custom tool,
// synced live to the Buoy Desktop dashboard.
import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Any object exposing getSnapshot/subscribe/actions can sync to the desktop.
final counterAdapter = ToolSyncAdapter(
  version: 1,
  getSnapshot: () => {'count': _count},
  subscribe: (onChange) {
    _listeners.add(onChange);
    return () => _listeners.remove(onChange);
  },
  actions: {'reset': (_) => _count = 0},
);

int _count = 0;
final _listeners = <void Function()>[];

void main() {
  if (kDebugMode) {
    BuoySyncClient(
      deviceName: 'My App',
      deviceId: 'my-app',
      platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      tools: {'counter': counterAdapter},
    ).connect();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const Scaffold(body: Center(child: Text('Your app'))),
      // The floating bubble + dial shell; tools open as in-app modals.
      builder: (context, child) => BuoyDevTools(
        tools: const [],
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
