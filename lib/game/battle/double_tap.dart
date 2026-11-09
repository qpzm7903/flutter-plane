import 'dart:ui';

import 'battle_tuning.dart';

enum TapResult { none, first, double }

class DoubleTapDetector {
  Duration? _last;
  Offset? _lastUpPos;
  TapResult onUp({
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
      return TapResult.none;
    }
    final last = _last;
    final lastPos = _lastUpPos;
    _last = upAt;
    _lastUpPos = upPos;
    if (last != null &&
        lastPos != null &&
        (downPos - lastPos).distance < kDoubleTapMaxGap &&
        downAt >= last &&
        (downAt - last).inMicroseconds / 1e6 < kDoubleTapWindow) {
      _last = null;
      return TapResult.double;
    }
    return TapResult.first;
  }
}
