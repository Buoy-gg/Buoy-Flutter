// Buoy env debugger — wiring:
// 1. registerBuoyEnv(vars, requiredEnvVars) seeds the env source (Flutter has no
//    enumerable process.env) and registers the tool + sync adapter.
// 2. BuoyDevTools mounts the in-app menu and starts desktop sync.
import 'package:buoy_env/buoy_env.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) {
    registerBuoyEnv(
      vars: {
        'API_URL': const String.fromEnvironment('API_URL',
            defaultValue: 'https://api.example.com'),
        'ENVIRONMENT': const String.fromEnvironment('ENVIRONMENT',
            defaultValue: 'development'),
        'DEBUG_MODE': 'true',
      },
      requiredEnvVars: [
        envVar('API_URL').withType('url').build(),
        const RequiredEnvVar.value('ENVIRONMENT', 'production'),
        const RequiredEnvVar.exists('MISSING_TOKEN'),
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
        body: Center(child: Text('Open the Buoy dial → ENV')),
      ),
      builder: (context, child) => BuoyDevTools(
        deviceName: 'My App',
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
