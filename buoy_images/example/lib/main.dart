// Buoy Images tool — two lines of wiring:
// 1. registerBuoyImages() registers the tool + sync adapter.
// 2. BuoyDevTools mounts the in-app menu and starts desktop sync.
// Then use BuoyImage in place of Image / CachedNetworkImage to capture loads.
import 'package:buoy_images/buoy_images.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  if (kDebugMode) registerBuoyImages();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: BuoyImage(
            provider: const NetworkImage('https://picsum.photos/400'),
            width: 120,
            height: 120,
            fit: BoxFit.cover,
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
