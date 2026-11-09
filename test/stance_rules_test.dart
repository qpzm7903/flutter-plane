import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:sky_fighter/game/battle/stance_rules.dart';
import 'package:sky_fighter/game/battle/player_weapon.dart';
import 'package:sky_fighter/game/battle/pickup_rules.dart';
import 'package:sky_fighter/game/battle/double_tap.dart';
import 'package:sky_fighter/pages/widgets/hud_stats.dart';
import 'package:sky_fighter/game/battle/rules_text.dart';

void main() {
  Player player() => Player(x: 200, y: 600);
  void still(Player p, double seconds, {int wave = 6}) {
    for (var t = 0.0; t < seconds; t += 0.01) {
      updateStance(p, 0.01, moved: 0, held: false, wave: wave);
    }
  }

  for (final wave in [0, 1, 2]) {
    test('wave $wave has no focus even with Shift', () {
      final p = player();
      for (var i = 0; i < 100; i++) {
        updateStance(p, 0.01, moved: 0, held: true, wave: wave);
      }
      expect(p.focus, 0);
      expect(p.squeeze, 0);
      expect(p.chargePower, 1);
      expect(p.focused, isFalse);
      expect(p.charge, 0);
    });
  }
  test('focus entry delay and smooth rise', () {
    final p = player();
    still(p, 0.10);
    expect(p.focused, isFalse);
    still(p, 0.03);
    expect(p.focused, isTrue);
    expect(p.focus, inExclusiveRange(0, 1));
    still(p, 1 / kFocusRiseRate);
    expect(p.focus, 1);
  });
  test('hysteresis preserves both sides in intermediate speed band', () {
    final p = player()..moveSpeed = 50;
    updateStance(p, 0.1, moved: 5, held: false, wave: 6);
    expect(p.focused, isFalse);
    p
      ..focused = true
      ..slowTime = 1;
    updateStance(p, 0.1, moved: 5, held: false, wave: 6);
    expect(p.focused, isTrue);
    updateStance(p, 0.1, moved: 20, held: false, wave: 6);
    expect(p.focused, isFalse);
    still(p, 1);
    expect(p.focused, isTrue);
  });
  test('hit radius endpoints and pickup radius stay distinct', () {
    final p = player();
    expect(p.hitRadius, 11);
    p.focus = 1;
    expect(p.hitRadius, kFocusHitRadius);
    expect(Player.radius, 11);
  });
  for (final wave in [3, 4, 5]) {
    test('wave $wave cannot charge', () {
      final p = player();
      still(p, 4, wave: wave);
      expect(p.focus, 1);
      expect(p.charge, 0);
    });
  }
  test('charge needs full focus and takes charge seconds', () {
    final p = player()
      ..focused = true
      ..slowTime = 1
      ..focus = 0.8;
    updateStance(p, 0.01, moved: 0, held: true, wave: 6);
    expect(p.charge, 0);
    p.focus = 1;
    still(p, kChargeSeconds);
    expect(p.charge, closeTo(1, 1e-9));
  });
  test('partial charge decays while moving with zero floor', () {
    final p = player()..charge = 0.5;
    updateStance(p, 0.1, moved: 30, held: false, wave: 6);
    expect(p.charge, closeTo(0.5 - kChargeDecayPerSec * 0.1, 1e-9));
    updateStance(p, 1, moved: 300, held: false, wave: 6);
    expect(p.charge, 0);
  });
  test('full charge holds until a focused to moving transition', () {
    final p = player()..charge = 1;
    expect(updateStance(p, 0.1, moved: 30, held: false, wave: 6), isFalse);
    expect(p.charge, 1);
    p
      ..focused = true
      ..focus = 1
      ..slowTime = 1;
    expect(updateStance(p, 0.1, moved: 30, held: false, wave: 6), isTrue);
    expect(p.charge, 0);
    expect(updateStance(p, 0.1, moved: 30, held: false, wave: 6), isFalse);
  });
  for (var level = 1; level <= 6; level++) {
    test('level $level focus preserves damage and squeezes geometry', () {
      final p = player()..weaponLevel = level;
      final normal = buildPlayerShots(p);
      p.squeeze = 1;
      final focused = buildPlayerShots(p);
      expect(focused.length, normal.length);
      for (var i = 0; i < normal.length; i++) {
        expect(focused[i].damage, normal[i].damage);
        expect(
          (focused[i].x - p.x).abs(),
          lessThanOrEqualTo((normal[i].x - p.x).abs()),
        );
        expect(focused[i].vx.abs(), lessThanOrEqualTo(normal[i].vx.abs()));
      }
    });
  }
  for (final route in WeaponRoute.values) {
    for (final tier in [1, 2]) {
      test('$route tier $tier focus preserves shot stats', () {
        final p = player()
          ..weaponLevel = 6
          ..overdrive = tier
          ..route = route;
        final a = buildPlayerShots(p);
        p.squeeze = 1;
        final b = buildPlayerShots(p);
        expect(b.length, a.length);
        for (var i = 0; i < a.length; i++) {
          expect(b[i].damage, a[i].damage);
          expect(b[i].pierce, a[i].pierce);
          expect((b[i].x - p.x).abs(), lessThanOrEqualTo((a[i].x - p.x).abs()));
          expect(b[i].vx.abs(), lessThanOrEqualTo(a[i].vx.abs()));
        }
      });
    }
  }
  for (final route in [null, ...WeaponRoute.values]) {
    test('charge spec $route', () {
      final p = player()
        ..route = route
        ..overdrive = route == null ? 0 : 1
        ..focus = 1;
      final shots = <Bullet>[];
      appendChargeLance(p, shots);
      final spec = kChargeSpecs[route] ?? kChargeSpecDefault;
      expect(shots.length, spec.angles.length);
      for (var i = 0; i < shots.length; i++) {
        final b = shots[i];
        expect(b.damage, spec.damage);
        expect(b.radius, spec.radius);
        expect(b.cuts, spec.cutsBullets);
        expect(b.pierce, kChargePierce);
        expect(b.kind, BulletKind.chargeLance);
        expect(b.fromPlayer, isTrue);
        expect(b.y, p.y - 16);
        expect(
          b.vx,
          closeTo(math.sin(spec.angles[i]) * kChargeLanceSpeed, 1e-9),
        );
      }
    });
  }
  test('graze token bucket burst, refill, reset and capped meter credit', () {
    final ledger = GrazeLedger();
    final p = player();
    for (var i = 0; i < 20; i++) {
      ledger.credit(p, wave: 3);
    }
    expect(ledger.total, 4);
    expect(p.resonance, 16);
    ledger.refill(0.1);
    expect(ledger.credit(p, wave: 3), kGrazeRewardMoving);
    ledger.refill(10);
    expect(ledger.tokens, kGrazeBucketCapacity);
    p.resonance = 99;
    expect(ledger.credit(p, wave: 3), kGrazeRewardMoving);
    expect(ledger.credit(p, wave: 3), kGrazeRewardMoving);
    expect(ledger.total, 7);
    ledger.clearRun();
    expect(ledger.total, 0);
    expect(ledger.tokens, kGrazeBucketCapacity);
  });
  test('moving and focused resonance gain and analytical requirement', () {
    final ledger = GrazeLedger();
    final p = player();
    expect(ledger.credit(p, wave: 3), kGrazeRewardMoving);
    p.focus = 0.5;
    expect(ledger.credit(p, wave: 3), kGrazeRewardFocused);
    expect(kResonanceMax / kGrazeRewardMoving.resonance, 25);
  });
  test('hit penalty keeps charge and clamps resonance', () {
    final p = player()
      ..charge = 1
      ..resonance = 75
      ..overdrive = 2
      ..route = WeaponRoute.pierce;
    applyHitPenalty(p);
    expect(p.resonance, 55);
    expect(p.charge, 1);
    expect(p.overdrive, 1);
    p.resonance = 5;
    applyHitPenalty(p);
    expect(p.resonance, 0);
    expect(p.route, isNull);
  });
  for (final wave in [2, 4, 5]) {
    for (final value in [0, 999, 1000]) {
      test('HUD meter wave $wave permille $value', () {
        final meter = resonanceMeterFor(value, wave);
        expect(meter.visible, wave >= 3);
        expect(meter.ready, wave >= 5 && value == 1000);
        expect(meter.ratio, value / 1000);
        expect(meter.label, meter.ready ? '共鸣就绪 · 双击' : '共鸣');
      });
    }
  }
  test('rules use tuning and retain seven supplies', () {
    expect(supplyHints().length, PowerUpKind.values.length);
    expect(controlHints().join(), contains('Shift'));
    expect(controlHints().join(), contains('R 共鸣'));
    expect(stanceHints()[0], contains('$kFocusHitRadius'));
    expect(stanceHints()[1], contains('$kGrazeBand'));
    expect(stanceHints()[3], contains('$kChargeSeconds'));
    expect(routeHints().last, contains('$kHitResonanceLoss'));
    for (final wave in [3, 5, 6]) {
      expect(systemHintForWave(wave), isNotNull);
    }
    for (final wave in [1, 2, 4, 7]) {
      expect(systemHintForWave(wave), isNull);
    }
  });
  TapResult tap(
    DoubleTapDetector d,
    int down,
    int up, {
    Offset pos = Offset.zero,
  }) => d.onUp(
    downAt: Duration(milliseconds: down),
    upAt: Duration(milliseconds: up),
    downPos: Offset.zero,
    upPos: pos,
  );
  test('double tap triggers once then requires two new taps', () {
    final d = DoubleTapDetector();
    expect(tap(d, 0, 50), TapResult.first);
    expect(tap(d, 100, 150), TapResult.double);
    expect(tap(d, 200, 250), TapResult.first);
    expect(tap(d, 300, 350), TapResult.double);
  });
  for (final invalid in ['duration', 'travel', 'interval']) {
    test('double tap rejects $invalid', () {
      final d = DoubleTapDetector();
      tap(d, 0, 50);
      expect(
        tap(
          d,
          invalid == 'interval' ? 400 : 100,
          invalid == 'duration'
              ? 300
              : invalid == 'interval'
              ? 450
              : 150,
          pos: invalid == 'travel' ? const Offset(14, 0) : Offset.zero,
        ),
        invalid == 'interval' ? TapResult.first : TapResult.none,
      );
    });
  }
}
