import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:sky_fighter/game/challenge/daily_challenge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_controller.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/wave_director.dart';

BattleController buildController({int highScore = 0}) {
  final controller = BattleController(
    size: const Size(400, 700),
    highScore: highScore,
    seed: 42,
  );
  controller.start();
  return controller;
}

void advance(
  BattleController controller,
  double seconds, {
  double step = 1 / 60,
}) {
  var remaining = seconds;
  while (remaining > 0) {
    final dt = remaining < step ? remaining : step;
    controller.update(dt);
    remaining -= dt;
  }
}

void main() {
  group('穿透碰撞', () {
    BattleController arena() {
      final c = buildController();
      c.player.fireCooldown = 100;
      addTearDown(c.dispose);
      return c;
    }

    Enemy enemy(
      BattleController c,
      double y, {
      EnemyKind kind = EnemyKind.fighter,
      double? hp,
    }) {
      final e = Enemy(
        kind: kind,
        pattern: EnemyPattern.straight,
        x: 200,
        y: y,
        difficulty: 1,
      )..vy = 0;
      if (hp != null) e.hp = hp;
      c.enemies.add(e);
      return e;
    }

    Bullet shot(
      BattleController c, {
      int pierce = 1,
      double y = 200,
      double vy = -560,
    }) {
      final b = Bullet(
        x: 200,
        y: y,
        vx: 0,
        vy: vy,
        radius: 3.6,
        damage: 2,
        fromPlayer: true,
        pierce: pierce,
        kind: BulletKind.lance,
      );
      c.playerBullets.add(b);
      return b;
    }

    test('一帧扫过两架敌机，两架受伤后消失', () {
      final c = arena(), dt = 0.1;
      final a = enemy(c, 185), b = enemy(c, 150), s = shot(c);
      c.update(dt);
      expect(a.hp, 8);
      expect(b.hp, 8);
      expect(s.dead, isTrue);
    });
    test('连续多帧重叠同一架敌机只结算一次', () {
      final c = arena(), a = enemy(c, 200), s = shot(c, vy: 0);
      for (var i = 0; i < 5; i++) {
        c.update(0.01);
      }
      expect(a.hp, 8);
      expect(s.lastHit, same(a));
      expect(s.dead, isFalse);
    });
    test('命中 Boss 即消失且不伤后方敌机', () {
      final c = arena(),
          a = enemy(c, 92, kind: EnemyKind.boss),
          b = enemy(c, 92),
          s = shot(c, y: 92, vy: 0);
      c.update(0.01);
      final hp = a.hp;
      c.update(0.01);
      expect(hp, a.maxHp - 2);
      expect(a.hp, hp);
      expect(b.hp, 10);
      expect(s.dead, isTrue);
    });
    test('普通弹命中第一架即消失', () {
      final c = arena(),
          a = enemy(c, 185),
          b = enemy(c, 150),
          s = shot(c, pierce: 0);
      c.update(0.1);
      expect(a.hp, 8);
      expect(b.hp, 10);
      expect(s.dead, isTrue);
    });
    test('击杀第一架后仍能飞行并命中第二架', () {
      final c = arena(),
          a = enemy(c, 190, hp: 2),
          b = enemy(c, 130),
          s = shot(c);
      c.update(0.01);
      expect(a.dead, isTrue);
      expect(s.dead, isFalse);
      c.update(0.1);
      expect(b.hp, 8);
      expect(s.dead, isTrue);
    });
    test('敌弹忽略穿透字段，仍按玩家受伤规则消失', () {
      final c = arena();
      c.player.invuln = 0;
      final s = Bullet(
        x: c.player.x,
        y: c.player.y,
        vx: 0,
        vy: 0,
        radius: 4,
        damage: 1,
        fromPlayer: false,
        pierce: 1,
      );
      c.enemyBullets.add(s);
      c.update(0.01);
      expect(c.player.lives, Player.startLives - 1);
      expect(s.dead, isTrue);
    });
  });
  group('掉落接线', () {
    Enemy kill(BattleController c, EnemyKind kind) {
      final e = Enemy(
        kind: kind,
        pattern: EnemyPattern.straight,
        x: 200,
        y: kind == EnemyKind.boss ? 92 : 150,
        difficulty: 1,
      )..vy = 0;
      c.enemies.add(e);
      c.playerBullets.add(
        Bullet(
          x: 200,
          y: e.y,
          vx: 0,
          vy: 0,
          radius: 3,
          damage: 10000,
          fromPlayer: true,
        ),
      );
      c.update(0.001);
      return e;
    }

    test('Boss 三份补给按左右偏移摆放，中间保证炸弹', () {
      final c = buildController();
      addTearDown(c.dispose);
      final e = kill(c, EnemyKind.boss);
      expect(c.powerUps, hasLength(3));
      expect(c.powerUps.map((p) => p.x), [
        e.x - kBossDropOffsetX,
        e.x,
        e.x + kBossDropOffsetX,
      ]);
      expect(c.powerUps[1].kind, PowerUpKind.bomb);
    });
    test('同种子同击破脚本得到完全相同掉落序列', () {
      final a = buildController(), b = buildController();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      List<List<Object>> script(BattleController c) {
        final out = <List<Object>>[];
        for (var i = 0; i < 60; i++) {
          kill(c, EnemyKind.values[i % 7]);
          out.add([for (final p in c.powerUps) p.kind]);
          c.powerUps.clear();
        }
        return out;
      }

      final expected = script(a);
      expect(script(b), expected);
    });
    test('普通与补给管制下第四次精英击破均保证炸弹', () {
      // 固定种子此脚本前三次没有随机炸弹，第四次命中保底。
      for (final modifier in [
        ChallengeModifier.standard,
        ChallengeModifier.scarcity,
      ]) {
        final c = BattleController(
          size: const Size(400, 700),
          seed: 42,
          challenge: DailyChallenge(
            dateKey: '20261108',
            seed: 42,
            modifier: modifier,
          ),
        )..start();
        addTearDown(c.dispose);
        for (var i = 0; i < 3; i++) {
          kill(c, EnemyKind.elite);
        }
        expect(c.powerUps.where((p) => p.kind == PowerUpKind.bomb), isEmpty);
        c.powerUps.clear();
        kill(c, EnemyKind.elite);
        expect(c.powerUps.single.kind, PowerUpKind.bomb);
      }
    });
    test('僚机拾取按侧设置初始节拍并遵守数量上限', () {
      final c = buildController();
      addTearDown(c.dispose);
      for (var i = 0; i < 3; i++) {
        c.powerUps.add(
          PowerUp(x: c.player.x, y: c.player.y, kind: PowerUpKind.wingman),
        );
        c.update(0.001);
      }
      expect(c.wingmen, hasLength(Player.maxWingmen));
      expect(c.wingmen.map((w) => w.role), [
        WingmanRole.gale,
        WingmanRole.heavy,
      ]);
      expect(c.wingmen[1].cooldown, greaterThan(0));
    });
  });

  group('BattleController 基础流程', () {
    test('开始后进入战斗并自动开火', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      expect(controller.phase, BattlePhase.playing);
      expect(controller.score, 0);
      expect(controller.player.lives, 3);

      advance(controller, 0.3);
      expect(controller.playerBullets, isNotEmpty);
      expect(controller.playerBullets.first.vy, lessThan(0));
    });

    test('玩家移动被限制在战场内', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.movePlayerBy(const Offset(-9999, -9999));
      expect(controller.player.x, 16);
      expect(controller.player.y, 44);

      controller.movePlayerBy(const Offset(9999, 9999));
      expect(controller.player.x, 384);
      expect(controller.player.y, 674);
    });

    test('第一波敌机按时抵达', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      advance(controller, 1.5);
      expect(controller.enemies, isNotEmpty);
      expect(controller.wave, 1);
    });

    test('击中与击破敌机累计得分与连击', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      final enemy = Enemy(
        kind: EnemyKind.scout,
        pattern: EnemyPattern.straight,
        x: 200,
        y: 120,
        difficulty: 1,
      );
      controller.enemies.add(enemy);
      controller.playerBullets.add(
        Bullet(
          x: 200,
          y: 128,
          vx: 0,
          vy: -500,
          radius: 3.4,
          damage: 10,
          fromPlayer: true,
        ),
      );

      advance(controller, 0.03);
      expect(enemy.dead, isTrue);
      expect(controller.kills, 1);
      expect(controller.combo, 1);
      expect(controller.score, 60);
      expect(controller.popups.any((popup) => popup.text == '+60'), isTrue);
    });

    test('连击倍率随击破数提升', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.combo = 12;
      expect(controller.multiplier, 2);
      controller.combo = 30;
      expect(controller.multiplier, 3);
      controller.combo = 60;
      expect(controller.multiplier, 4);
    });

    test('高速子弹不会穿透小敌机', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      final enemy = Enemy(
        kind: EnemyKind.scout,
        pattern: EnemyPattern.straight,
        x: 200,
        y: 200,
        difficulty: 1,
      );
      controller.enemies.add(enemy);
      // 一帧跨越 60 像素，若不使用扫掠检测会直接穿过半径 11 的敌机。
      controller.playerBullets.add(
        Bullet(
          x: 200,
          y: 240,
          vx: 0,
          vy: -3600,
          radius: 3,
          damage: 1,
          fromPlayer: true,
        ),
      );
      controller.update(1 / 60);
      expect(enemy.hp, lessThan(enemy.maxHp));
    });

    test('包围盒相交但线段未命中时不会误伤', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      final enemy = Enemy(
        kind: EnemyKind.scout,
        pattern: EnemyPattern.straight,
        x: 200,
        y: 200,
        difficulty: 1,
      );
      controller.enemies.add(enemy);
      // 扫掠线段的包围盒覆盖敌机，但线段本身与敌机圆的最近距离约 14 > 半径 11+3。
      controller.playerBullets.add(
        Bullet(
          x: 230,
          y: 150,
          vx: 5400,
          vy: -5400,
          radius: 3,
          damage: 1,
          fromPlayer: true,
        ),
      );
      controller.update(1 / 60);
      expect(enemy.hp, enemy.maxHp);
    });

    test('战斗事件按帧累积，消费后清空', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      advance(controller, 0.2);

      expect(controller.pendingEvents, contains(BattleEvent.shoot));
      controller.clearEvents();

      expect(controller.pendingEvents, isEmpty);
    });
  });

  group('补给与炸弹', () {
    test('拾取火力补给提升弹道等级', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.powerUps.add(
        PowerUp(
          x: controller.player.x,
          y: controller.player.y,
          kind: PowerUpKind.weapon,
        ),
      );
      advance(controller, 0.02);
      expect(controller.player.weaponLevel, 2);
      expect(controller.powerUps, isEmpty);
    });

    test('满级火力拾取转为分数', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.player.weaponLevel = Player.maxWeaponLevel;
      controller.powerUps.add(
        PowerUp(
          x: controller.player.x,
          y: controller.player.y,
          kind: PowerUpKind.weapon,
        ),
      );
      advance(controller, 0.02);
      expect(controller.player.weaponLevel, Player.maxWeaponLevel);
      expect(controller.score, 300);
    });

    test('护盾抵挡一次伤害', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.player.shield = 8;
      controller.enemyBullets.add(
        Bullet(
          x: controller.player.x,
          y: controller.player.y + 10,
          vx: 0,
          vy: -100,
          radius: 5,
          damage: 1,
          fromPlayer: false,
        ),
      );
      advance(controller, 0.02);
      expect(controller.player.lives, 3);
      expect(controller.player.shield, 0);
      expect(controller.player.invuln, greaterThan(0));
    });

    test('急速补给开启限时射速提升且不会影响火力等级', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.powerUps.add(
        PowerUp(
          x: controller.player.x,
          y: controller.player.y,
          kind: PowerUpKind.rapid,
        ),
      );
      final level = controller.player.weaponLevel;
      advance(controller, 0.02);
      expect(controller.player.rapid, greaterThan(0));
      expect(controller.player.weaponLevel, level);
      expect(controller.popups.any((popup) => popup.text == '急速射击'), isTrue);

      advance(controller, 0.5);
      expect(controller.player.rapid, lessThan(9));
    });

    test('急速射击在相同时长内打出更多弹丸', () {
      final normal = buildController();
      final rapid = buildController()..player.rapid = 10;
      addTearDown(normal.dispose);
      addTearDown(rapid.dispose);

      advance(normal, 0.7);
      advance(rapid, 0.7);

      expect(
        rapid.playerBullets.length,
        greaterThan(normal.playerBullets.length),
      );
    });

    test('炸弹清空敌弹并伤害全场敌机', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      final enemy = Enemy(
        kind: EnemyKind.bomber,
        pattern: EnemyPattern.straight,
        x: 120,
        y: 80,
        difficulty: 1,
      );
      controller.enemies.add(enemy);
      controller.enemyBullets.add(
        Bullet(
          x: 100,
          y: 100,
          vx: 0,
          vy: 100,
          radius: 4,
          damage: 1,
          fromPlayer: false,
        ),
      );
      final bombsBefore = controller.player.bombs;
      controller.useBomb();

      expect(controller.player.bombs, bombsBefore - 1);
      expect(controller.enemyBullets, isEmpty);
      expect(enemy.hp, lessThan(enemy.maxHp));
    });

    test('炸弹耗尽后无法释放', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.player.bombs = 0;
      controller.useBomb();
      expect(controller.player.bombs, 0);
      expect(controller.flash, 0);
    });
  });

  group('受伤与结算', () {
    test('生命耗尽进入结算并记录存活时间', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.player.lives = 1;
      controller.enemies.add(
        Enemy(
          kind: EnemyKind.scout,
          pattern: EnemyPattern.straight,
          x: controller.player.x,
          y: controller.player.y,
          difficulty: 1,
        ),
      );

      advance(controller, 0.05);
      expect(controller.phase, BattlePhase.gameOver);
      expect(controller.player.lives, 0);
      expect(controller.player.alive, isFalse);
      expect(controller.survived.inMilliseconds, greaterThan(0));
    });

    test('受伤后短暂无敌且火力降一级', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.player.weaponLevel = 4;
      controller.enemies.add(
        Enemy(
          kind: EnemyKind.scout,
          pattern: EnemyPattern.straight,
          x: controller.player.x,
          y: controller.player.y,
          difficulty: 1,
        ),
      );
      advance(controller, 0.03);
      expect(controller.player.lives, 2);
      expect(controller.player.weaponLevel, 3);
      expect(controller.player.invuln, greaterThan(0));
    });

    test('暂停时逻辑停止推进', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      advance(controller, 0.2);
      final y = controller.playerBullets.first.y;
      controller.pause();
      advance(controller, 0.5);
      expect(controller.playerBullets.first.y, y);
      controller.resume();
      advance(controller, 0.1);
      expect(controller.phase, BattlePhase.playing);
    });

    test('游戏结束后只更新特效', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.player.lives = 1;
      controller.enemies.add(
        Enemy(
          kind: EnemyKind.scout,
          pattern: EnemyPattern.straight,
          x: controller.player.x,
          y: controller.player.y,
          difficulty: 1,
        ),
      );
      advance(controller, 0.05);
      final particleCount = controller.particles.length;
      advance(controller, 0.5);
      expect(controller.phase, BattlePhase.gameOver);
      expect(controller.particles.length, lessThanOrEqualTo(particleCount));
    });
  });

  group('波次与 Boss', () {
    test('每 4 波出现 Boss 波', () {
      final director = WaveDirector(seed: 7);
      final bossWaves = <int>[];
      for (var i = 0; i < 8; i++) {
        director.startNextWave();
        if (director.bossWave) bossWaves.add(director.wave);
        // 清空生成队列，避免影响下一波。
        while (director.spawning) {
          director.update(10);
        }
      }
      expect(bossWaves, [4, 8]);
    });

    test('Boss 入场后循环发射弹幕', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      final boss = Enemy(
        kind: EnemyKind.boss,
        pattern: EnemyPattern.hover,
        x: 200,
        y: -60,
        difficulty: 1,
      );
      controller.enemies.add(boss);
      advance(controller, 3.2);
      expect(boss.entered, isTrue);
      expect(controller.enemyBullets, isNotEmpty);
      expect(controller.bossHpRatio, greaterThan(0));
    });

    test('第 8 波为利维坦，入场后发射等离子弹幕', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.wave = 8;
      expect(controller.bossVariant, BossVariant.leviathan);
      expect(controller.bossName, '深渊利维坦');

      final boss = Enemy(
        kind: EnemyKind.boss,
        pattern: EnemyPattern.hover,
        x: 200,
        y: -60,
        difficulty: 1,
        variant: BossVariant.leviathan,
      );
      controller.enemies.add(boss);
      advance(controller, 3.2);
      expect(boss.entered, isTrue);
      expect(controller.enemyBullets, isNotEmpty);
      expect(
        controller.enemyBullets.every(
          (bullet) => bullet.kind == BulletKind.plasma,
        ),
        isTrue,
      );
    });

    test('第 12 波为幽影方舟，入场后发射相位弹幕', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.wave = 12;
      expect(controller.bossVariant, BossVariant.wraith);
      expect(controller.bossName, '幽影方舟');

      final boss = Enemy(
        kind: EnemyKind.boss,
        pattern: EnemyPattern.hover,
        x: 200,
        y: -60,
        difficulty: 1,
        variant: BossVariant.wraith,
      );
      controller.enemies.add(boss);
      advance(controller, 3.2);
      expect(boss.entered, isTrue);
      expect(controller.enemyBullets, isNotEmpty);
      expect(
        controller.enemyBullets.every(
          (bullet) => bullet.kind == BulletKind.phase,
        ),
        isTrue,
      );
    });
  });

  group('僚机', () {
    test('拾取僚机补给召唤左翼僚机并跟随玩家', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      expect(controller.player.wingmen, 0);

      controller.powerUps.add(
        PowerUp(
          x: controller.player.x,
          y: controller.player.y,
          kind: PowerUpKind.wingman,
        ),
      );
      advance(controller, 0.1);

      expect(controller.player.wingmen, 1);
      expect(controller.wingmen, hasLength(1));
      expect(controller.wingmen.single.side, -1);
      expect(controller.wingmen.single.x, lessThan(controller.player.x));
      expect(controller.wingmen.single.y, greaterThan(controller.player.y));
      expect(controller.popups.any((popup) => popup.text == '僚机就位'), isTrue);
    });

    test('最多两架僚机，满编后补给折算分数', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      for (var i = 0; i < 2; i++) {
        controller.powerUps.add(
          PowerUp(
            x: controller.player.x,
            y: controller.player.y,
            kind: PowerUpKind.wingman,
          ),
        );
        advance(controller, 0.02);
      }
      expect(controller.player.wingmen, Player.maxWingmen);
      expect(controller.wingmen.map((wing) => wing.side), [-1, 1]);

      controller.powerUps.add(
        PowerUp(
          x: controller.player.x,
          y: controller.player.y,
          kind: PowerUpKind.wingman,
        ),
      );
      advance(controller, 0.02);
      expect(controller.player.wingmen, Player.maxWingmen);
      expect(controller.wingmen, hasLength(Player.maxWingmen));
      expect(controller.score, 250);
    });

    test('僚机自动向外侧开火', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.player.wingmen = 1;
      controller.wingmen.add(
        Wingman(
          side: 1,
          x: controller.player.x + 27,
          y: controller.player.y + 13,
        ),
      );

      advance(controller, 0.1);

      final wingShots = controller.playerBullets
          .where((bullet) => bullet.x > controller.player.x + 20)
          .toList();
      expect(wingShots, isNotEmpty);
      expect(wingShots.every((bullet) => bullet.vx > 0), isTrue);
      expect(wingShots.every((bullet) => bullet.vy < 0), isTrue);
    });

    test('重新开始清空僚机', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.player.wingmen = 1;
      controller.wingmen.add(
        Wingman(side: -1, x: controller.player.x, y: controller.player.y),
      );

      controller.start();

      expect(controller.player.wingmen, 0);
      expect(controller.wingmen, isEmpty);
    });
  });

  group('世界尺寸', () {
    test('缩放窗口后玩家仍在战场内', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.resize(const Size(400, 900));
      expect(controller.size.height, 900);
      expect(controller.player.y, lessThanOrEqualTo(900 - 26));
      expect(controller.stars, isNotEmpty);
    });
  });

  group('HUD 刷新', () {
    test('开场提示结束后，数值没变化就不再按 10Hz 通知', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      // 停止开火与拾取，让得分、生命、火力保持不变。
      controller.player.alive = false;

      advance(controller, 7);
      notifications = 0;
      advance(controller, 1);

      // 旧的实现 1 秒固定通知 10 次；现在只有波次推进等真实变化才通知。
      expect(notifications, lessThanOrEqualTo(3));
    });

    test('开场 6 秒内提示需要持续淡出，保持刷新', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.player.alive = false;

      advance(controller, 1);

      expect(notifications, greaterThanOrEqualTo(8));
    });

    test('Boss 战期间数值不变时不再按 10Hz 重建整个 HUD', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      controller.enemies.add(
        Enemy(
          kind: EnemyKind.boss,
          pattern: EnemyPattern.hover,
          x: 200,
          y: -60,
          difficulty: 1,
        ),
      );
      // 保持无敌，避免 Boss 弹幕命中改变生命值而触发通知。
      controller.player.invuln = 999;
      advance(controller, 7);
      var notifications = 0;
      controller.addListener(() => notifications++);

      advance(controller, 1);

      // 旧实现只要 Boss 在场就固定通知 10 次。
      expect(notifications, lessThanOrEqualTo(3));
    });

    test('Boss 血量通过独立通知器更新，不依赖 HUD 重建', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      final boss = Enemy(
        kind: EnemyKind.boss,
        pattern: EnemyPattern.hover,
        x: 200,
        y: 100,
        difficulty: 1,
      );
      controller.enemies.add(boss);
      controller.player.invuln = 999;
      advance(controller, 0.2);
      expect(controller.bossHp.value, 1000);

      final samples = <int>[];
      controller.bossHp.addListener(() => samples.add(controller.bossHp.value));
      boss.hp = boss.maxHp * 0.5;
      advance(controller, 0.3);

      expect(samples, isNotEmpty);
      expect(samples.last, closeTo(500, 5));
    });

    test('Boss 被击破时血条立即归零并通知界面', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      final boss = Enemy(
        kind: EnemyKind.boss,
        pattern: EnemyPattern.hover,
        x: 200,
        y: 120,
        difficulty: 1,
      )..entered = true;
      boss.hp = 1;
      controller.enemies.add(boss);
      controller.playerBullets.add(
        Bullet(
          x: 200,
          y: 128,
          vx: 0,
          vy: -560,
          radius: 3.4,
          damage: 10,
          fromPlayer: true,
        ),
      );

      advance(controller, 0.03);

      expect(controller.boss, isNull);
      expect(controller.bossHp.value, 0);
    });

    test('同一步击破多架敌机只在 10Hz 刷新时合并通知', () {
      final controller = buildController();
      addTearDown(controller.dispose);
      for (var i = 0; i < 5; i++) {
        final enemy = Enemy(
          kind: EnemyKind.scout,
          pattern: EnemyPattern.straight,
          x: 100 + i * 20,
          y: 120,
          difficulty: 1,
        );
        controller.enemies.add(enemy);
        controller.playerBullets.add(
          Bullet(
            x: enemy.x,
            y: 128,
            vx: 0,
            vy: -560,
            radius: 3.4,
            damage: 10,
            fromPlayer: true,
          ),
        );
      }
      var notifications = 0;
      controller.addListener(() => notifications++);

      // 首个逻辑步远早于第一次 HUD 刷新周期，击破不应逐个通知。
      controller.update(1 / 60);
      expect(controller.kills, 5);
      expect(notifications, 0);

      advance(controller, 0.2);
      expect(notifications, greaterThanOrEqualTo(1));
      expect(notifications, lessThanOrEqualTo(3));
    });
  });
}
