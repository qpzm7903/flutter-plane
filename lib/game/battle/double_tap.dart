import 'dart:ui';

import 'battle_tuning.dart';

class DoubleTapDetector {
  Duration? _last;
  bool onUp({
    required Duration downAt,
    required Duration upAt,
    required Offset downPos,
    required Offset upPos,
  }) {
    final duration = (upAt - downAt).inMicroseconds / 1e6;
    if (duration < 0 ||
        duration >= kTapMaxDuration ||
        (upPos - downPos).distance >= kTapMaxTravel) {
      _last = null;
      return false;
    }
    final last = _last;
    _last = upAt;
    if (last != null &&
        downAt >= last &&
        (downAt - last).inMicroseconds / 1e6 < kDoubleTapWindow) {
      _last = null;
      return true;
    }
    return false;
  }
}
