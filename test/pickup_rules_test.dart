import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/pickup_rules.dart';

Player buildPlayer() => Player(x: 200, y: 600);

void main() {
  group('进化核心与成长不变量', () {
    for (final route in WeaponRoute.values) {
      test('$route 核心全状态表与转向代价', () {
        final p = buildPlayer()..weaponLevel = 5;
        expect(
          applyPickup(PowerUpKind.core, p, multiplier: 1, route: route).text,
          '火力 6 级',
        );
        expect(p.route, isNull);
        final first = applyPickup(
          PowerUpKind.core,
          p,
          multiplier: 1,
          route: route,
        );
        expect([p.overdrive, p.route], [1, route]);
        expect(first.text, '${kWeaponRoutes[route]!.label}进化 Ⅰ');
        expect(first.color, kWeaponRoutes[route]!.argb);
        applyPickup(PowerUpKind.core, p, multiplier: 1, route: route);
        expect(p.overdrive, 2);
        expect(
          applyPickup(PowerUpKind.core, p, multiplier: 4, route: route).score,
          400,
        );
        final other = WeaponRoute.values[(route.index + 1) % 3];
        expect(
          applyPickup(PowerUpKind.core, p, multiplier: 1, route: other).text,
          '转向 ${kWeaponRoutes[other]!.label}',
        );
        expect([p.overdrive, p.route], [1, other]);
        applyPickup(PowerUpKind.core, p, multiplier: 1, route: route);
        expect([p.overdrive, p.route], [1, route]);
      });
    }
    test('受伤按 L8 → L7 → L6 → L5，最低 1，保留僚机', () {
      final p = buildPlayer()
        ..weaponLevel = 6
        ..overdrive = 2
        ..route = WeaponRoute.focus
        ..wingmen = 3;
      for (final tier in [7, 6, 5, 4, 3, 2, 1, 1]) {
        applyHitPenalty(p);
        expect(p.fireTier, tier);
        expect(p.wingmen, 3);
        if (p.overdrive == 0) expect(p.route, isNull);
      }
    });
    test('随机拾取与受伤序列维持成长不变量', () {
      final rng = math.Random(600), p = buildPlayer();
      for (var i = 0; i < 2000; i++) {
        if (rng.nextInt(5) == 0) {
          applyHitPenalty(p);
        } else {
          applyPickup(
            PowerUpKind.values[rng.nextInt(PowerUpKind.values.length)],
            p,
            multiplier: 1,
            route: WeaponRoute.values[rng.nextInt(3)],
          );
        }
        expect(p.overdrive, inInclusiveRange(0, Player.maxOverdrive));
        expect(p.wingmen, inInclusiveRange(0, Player.maxWingmen));
        if (p.overdrive > 0) {
          expect(p.weaponLevel, Player.maxWeaponLevel);
          expect(p.route, isNotNull);
        } else {
          expect(p.route, isNull);
        }
      }
    });
    test('第三次僚机给卫星提示，第四次折分', () {
      final p = buildPlayer();
      for (var i = 0; i < 2; i++) {
        applyPickup(PowerUpKind.wingman, p, multiplier: 1);
      }
      expect(applyPickup(PowerUpKind.wingman, p, multiplier: 1).text, '护卫卫星就位');
      expect(applyPickup(PowerUpKind.wingman, p, multiplier: 1).score, 250);
      expect(p.wingmen, 3);
    });
    test('核心循环、站位顺序与随机权重不变', () {
      expect(
        [coreRouteAt(0), coreRouteAt(0.9), coreRouteAt(1.8), coreRouteAt(2.7)],
        [
          WeaponRoute.fan,
          WeaponRoute.pierce,
          WeaponRoute.focus,
          WeaponRoute.fan,
        ],
      );
      expect([for (var n = 1; n <= 3; n++) wingmanSideFor(n)], [-1, 1, 0]);
      expect(kPowerUpWeights.values.reduce((a, b) => a + b), 100);
      expect(kPowerUpWeights.containsKey(PowerUpKind.core), isFalse);
    });
  });
  group('核心掉落账本', () {
    test('转化条件与三十次击破冷却', () {
      final p = buildPlayer()..weaponLevel = 6;
      final ledger = DropLedger();
      for (var wave = 1; wave < 5; wave++) {
        expect(
          ledger.resolveDrop(PowerUpKind.weapon, p, wave: wave),
          PowerUpKind.weapon,
        );
      }
      p.weaponLevel = 5;
      expect(
        ledger.resolveDrop(PowerUpKind.weapon, p, wave: 5),
        PowerUpKind.weapon,
      );
      p
        ..weaponLevel = 6
        ..overdrive = 2
        ..route = WeaponRoute.fan;
      expect(
        ledger.resolveDrop(PowerUpKind.weapon, p, wave: 5),
        PowerUpKind.weapon,
      );
      p
        ..overdrive = 0
        ..route = null;
      expect(
        ledger.resolveDrop(PowerUpKind.weapon, p, wave: 5),
        PowerUpKind.core,
      );
      expect(ledger.coreKills, 0);
      for (var n = 1; n <= 30; n++) {
        final result = ledger.rollKill(
          kind: EnemyKind.scout,
          wave: 5,
          player: p,
          dropScale: 1,
          chanceRoll: 0,
          kindRoll: 0,
        );
        expect(result, n == 30 ? PowerUpKind.core : PowerUpKind.weapon);
      }
      expect(ledger.coreKills, 0);
    });
    test('炸弹/reset 保留核心计数，clearRun 设为就绪且计数封顶', () {
      final ledger = DropLedger()..coreKills = 4;
      ledger.reset();
      expect(ledger.coreKills, 4);
      ledger.rollKill(
        kind: EnemyKind.scout,
        wave: 5,
        player: buildPlayer(),
        dropScale: 1,
        chanceRoll: 0,
        kindRoll: 0.55,
      );
      expect([ledger.bombPity, ledger.eliteKills, ledger.coreKills], [0, 0, 5]);
      ledger.clearRun();
      expect(ledger.coreKills, kCoreCooldownKills);
      ledger.rollKill(
        kind: EnemyKind.scout,
        wave: 5,
        player: buildPlayer(),
        dropScale: 1,
        chanceRoll: 1,
        kindRoll: 0,
      );
      expect(ledger.coreKills, kCoreCooldownKills);
    });
    test('Boss 七级按需链与左右核心去重', () {
      final p = buildPlayer(), ledger = DropLedger();
      PowerUpKind left() => ledger.bossDrops(p, 0.99, wave: 8).first;
      expect(left(), PowerUpKind.weapon);
      p.weaponLevel = 5;
      expect(left(), PowerUpKind.wingman);
      p.wingmen = 2;
      expect(left(), PowerUpKind.weapon);
      p.weaponLevel = 6;
      final drops = ledger.bossDrops(p, 0, wave: 8);
      expect(drops, [PowerUpKind.core, PowerUpKind.bomb, PowerUpKind.weapon]);
      expect(ledger.coreKills, 0);
      p
        ..overdrive = 1
        ..route = WeaponRoute.fan;
      expect(left(), PowerUpKind.wingman);
      p.wingmen = 3;
      expect(left(), PowerUpKind.core);
      p.overdrive = 2;
      expect(left(), PowerUpKind.shield);
      p
        ..overdrive = 0
        ..route = null;
      for (var wave = 1; wave < 5; wave++) {
        expect(
          ledger.bossDrops(p, 0, wave: wave),
          isNot(contains(PowerUpKind.core)),
        );
      }
    });
    test('固定种子第 5–12 波核心总数与可复现性', () {
      List<PowerUpKind> script() {
        final rng = math.Random(503), ledger = DropLedger();
        final p = buildPlayer()
          ..weaponLevel = 6
          ..wingmen = 2;
        final drops = <PowerUpKind>[];
        for (var wave = 5; wave <= 12; wave++) {
          for (var i = 0; i < 16; i++) {
            final kind = ledger.rollKill(
              kind: EnemyKind.scout,
              wave: wave,
              player: p,
              dropScale: 1,
              chanceRoll: rng.nextDouble(),
              kindRoll: rng.nextDouble(),
            );
            if (kind != null) drops.add(kind);
          }
          if (wave % 4 == 0) {
            drops.addAll(ledger.bossDrops(p, rng.nextDouble(), wave: wave));
          }
        }
        return drops;
      }

      final drops = script();
      expect(script(), drops);
      expect(
        drops.where((k) => k == PowerUpKind.core).length,
        inInclusiveRange(2, 5),
      );
    });
  });

  group('掉落账本', () {
    PowerUpKind? roll(
      DropLedger ledger,
      Player player, {
      EnemyKind kind = EnemyKind.scout,
      int wave = 3,
      double scale = 1,
      double chance = 1,
      double item = 0.99,
    }) => ledger.rollKill(
      kind: kind,
      wave: wave,
      player: player,
      dropScale: scale,
      chanceRoll: chance,
      kindRoll: item,
    );

    test('未触发掉落时累计，重置清空全部计数', () {
      final ledger = DropLedger(), player = buildPlayer();
      expect(roll(ledger, player), isNull);
      expect([ledger.pity, ledger.bombPity, ledger.eliteKills], [1, 1, 0]);
      ledger.reset();
      expect([ledger.pity, ledger.bombPity, ledger.eliteKills], [0, 0, 0]);
    });
    test('早期与常规通用保底按需补火力', () {
      for (final wave in [1, 2, 3, 12]) {
        final ledger = DropLedger(), player = buildPlayer();
        final limit = wave <= 2 ? 10 : 20;
        for (var i = 0; i < limit; i++) {
          expect(roll(ledger, player, wave: wave), isNull);
        }
        expect(roll(ledger, player, wave: wave), PowerUpKind.weapon);
        expect(ledger.pity, 0);
        ledger.pity = limit;
        player.weaponLevel = 3;
        expect(roll(ledger, player, wave: wave), PowerUpKind.wingman);
      }
    });
    test('精英堡垒共用四次保底，普通敌机不计入', () {
      final ledger = DropLedger(), player = buildPlayer();
      roll(ledger, player);
      expect(ledger.eliteKills, 0);
      for (final kind in [
        EnemyKind.elite,
        EnemyKind.fortress,
        EnemyKind.elite,
      ]) {
        expect(roll(ledger, player, kind: kind), isNull);
      }
      expect(roll(ledger, player, kind: EnemyKind.fortress), PowerUpKind.bomb);
      expect([ledger.pity, ledger.bombPity, ledger.eliteKills], [0, 0, 0]);
    });
    test('满额保留精英与炸弹保底，空位出现后兑现', () {
      final ledger = DropLedger(),
          player = buildPlayer()..bombs = Player.maxBombs;
      for (var i = 0; i < 6; i++) {
        roll(ledger, player, kind: EnemyKind.elite);
      }
      expect(ledger.eliteKills, kEliteBombEvery);
      player.bombs--;
      expect(roll(ledger, player, kind: EnemyKind.elite), PowerUpKind.bomb);
      player.bombs = Player.maxBombs;
      ledger.bombPity = kBombPityKillsHeld;
      expect(roll(ledger, player), isNull);
      expect(ledger.bombPity, greaterThan(kBombPityKillsHeld));
      player.bombs--;
      expect(roll(ledger, player), PowerUpKind.bomb);
    });
    test('无弹二十四次，有弹四十八次；通用掉落不打断炸弹计数', () {
      for (final bombs in [0, 1]) {
        final ledger = DropLedger(), player = buildPlayer()..bombs = bombs;
        final limit = bombs == 0 ? kBombPityKillsEmpty : kBombPityKillsHeld;
        for (var i = 1; i < limit; i++) {
          expect(roll(ledger, player), isNot(PowerUpKind.bomb));
        }
        expect(roll(ledger, player), PowerUpKind.bomb);
        expect(ledger.bombPity, 0);
      }
    });
    test('补给管制只缩放随机掉率，全部保底保持有效', () {
      final ledger = DropLedger(), player = buildPlayer();
      expect(roll(ledger, player, chance: 0.03, scale: 0.62), isNull);
      expect(roll(DropLedger(), player, chance: 0.03), PowerUpKind.wingman);
      ledger.pity = kDropPityLimit;
      expect(roll(ledger, player, scale: 0.62), PowerUpKind.weapon);
      ledger.eliteKills = 3;
      expect(
        roll(ledger, player, kind: EnemyKind.elite, scale: 0.62),
        PowerUpKind.bomb,
      );
      player.bombs = 0;
      ledger.bombPity = 23;
      expect(roll(ledger, player, scale: 0.62), PowerUpKind.bomb);
    });
    test('随机炸弹同样清空账本，满库存拾取只折分', () {
      final ledger = DropLedger()
        ..bombPity = 12
        ..eliteKills = 2;
      final player = buildPlayer();
      expect(roll(ledger, player, chance: 0, item: 0.55), PowerUpKind.bomb);
      expect([ledger.pity, ledger.bombPity, ledger.eliteKills], [0, 0, 0]);
      player.bombs = Player.maxBombs;
      final outcome = applyPickup(PowerUpKind.bomb, player, multiplier: 1);
      expect(player.bombs, Player.maxBombs);
      expect(outcome.score, kBombCapScore);
    });
    test('Boss 左侧按需、中间炸弹、右侧随机并清空计数', () {
      final ledger = DropLedger()
        ..pity = 7
        ..bombPity = 19
        ..eliteKills = 3;
      final player = buildPlayer();
      expect(ledger.bossDrops(player, 0.99), [
        PowerUpKind.weapon,
        PowerUpKind.bomb,
        PowerUpKind.wingman,
      ]);
      expect([ledger.pity, ledger.bombPity, ledger.eliteKills], [0, 0, 0]);
      player.weaponLevel = 5;
      expect(ledger.bossDrops(player, 0).first, PowerUpKind.wingman);
      player.weaponLevel = 6;
      player.overdrive = 2;
      player.route = WeaponRoute.fan;
      player.wingmen = Player.maxWingmen;
      player.bombs = Player.maxBombs;
      expect(ledger.bossDrops(player, 0), [
        PowerUpKind.shield,
        PowerUpKind.shield,
        PowerUpKind.weapon,
      ]);
    });
    test('固定种子四波周期炸弹供给处于预期范围', () {
      for (final startWave in [5, 9]) {
        final rng = math.Random(503), ledger = DropLedger();
        final player = buildPlayer()
          ..weaponLevel = 6
          ..bombs = 1;
        var bombs = 0;
        const cycles = 500;
        for (var cycle = 0; cycle < cycles; cycle++) {
          for (var wave = startWave; wave < startWave + 4; wave++) {
            if (wave == startWave + 3) {
              bombs += ledger
                  .bossDrops(player, rng.nextDouble())
                  .where((k) => k == PowerUpKind.bomb)
                  .length;
            } else {
              final script = [
                for (var i = 0; i < 10; i++) EnemyKind.scout,
                EnemyKind.fighter,
                EnemyKind.fighter,
                EnemyKind.bomber,
                EnemyKind.drone,
                EnemyKind.drone,
                EnemyKind.elite,
                if (startWave >= 9) EnemyKind.fortress,
              ];
              for (final kind in script) {
                if (roll(
                      ledger,
                      player,
                      kind: kind,
                      wave: wave,
                      chance: rng.nextDouble(),
                      item: rng.nextDouble(),
                    ) ==
                    PowerUpKind.bomb) {
                  bombs++;
                }
              }
            }
          }
        }
        expect(bombs / cycles, inInclusiveRange(1.5, 3.5));
      }
    });
  });

  group('火力补给', () {
    test('未满级时提升一级并提示当前等级', () {
      final player = buildPlayer();
      final outcome = applyPickup(PowerUpKind.weapon, player, multiplier: 1);
      expect(player.weaponLevel, 2);
      expect(outcome.text, '火力 2 级');
      expect(outcome.score, 0);
    });

    test('满级后折算成分数', () {
      final player = buildPlayer()..weaponLevel = Player.maxWeaponLevel;
      final outcome = applyPickup(PowerUpKind.weapon, player, multiplier: 4);
      expect(player.weaponLevel, Player.maxWeaponLevel);
      expect(outcome.score, kWeaponCapScore);
      expect(outcome.text, '+$kWeaponCapScore');
    });
  });

  group('护盾、炸弹与急速', () {
    test('护盾取较长剩余时间，不会缩短已有护盾', () {
      final player = buildPlayer()..shield = kShieldPickupDuration + 3;
      applyPickup(PowerUpKind.shield, player, multiplier: 1);
      expect(player.shield, kShieldPickupDuration + 3);

      final fresh = buildPlayer();
      applyPickup(PowerUpKind.shield, fresh, multiplier: 1);
      expect(fresh.shield, kShieldPickupDuration);
    });

    test('炸弹上限内补充，满额后折算分数', () {
      final player = buildPlayer()..bombs = 1;
      applyPickup(PowerUpKind.bomb, player, multiplier: 1);
      expect(player.bombs, 2);

      player.bombs = Player.maxBombs;
      final outcome = applyPickup(PowerUpKind.bomb, player, multiplier: 1);
      expect(player.bombs, Player.maxBombs);
      expect(outcome.score, kBombCapScore);
    });

    test('急速补给累加且不超过上限', () {
      final player = buildPlayer();
      applyPickup(PowerUpKind.rapid, player, multiplier: 1);
      expect(player.rapid, kRapidPickupDuration);

      player.rapid = kRapidMaxDuration - 1;
      applyPickup(PowerUpKind.rapid, player, multiplier: 1);
      expect(player.rapid, kRapidMaxDuration);
    });
  });

  group('分数与僚机', () {
    test('分数补给按连击倍率结算', () {
      final player = buildPlayer();
      final outcome = applyPickup(PowerUpKind.star, player, multiplier: 3);
      expect(outcome.score, kStarPickupScore * 3);
      expect(outcome.text, '+${kStarPickupScore * 3}');
    });

    test('僚机未满编时请求生成僚机', () {
      final player = buildPlayer();
      final outcome = applyPickup(PowerUpKind.wingman, player, multiplier: 1);
      expect(player.wingmen, 1);
      expect(outcome.spawnWingman, isTrue);
    });

    test('僚机满编后折算分数且不再生成', () {
      final player = buildPlayer()..wingmen = Player.maxWingmen;
      final outcome = applyPickup(PowerUpKind.wingman, player, multiplier: 1);
      expect(player.wingmen, Player.maxWingmen);
      expect(outcome.spawnWingman, isFalse);
      expect(outcome.score, kWingmanCapScore);
    });
  });

  test('所有补给类型都有可展示的提示', () {
    for (final kind in PowerUpKind.values) {
      final outcome = applyPickup(kind, buildPlayer(), multiplier: 1);
      expect(outcome.text, isNotEmpty, reason: '$kind 缺少提示');
    }
  });
}
