// Buoy impersonate tool — wiring:
// 1. registerBuoyImpersonate(onSearchUsers, ...) attaches your user search +
//    cache-clear callbacks and registers the tool + sync adapter.
// 2. Apply BuoyImpersonate.instance.impersonationHeaders in your HTTP client.
// 3. BuoyDevTools mounts the in-app menu and starts desktop sync.
import 'package:buoy_impersonate/buoy_impersonate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) {
    registerBuoyImpersonate(
      onSearchUsers: (query) async => const [
        ImpersonateUser(
          id: 'admin_1',
          displayName: 'Admin User',
          email: 'admin@example.com',
          metadata: {'role': 'admin'},
        ),
      ],
    );
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const Scaffold(
        body: Center(child: Text('Open the Buoy dial → IMPERSONATE')),
      ),
      builder: (context, child) => BuoyDevTools(
        deviceName: 'My App',
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
