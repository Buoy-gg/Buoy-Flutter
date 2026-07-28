/// `BuoyRiverpodObserver` — the Riverpod-side capture backend, the analog of
/// Jotai's `watchAtoms()`. A [ProviderObserver] the app adds to its
/// `ProviderScope(observers: [buoyRiverpodObserver])`; it feeds every provider
/// lifecycle event into [riverpodStateStore].
///
/// All capture is gated on [kDebugMode] — in release the overrides are no-ops.
/// Values are serialized ([serializeValue]) at capture time so the store holds
/// JSON-safe structures for the data/diff viewers.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'riverpod_serialize.dart';
import 'riverpod_state_store.dart';

final class BuoyRiverpodObserver extends ProviderObserver {
  const BuoyRiverpodObserver();

  /// Human label for the [context]'s provider. Honest about unnamed providers:
  /// prefers the provider's own `name`, then its family's `name`, else the
  /// runtime type; appends the family `argument` when present (e.g.
  /// `pokemonCard(pikachu)`). Typed via [context] because Riverpod does not
  /// export `ProviderBase` by name.
  static String labelFor(ProviderObserverContext context) {
    final provider = context.provider;
    final name = provider.name ?? provider.from?.name;
    final base = name ?? provider.runtimeType.toString();
    final arg = provider.argument;
    if (arg != null) return '$base($arg)';
    return base;
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    if (!kDebugMode) return;
    riverpodStateStore.recordInitial(labelFor(context), serializeValue(value));
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (!kDebugMode) return;
    riverpodStateStore.recordUpdate(
      labelFor(context),
      serializeValue(previousValue),
      serializeValue(newValue),
    );
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    if (!kDebugMode) return;
    riverpodStateStore.recordDispose(labelFor(context));
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    riverpodStateStore.recordError(labelFor(context), error);
  }
}

/// Shared observer instance the app adds to its `ProviderScope`:
/// `ProviderScope(observers: [buoyRiverpodObserver], child: ...)`.
const buoyRiverpodObserver = BuoyRiverpodObserver();
