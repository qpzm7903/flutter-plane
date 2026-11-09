import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_controller.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:sky_fighter/game/battle/player_weapon.dart';
import 'package:sky_fighter/game/battle/battle_effects.dart';
import 'package:sky_fighter/game/challenge/daily_challenge.dart';

void main() {
  BattleController arena({int wave = 6, DailyChallenge? challenge}) {
    final c = BattleController(
      size: const Size(400, 700),
      seed: 42,
      challenge: challenge,
    )..start();
    c.wave = wave;
    c.player.fireCooldown = 100;
    addTearDown(c.dispose);
    return c;
  }

  Bullet shot(BattleController c, {double dx = 24, double dy = 0}) => Bullet(
    x: c.player.x + dx,
    y: c.player.y + dy,
    vx: 0,
    vy: 0,
    radius: 4.2,
    damage: 1,
    fromPlayer: false,
  );
  test('barrage score scaling applies to graze and resonance', () {
    final c = arena(
      challenge: const DailyChallenge(
        dateKey: '2026-11-08',
        seed: 42,
        modifier: ChallengeModifier.barrage,
      ),
    );
    c.combo = 12;
    c.comboTimer = 1;
    c.enemyBullets.add(shot(c));
    c.update(0.001);
    expect(c.score, (kGrazeScore * 2 * 1.1).round());
    c.player.resonance = 100;
    c.useResonance();
    expect(c.score, 22 + 44);
  });
  test('identical kill scripts retain drop sequence with graze and resonance effects', () {
    final a = arena(), b = arena();
    final dropsA = <PowerUpKind>[], dropsB = <PowerUpKind>[];
    for (var i = 0; i < 90; i++) {
      // Both scripts advance the same time, kills, player state and explosion effects.
      for (final c in [a, b]) {
        c.player.invuln = 0;
        c.enemies.clear();
        c.playerBullets.clear();
        c.enemyBullets.clear();
        c.powerUps.clear();
      }
      b.enemyBullets.add(shot(b));
      a.update(0.001);
      b.update(0.001);
      b.player.resonance = 100;
      b.useResonance();
      b.player.invuln = 0;
      for (final c in [a, b]) {
        c.enemies.add(
          Enemy(
            kind: EnemyKind.scout,
            pattern: EnemyPattern.straight,
            x: 50,
            y: 150,
            difficulty: 1,
          ),
        );
        c.playerBullets.add(
          Bullet(
            x: 50,
            y: 150,
            vx: 0,
            vy: 0,
            radius: 4,
            damage: 100,
            fromPlayer: true,
          ),
        );
        c.update(0.001);
      }
      dropsA.addAll(a.powerUps.map((p) => p.kind));
      dropsB.addAll(b.powerUps.map((p) => p.kind));
    }
    expect(dropsA, isNotEmpty);
    expect(dropsB, dropsA);
  });
  test('graze credits once per bullet', () {
    final c = arena();
    final b = shot(c);
    c.enemyBullets.add(b);
    c.update(0.001);
    expect(c.grazes, 1);
    expect(b.grazed, isTrue);
    expect(c.score, kGrazeScore);
    expect(c.player.resonance, kGrazeGainMoving);
    c.update(0.001);
    expect(c.grazes, 1);
  });
  for (final condition in ['locked', 'invulnerable', 'dead']) {
    test('graze disabled while $condition', () {
      final c = arena(wave: condition == 'locked' ? 2 : 6);
      if (condition == 'invulnerable') c.player.invuln = 2;
      if (condition == 'dead') c.player.alive = false;
      c.enemyBullets.add(shot(c));
      c.update(0.001);
      expect(c.grazes, 0);
      expect(c.player.resonance, 0);
    });
  }
  test('hit takes priority over graze', () {
    final c = arena();
    final b = shot(c, dx: 0);
    c.enemyBullets.add(b);
    c.update(0.001);
    expect(c.player.lives, 2);
    expect(b.grazed, isFalse);
    expect(c.grazes, 0);
  });
  test('focused graze has half gain and full radius graze band', () {
    final c = arena();
    c.player
      ..focus = 1
      ..focused = true
      ..slowTime = 1;
    c.enemyBullets.add(shot(c, dx: 12));
    c.update(0.001);
    expect(c.player.lives, 3);
    expect(c.grazes, 1);
    expect(c.player.resonance, kGrazeGainFocused);
  });
  test('graze bucket marks discarded bullets and limits later credits', () {
    final c = arena();
    for (var i = 0; i < 20; i++) {
      c.enemyBullets.add(shot(c));
    }
    c.update(0.001);
    expect(c.grazes, 4);
    expect(c.enemyBullets.every((b) => b.grazed), isTrue);
    c.update(0.1);
    expect(c.grazes, 4);
    for (var i = 0; i < 9; i++) {
      c.enemyBullets.add(shot(c));
      c.update(0.1);
    }
    expect(c.grazes, lessThanOrEqualTo(14));
  });
  test('graze extends existing combo without increasing combo', () {
    final c = arena()
      ..combo = 5
      ..comboTimer = 1;
    c.enemyBullets.add(shot(c));
    c.update(0.001);
    expect(c.combo, 5);
    expect(c.comboTimer, closeTo(1.25 - 0.001, 1e-9));
    c.comboTimer = kComboWindow;
    c.enemyBullets.add(shot(c));
    c.update(0.001);
    expect(c.comboTimer, lessThanOrEqualTo(kComboWindow));
  });
  test('graze does not start combo and full meter still earns score', () {
    final c = arena();
    c.player.resonance = 100;
    c.enemyBullets.add(shot(c));
    c.update(0.001);
    expect(c.comboTimer, 0);
    expect(c.combo, 0);
    expect(c.player.resonance, 100);
    expect(c.score, 10);
  });
  test('guard absorbs before graze', () {
    final c = arena();
    c.wingmen.add(
      Wingman(side: 0, x: c.player.x, y: c.player.y - kGuardOffsetY)
        ..energy = 12,
    );
    c.enemyBullets.add(shot(c, dx: 0, dy: -24));
    c.update(0.001);
    expect(c.enemyBullets.single.dead, isTrue);
    expect(c.grazes, 0);
  });
  test('bomb clears without graze or resonance', () {
    final c = arena();
    c.enemyBullets.add(shot(c));
    c.useBomb();
    c.update(0.001);
    expect(c.grazes, 0);
    expect(c.player.resonance, 0);
  });
  for (final wave in [4, 5]) {
    test('resonance gate wave $wave', () {
      final c = arena(wave: wave);
      c.player.resonance = wave == 4 ? 100 : 99;
      final before = c.player.resonance;
      c.useResonance();
      expect(c.player.resonance, before);
      expect(c.player.invuln, 0);
      expect(c.pendingEvents, isNot(contains(BattleEvent.resonance)));
    });
  }
  for (final phase in [
    BattlePhase.ready,
    BattlePhase.paused,
    BattlePhase.gameOver,
  ]) {
    test('resonance ignores $phase', () {
      final c = arena();
      c.player.resonance = 100;
      c.phase = phase;
      c.useResonance();
      expect(c.player.resonance, 100);
    });
  }
  test('resonance clears all nearby bullets and caps conversion at sixty', () {
    final c = arena()
      ..combo = 30
      ..comboTimer = 1;
    c.player
      ..resonance = 100
      ..shield = 4;
    for (var i = 0; i < 70; i++) {
      c.enemyBullets.add(shot(c));
    }
    final boundary = shot(c, dx: kResonanceRadius);
    final outside = shot(c, dx: kResonanceRadius + 1);
    c.enemyBullets.addAll([boundary, outside]);
    final enemy = Enemy(
      kind: EnemyKind.fortress,
      pattern: EnemyPattern.straight,
      x: c.player.x,
      y: c.player.y - 80,
      difficulty: 1,
    );
    c.enemies.add(enemy);
    final hp = enemy.hp;
    c.useResonance();
    expect(c.enemyBullets.where((b) => b.dead).length, 71);
    expect(outside.dead, isFalse);
    expect(c.score, 60 * 20 * 3);
    expect(c.player.resonance, 0);
    expect(c.player.invuln, kResonanceInvuln);
    expect(c.player.shield, 4);
    expect(enemy.hp, hp);
    expect(c.comboTimer, kComboWindow);
    expect(c.player.charge, 1);
    expect(c.pendingEvents, contains(BattleEvent.resonance));
  });
  test('resonance restores guard and never shortens invulnerability', () {
    final c = arena();
    c.player
      ..resonance = 100
      ..invuln = 2;
    final guard = Wingman(side: 0, x: 200, y: 500)
      ..energy = 0
      ..overheat = 4;
    c.wingmen.add(guard);
    c.useResonance();
    expect(c.player.invuln, 2);
    expect(guard.energy, kGuardMaxEnergy);
    expect(guard.overheat, 0);
  });
  test('wave five resonance does not fill locked charge', () {
    final c = arena(wave: 5);
    c.player.resonance = 100;
    c.useResonance();
    expect(c.player.charge, 0);
  });
  test('bomb and resonance commute for player resources', () {
    final a = arena(), b = arena();
    for (final c in [a, b]) {
      c.player.resonance = 100;
      c.enemyBullets.add(shot(c));
    }
    a.useBomb();
    a.useResonance();
    b.useResonance();
    b.useBomb();
    expect(a.player.bombs, b.player.bombs);
    expect(a.player.charge, b.player.charge);
    expect(a.player.invuln, b.player.invuln);
    expect(a.player.resonance, b.player.resonance);
    expect(a.enemyBullets, b.enemyBullets);
  });
  test('lance emitted only at focused to moving transition', () {
    final c = arena();
    c.player
      ..focus = 1
      ..focused = true
      ..slowTime = 1
      ..charge = 1;
    c.movePlayerBy(const Offset(30, 0));
    c.update(0.01);
    expect(c.playerBullets.single.kind, BulletKind.chargeLance);
    expect(c.player.charge, 0);
    expect(c.pendingEvents, contains(BattleEvent.lance));
    c.update(0.01);
    expect(c.playerBullets.length, 1);
  });
  test('default lance pierces four scouts in one swept path', () {
    final c = arena();
    appendChargeLance(c.player, c.playerBullets);
    for (var i = 0; i < 4; i++) {
      c.enemies.add(
        Enemy(
          kind: EnemyKind.scout,
          pattern: EnemyPattern.straight,
          x: c.player.x,
          y: c.player.y - 35 - 30 * i,
          difficulty: 1,
        ),
      );
    }
    c.update(0.2);
    expect(c.kills, 4);
    expect(c.playerBullets.single.dead, isFalse);
  });
  test('boss consumes lance after one hit', () {
    final c = arena();
    appendChargeLance(c.player, c.playerBullets);
    final boss =
        Enemy(
            kind: EnemyKind.boss,
            pattern: EnemyPattern.hover,
            x: c.player.x,
            y: c.player.y - 50,
            difficulty: 1,
          )
          ..entered = true
          ..attackTimer = 100;
    // Entry movement is disabled by entered, hover center follows elapsed; place shot at expected x.
    c.enemies.add(boss);
    c.playerBullets.single.x = 200;
    boss.y = 100;
    c.playerBullets.single.y = 115;
    final hp = boss.hp;
    c.update(0.001);
    expect(boss.hp, hp - kChargeSpecDefault.damage);
    expect(c.playerBullets.single.dead, isTrue);
  });
  for (final route in WeaponRoute.values) {
    test('$route lance cutting only on pierce route', () {
      final c = arena();
      c.player
        ..route = route
        ..overdrive = 1;
      appendChargeLance(c.player, c.playerBullets);
      final b = shot(c, dx: 0, dy: -45);
      c.enemyBullets.add(b);
      c.update(0.05);
      expect(b.dead, route == WeaponRoute.pierce);
      expect(c.grazes, 0);
      expect(c.score, 0);
    });
  }
  test('wingmen tuck, guard remains in front', () {
    final c = arena();
    c.player
      ..focus = 1
      ..focused = true
      ..slowTime = 1;
    for (final side in [-1, 1, 0]) {
      c.wingmen.add(Wingman(side: side, x: c.player.x, y: c.player.y));
    }
    for (var i = 0; i < 100; i++) {
      c.update(0.01);
    }
    expect(
      c.wingmen[0].x - c.player.x,
      closeTo(-kWingmanOffsetX * (1 - kFocusWingmanSqueeze), 0.001),
    );
    expect(
      c.wingmen[1].x - c.player.x,
      closeTo(kWingmanOffsetX * (1 - kFocusWingmanSqueeze), 0.001),
    );
    expect(c.wingmen[2].x, c.player.x);
  });
  test('Shift scales keyboard speed only after unlock', () {
    for (final wave in [2, 3]) {
      final c = arena(wave: wave);
      c.setFocusHeld(true);
      c.setMoveAxis(const Offset(1, 0));
      final x = c.player.x;
      c.update(0.1);
      expect(
        c.player.x - x,
        closeTo(30 * (wave == 2 ? 1 : kFocusKeySpeedScale), 1e-9),
      );
      expect(c.player.focused, wave >= 3);
      c.setFocusHeld(false);
      final next = c.player.x;
      c.update(0.1);
      expect(c.player.x - next, closeTo(30, 1e-9));
    }
  });
  test(
    'damage retains charge and grazes, shield and invuln retain resonance',
    () {
      final c = arena();
      c.enemyBullets.add(shot(c));
      c.update(0.001);
      c.player
        ..resonance = 75
        ..charge = 1;
      c.enemyBullets.add(shot(c, dx: 0));
      c.update(0.001);
      expect(c.player.resonance, 55);
      expect(c.player.charge, 1);
      expect(c.grazes, 1);
      c.player
        ..invuln = 0
        ..shield = 5
        ..resonance = 75;
      c.enemyBullets.add(shot(c, dx: 0));
      c.update(0.001);
      expect(c.player.resonance, 75);
      expect(c.player.charge, 1);
      c.enemyBullets.add(shot(c, dx: 0));
      c.update(0.001);
      expect(c.player.resonance, 75);
    },
  );
  test('meter syncs independently at ten Hz and reset clears run', () {
    final c = arena();
    var updates = 0;
    c.resonanceMeter.addListener(() => updates++);
    c.player.resonance = 50;
    c.update(0.05);
    expect(updates, 0);
    c.update(0.05);
    expect(updates, 1);
    expect(c.resonanceMeter.value, 500);
    c.start();
    expect(c.resonanceMeter.value, 0);
    expect(c.grazes, 0);
    expect(c.player.focus, 0);
  });
  test('new effects never consume combat random stream', () {
    final rng = math.Random(42), baseline = math.Random(42);
    final fx = BattleEffects(rng, math.Random(43));
    for (var i = 0; i < 100; i++) {
      fx.grazeSpark(const Offset(200, 200), 0xFFFFFFFF);
      fx.absorbBurst(const Offset(200, 300), const Offset(200, 200));
      fx.absorbRing(const Offset(200, 300));
    }
    expect(fx.particles.length, lessThanOrEqualTo(BattleEffects.maxParticles));
    for (var i = 0; i < 100; i++) {
      expect(rng.nextDouble(), baseline.nextDouble());
    }
  });
}
