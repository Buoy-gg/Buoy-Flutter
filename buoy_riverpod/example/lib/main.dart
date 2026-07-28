import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buoy_riverpod/buoy_riverpod.dart';

/// Minimal example: attach the Buoy Riverpod observer to the ProviderScope and
/// register the tool. A named counter provider gives the inspector something to
/// watch (its `prev → next` writes show in the tool).
class CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

final counterProvider =
    NotifierProvider<CounterNotifier, int>(CounterNotifier.new, name: 'counter');

void main() {
  registerBuoyRiverpod();
  runApp(
    const ProviderScope(
      observers: [buoyRiverpodObserver],
      child: _ExampleApp(),
    ),
  );
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Consumer(
        builder: (context, ref, _) {
          final count = ref.watch(counterProvider);
          return Scaffold(
            appBar: AppBar(title: const Text('buoy_riverpod example')),
            body: Center(child: Text('Count: $count')),
            floatingActionButton: FloatingActionButton(
              onPressed: () => ref.read(counterProvider.notifier).increment(),
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    );
  }
}
