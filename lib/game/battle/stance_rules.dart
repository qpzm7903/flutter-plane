import 'dart:math' as math;

import 'battle_types.dart';
import 'battle_tuning.dart';

bool updateStance(
  Player p,
  double dt, {
  required double moved,
  required bool held,
  required int wave,
}) {
  if (dt <= 0) return false;
  if (wave < kFocusFromWave) {
    p.focus = 0;
    p.focused = false;
    p.slowTime = 0;
    return false;
  }
  p.moveSpeed +=
      (moved / dt - p.moveSpeed) * math.min(1, dt * kMoveSpeedSmoothing);
  final slow = p.moveSpeed < (p.focused ? kFocusExitSpeed : kFocusEnterSpeed);
  p.slowTime = slow ? p.slowTime + dt : 0;
  final want = held || p.slowTime >= kFocusEnterDelay;
  final release =
      wave >= kChargeFromWave && p.focused && !want && p.charge >= 1;
  p.focused = want;
  p.focus += ((want ? 1.0 : 0.0) - p.focus).clamp(
    -kFocusFallRate * dt,
    kFocusRiseRate * dt,
  );
  if (release) {
    p.charge = 0;
  } else if (wave >= kChargeFromWave) {
    if (p.focus >= 0.95) {
      p.charge = math.min(1, p.charge + dt / kChargeSeconds);
    } else if (!want && p.charge < 1) {
      p.charge = math.max(0, p.charge - dt * kChargeDecayPerSec);
    }
  }
  return release;
}

class GrazeLedger {
  int total = 0;
  double tokens = kGrazeBucketCapacity;
  void refill(double dt) =>
      tokens = math.min(kGrazeBucketCapacity, tokens + dt * kGrazeTokensPerSec);
  double credit(Player p, {required int wave}) {
    if (wave < kGrazeFromWave || !p.alive || p.invuln > 0 || tokens < 1) {
      return 0;
    }
    tokens -= 1;
    total++;
    final gain = p.focus < 0.5 ? kGrazeGainMoving : kGrazeGainFocused;
    final before = p.resonance;
    p.resonance = math.min(kResonanceMax, before + gain);
    return p.resonance - before;
  }

  void clearRun() {
    total = 0;
    tokens = kGrazeBucketCapacity;
  }
}

bool canResonate(Player p, int wave) =>
    wave >= kResonanceFromWave && p.resonance >= kResonanceCost;
