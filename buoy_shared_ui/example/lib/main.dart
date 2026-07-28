// buoy_shared_ui is a building block for Buoy's Flutter tools, not an app you
// run directly. This example just renders a couple of the shared widgets so the
// package has a runnable entry point.
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: BuoyColors.base,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PillBadge(color: BuoyColors.primary, child: const Text('SHARED UI')),
              const SizedBox(height: 16),
              const StatusBadge(status: 'success'),
            ],
          ),
        ),
      ),
    );
  }
}
