import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/pickup_rules.dart';

Player buildPlayer() => Player(x: 200, y: 600);

void main() {
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
