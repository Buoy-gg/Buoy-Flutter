import 'dart:async';

import 'package:flutter/foundation.dart';

/// Port of the RN TickProvider/useTickEveryMinute — one shared 60s tick that
/// keeps relative timestamps fresh while the modal is open. Rows listen to
/// this notifier (only the timestamp Text rebuilds, per the RN
/// BottomRightTime decomposition).
class MinuteTicker {
  MinuteTicker._();
  static final MinuteTicker instance = MinuteTicker._();

  final ValueNotifier<int> tick = ValueNotifier(0);
  Timer? _timer;
  int _refCount = 0;

  /// Start ticking while at least one consumer is active (the modal).
  void retain() {
    _refCount++;
    _timer ??= Timer.periodic(const Duration(seconds: 60), (_) {
      tick.value++;
    });
  }

  void release() {
    _refCount--;
    if (_refCount <= 0) {
      _refCount = 0;
      _timer?.cancel();
      _timer = null;
    }
  }
}
