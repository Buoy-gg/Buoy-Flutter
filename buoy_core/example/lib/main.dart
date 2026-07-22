// buoy_core: the floating devtools shell + a custom tool synced to the
// Buoy Desktop dashboard. Register tools with Buoy; BuoyDevTools starts the
// desktop connection automatically on mount.
import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

int _count = 0;
final _listeners = <void Function()>[];

void main() {
  if (kDebugMode) {
    // Any object exposing getSnapshot/subscribe/actions can sync to desktop.
    Buoy.registerTool(
      BuoyTool(
        id: 'counter',
        name: 'Counter',
        color: const Color(0xFF34D399),
        icon: Icons.plus_one,
        onPressed: (context) {
          _count++;
          for (final l in List.of(_listeners)) {
            l();
          }
        },
      ),
      adapter: ToolSyncAdapter(
        version: 1,
        getSnapshot: () => {'count': _count},
        subscribe: (onChange) {
          _listeners.add(onChange);
          return () => _listeners.remove(onChange);
        },
        actions: {'reset': (_) => _count = 0},
      ),
    );
  }
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
