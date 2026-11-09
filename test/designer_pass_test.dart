import 'dart:math' as math;
import 'dart:ui';

import 'package:sky_fighter/game/battle/battle_controller.dart';
import 'package:sky_fighter/game/battle/double_tap.dart';
import 'package:sky_fighter/game/battle/rules_text.dart';
import 'package:sky_fighter/services/sound_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:sky_fighter/game/battle/player_weapon.dart';
import 'package:sky_fighter/game/battle/stance_rules.dart';

void main() {
  for (final route in [null, ...WeaponRoute.values]) {
    for (final tier in route == null ? [0] : [1, 2]) {
      test('Boss damage guard $route $tier', () {
        final p = Player(x: 0, y: 700)
          ..weaponLevel = 6
          ..route = route
          ..overdrive = tier;
        double damage(double squeeze, Iterable<int> offsets) {
          p.squeeze = squeeze;
          var sum = 0.0;
          for (final d in [450, 540, 620]) {
            for (final x in offsets) {
              for (final b in buildPlayerShots(p)) {
                if ((b.x + b.vx / -b.vy * d - x).abs() <= 41) sum += b.damage;
              }
            }
          }
          return sum;
        }

        expect(
          damage(1, [0, -30, 30]) / damage(0, [0, -30, 30]),
          lessThanOrEqualTo(1.25),
        );
        // Converging focus shots cross past an offset target at long range; see design deviations.
        if (route != WeaponRoute.focus) {
          expect(damage(1, [60]), greaterThanOrEqualTo(damage(0, [60])));
        }
      });
    }
  }
  // Deliberately failing v0.7 counterexample, excluded from CI per §11.2.
  test('legacy .5/.6 Boss squeeze violates DPS guard', () {
    final p = Player(x: 0, y: 700)..weaponLevel = 6;
    double damage(double sx, double sa) {
      var sum = 0.0;
      for (final d in [450, 540, 620]) {
        for (final x in [0, -30, 30]) {
          for (final b in buildPlayerShots(p)) {
            final angle = math.atan2(b.vx, -b.vy) * (1 - sa);
            if ((b.x * (1 - sx) + math.tan(angle) * d - x).abs() <= 41) {
              sum += b.damage;
            }
          }
        }
      }
      return sum;
    }

    expect(damage(.5, .6) / damage(0, 0), lessThanOrEqualTo(1.25));
  }, skip: 'v0.7 counterexample: expected ratio 4/3 > 1.25');
  test('squeeze timing and fast held intent', () {
    final p = Player(x: 0, y: 0);
    for (var i = 0; i < 30; i++) {
      updateStance(p, .01, moved: 0, held: false, wave: 6);
    }
    expect(p.squeeze, lessThan(.6));
    for (var i = 0; i < 20; i++) {
      updateStance(p, .01, moved: 0, held: false, wave: 6);
    }
    expect(p.squeeze, greaterThanOrEqualTo(.95));
    p.squeeze = 0;
    updateStance(p, .15, moved: 0, held: true, wave: 6);
    expect(p.squeeze, greaterThanOrEqualTo(.9));
    updateStance(p, 1 / 12, moved: 30, held: false, wave: 6);
    expect(p.squeeze, 0);
  });
  test('60 speed exits focus', () {
    final p = Player(x: 0, y: 0)
      ..focused = true
      ..slowTime = 1
      ..moveSpeed = 60;
    updateStance(p, .1, moved: 6, held: false, wave: 6);
    expect(p.focused, isFalse);
  });
  test('tuning identities', () {
    expect(kSqueezeSeconds, 1 / kSqueezeRiseRate);
    expect(
      kLancePowerMax,
      1 + math.min(40, kLancePowerCapBullets) * kLancePowerPerBullet,
    );
  });
  BattleController arena({int wave = 6}) {
    final c = BattleController(size: const Size(400, 700))..start();
    c.wave = wave;
    c.player.fireCooldown = 100;
    addTearDown(c.dispose);
    return c;
  }

  void bullets(BattleController c, int count) {
    c.enemyBullets.addAll(
      List.generate(
        count,
        (_) => Bullet(
          x: c.player.x + 50,
          y: c.player.y,
          vx: 0,
          vy: 0,
          radius: 3,
          damage: 1,
          fromPlayer: false,
        ),
      ),
    );
  }

  for (final count in [0, 3, 4, 20, 40, 80]) {
    test('absorption power and protection $count', () {
      final c = arena();
      c.player.resonance = 100;
      bullets(c, count);
      c.useResonance();
      expect(c.player.resonance, count < 4 ? 100 : 0);
      expect(c.player.charge, count < 4 ? 0 : 1);
      expect(c.player.invuln, count < 4 ? 0 : kResonanceInvuln);
      expect(
        c.player.chargePower,
        count < 4 ? 1 : 1 + math.min(count, 40) * .05,
      );
    });
  }
  for (final route in [null, ...WeaponRoute.values]) {
    for (final power in [1.2, 2.0, 3.0]) {
      test('heavy lance geometry $route $power', () {
        final p = Player(x: 0, y: 0)
          ..route = route
          ..overdrive = route == null ? 0 : 1
          ..chargePower = power;
        final out = <Bullet>[];
        appendChargeLance(p, out);
        final spec = chargeSpecFor(p);
        for (final b in out) {
          expect(b.damage, spec.damage * power);
          expect(b.radius, spec.radius * (1 + .2 * (power - 1)));
          expect(b.cuts, spec.cutsBullets);
        }
        expect(p.chargePower, power); // Pure builder; controller consumes it.
      });
    }
  }
  test('first tap only arms ready resonance and timer resets', () {
    final c = arena();
    c.armResonance();
    expect(c.resonanceArm, 0);
    c.player.resonance = 100;
    c.armResonance();
    expect(c.resonanceArm, kDoubleTapWindow);
    c.update(.1);
    expect(c.resonanceArm, closeTo(.22, 1e-9));
    c.start();
    expect(c.resonanceArm, 0);
    expect(c.grazePulse, 0);
  });
  test('empty cast protects guard and charge with throttled popup', () {
    final c = arena();
    c.player
      ..resonance = 100
      ..charge = .6;
    final guard = Wingman(side: 0, x: 200, y: 500)
      ..energy = 2
      ..overheat = 3;
    c.wingmen.add(guard);
    bullets(c, 3);
    c.useResonance();
    c.useResonance();
    expect(c.popups.where((p) => p.text == '无弹可吞').length, 1);
    expect(c.player.charge, .6);
    expect(guard.energy, 2);
    expect(guard.overheat, 3);
    final firstPopup = c.popups.first;
    c.update(.81);
    c.player.resonance = 100;
    c.useResonance();
    expect(c.popups.where((p) => p.text == '无弹可吞').length, 1);
    expect(c.popups.last, isNot(same(firstPopup)));
  });
  for (final damaged in [false, true]) {
    test('repair popup only for damaged satellite $damaged', () {
      final c = arena();
      final guard = Wingman(side: 0, x: 200, y: 500)
        ..energy = damaged ? 2 : kGuardMaxEnergy;
      c.wingmen.add(guard);
      c.player.resonance = 100;
      bullets(c, 4);
      c.useResonance();
      expect(c.popups.any((p) => p.text == '卫星复位'), damaged);
      expect(guard.energy, kGuardMaxEnergy);
    });
  }
  test('wave five resonance keeps heavy lance locked', () {
    final c = arena(wave: 5);
    c.player.resonance = 100;
    bullets(c, 40);
    c.useResonance();
    expect(c.player.chargePower, 1);
    expect(c.player.charge, 0);
  });
  test('already charged resonance upgrades then consumes lance once', () {
    final c = arena();
    c.player
      ..resonance = 100
      ..charge = 1
      ..focus = 1
      ..focused = true
      ..slowTime = 1;
    bullets(c, 20);
    c.useResonance();
    expect(c.player.chargePower, 2);
    c.movePlayerBy(const Offset(30, 0));
    c.update(.01);
    expect(c.playerBullets.single.damage, 28);
    expect(c.player.chargePower, 1);
    expect(c.popups.any((p) => p.text == '矛击 ×2.0'), isTrue);
  });
  for (final shield in [false, true]) {
    test('real hit extinguishes power but shield preserves it $shield', () {
      final c = arena();
      c.player
        ..charge = .7
        ..chargePower = 3
        ..shield = shield ? 5 : 0;
      c.enemyBullets.add(
        Bullet(
          x: c.player.x,
          y: c.player.y,
          vx: 0,
          vy: 0,
          radius: 3,
          damage: 1,
          fromPlayer: false,
        ),
      );
      c.update(.001);
      expect(c.player.chargePower, shield ? 3 : 1);
      expect(c.player.charge, closeTo(.7 - .001 * kChargeDecayPerSec, 1e-9));
    });
  }
  for (final focus in [0.0, 1.0]) {
    test('graze pays all three outputs $focus', () {
      final c = arena();
      c.player
        ..focus = focus
        ..focused = focus == 1
        ..slowTime = 1;
      c.combo = 2;
      c.comboTimer = 1;
      c.enemyBullets.add(
        Bullet(
          x: c.player.x + 24,
          y: c.player.y,
          vx: 0,
          vy: 0,
          radius: 3,
          damage: 1,
          fromPlayer: false,
        ),
      );
      c.update(.001);
      final reward = grazeRewardFor(focus);
      expect(c.score, reward.score);
      expect(c.player.resonance, reward.resonance);
      expect(c.comboTimer, closeTo(1 + reward.comboExtend - .001, 1e-9));
      expect(c.grazePulse, 1);
    });
  }
  for (final gap in [55.0, 56.0, 100.0]) {
    test('double tap spatial boundary $gap', () {
      final d = DoubleTapDetector();
      expect(
        d.onUp(
          downAt: Duration.zero,
          upAt: const Duration(milliseconds: 50),
          downPos: Offset.zero,
          upPos: Offset.zero,
        ),
        TapResult.first,
      );
      expect(
        d.onUp(
          downAt: const Duration(milliseconds: 100),
          upAt: const Duration(milliseconds: 150),
          downPos: Offset(gap, 0),
          upPos: Offset(gap, 0),
        ),
        gap < 56 ? TapResult.double : TapResult.first,
      );
    });
  }
  test('focus hitbox and charge independent from squeeze', () {
    final p = Player(x: 0, y: 0)
      ..focus = 1
      ..squeeze = 0;
    expect(p.hitRadius, kFocusHitRadius);
    updateStance(p, .1, moved: 0, held: true, wave: 6);
    expect(p.charge, closeTo(.1 / kChargeSeconds, 1e-9));
  });
  test('charge decay is .18 over a .3 second dash', () {
    final p = Player(x: 0, y: 0)..charge = .6;
    updateStance(p, .3, moved: 90, held: false, wave: 6);
    expect(p.charge, closeTo(.42, 1e-9));
  });
  test('dedicated synthesized sounds differ from routine sounds', () {
    for (final sound in [GameSound.lance, GameSound.resonance]) {
      for (final other in [GameSound.shoot, GameSound.powerUp]) {
        expect(
          SoundService.clipOf(sound),
          isNot(orderedEquals(SoundService.clipOf(other))),
        );
      }
    }
  });
  test('instruction numbers come from tuning and seven supplies remain', () {
    final hints = stanceHints();
    expect(hints[0], contains('$kSqueezeSeconds'));
    expect(hints[1], contains('${kGrazeRewardMoving.score}'));
    expect(hints[1], contains('${kGrazeRewardFocused.score}'));
    expect(hints[2], contains('$kResonanceMinConvert'));
    expect(hints[3], contains('$kLancePowerMax'));
    expect(supplyHints().length, 7);
  });
}
