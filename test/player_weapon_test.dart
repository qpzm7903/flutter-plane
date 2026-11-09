import 'package:sky_fighter/game/battle/battle_tuning.dart';

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/player_weapon.dart';

void main() {
  const counts = [
    [13, 15],
    [9, 9],
    [5, 7],
  ];
  const totals = [
    [14, 16],
    [11, 13],
    [7, 9],
  ];
  const singles = [
    [4, 4],
    [5, 7],
    [7, 9],
  ];
  const kinds = [
    {7, 8, 9, 12},
    {7, 13},
    {8, 9, 14},
  ];
  final baseInterval = playerFireInterval(6, rapid: false);
  for (final route in WeaponRoute.values) {
    for (var tier = 1; tier <= Player.maxOverdrive; tier++) {
      test('$route 阶 $tier 弹道、汇聚几何与 DPS 护栏', () {
        final pattern = kOverdrivePatterns[route]![tier - 1];
        final total = pattern.fold<double>(0, (n, s) => n + s.damage);
        final st = pattern
            .where(
              (s) =>
                  (s.offsetX + math.tan(s.angle) * 300).abs() <= 18 + s.radius,
            )
            .fold<double>(0, (n, s) => n + s.damage);
        final interval = playerFireInterval(6, rapid: false, route: route);
        expect(pattern, hasLength(counts[route.index][tier - 1]));
        expect(total, totals[route.index][tier - 1]);
        expect(st, singles[route.index][tier - 1]);
        expect(pattern.map((s) => s.kind).toSet(), kinds[route.index]);
        expect(
          interval,
          closeTo(
            baseInterval * kWeaponRoutes[route]!.fireIntervalScale,
            1e-10,
          ),
        );
        expect(
          playerFireInterval(6, rapid: true, route: route),
          closeTo(interval * kRapidFireIntervalScale, 1e-10),
        );
        expect(
          st / interval,
          inInclusiveRange(4 / baseInterval, 8 / baseInterval),
        );
        expect(total / interval, lessThanOrEqualTo(10 / baseInterval * 1.9));
        expect(pattern.every((s) => s.pierce <= kMaxPierce), isTrue);
        for (final shot in pattern.where(
          (s) => s.kind == BulletKind.focusBolt,
        )) {
          expect(
            (shot.offsetX + math.tan(shot.angle) * 300).abs(),
            lessThan(1),
          );
          expect(shot.offsetX * shot.angle, lessThan(0));
        }
        final p = Player(x: 200, y: 600)
          ..weaponLevel = 6
          ..route = route
          ..overdrive = tier;
        expect(buildPlayerShots(p), hasLength(pattern.length));
        if (tier == 2) {
          final previous = singles[route.index][0] / interval;
          expect(
            st / interval,
            route == WeaponRoute.fan ? previous : greaterThan(previous),
          );
        }
      });
    }
  }
  test('无过载与低等级使用基础表，散射二阶全部扇弹可穿透', () {
    final p = Player(x: 200, y: 600)
      ..weaponLevel = 6
      ..route = WeaponRoute.fan;
    expect(buildPlayerShots(p), hasLength(9));
    p
      ..weaponLevel = 3
      ..overdrive = 2;
    expect(buildPlayerShots(p), hasLength(4));
    expect(
      kOverdrivePatterns[WeaponRoute.fan]![1]
          .where((s) => s.kind == BulletKind.fanBolt)
          .every((s) => s.pierce == 1),
      isTrue,
    );
  });

  test('六级弹种、伤害、穿透与名义火力符合配置', () {
    const counts = [1, 2, 4, 5, 7, 9];
    const damage = [1, 2, 4, 6, 8, 10];
    const kinds = [
      {0},
      {6},
      {6, 7},
      {6, 7, 8},
      {6, 7, 8},
      {7, 8, 9},
    ];
    var previous = 0.0;
    for (var level = 1; level <= 6; level++) {
      final shots = buildPlayerShots(
        Player(x: 200, y: 600)..weaponLevel = level,
      );
      expect(shots, hasLength(counts[level - 1]));
      expect(shots.map((b) => b.kind).toSet(), kinds[level - 1]);
      final total = shots.fold<double>(0, (sum, b) => sum + b.damage);
      expect(total, damage[level - 1]);
      final dps = total / playerFireInterval(level, rapid: false);
      expect(dps, greaterThan(previous));
      previous = dps;
      if (level < firstPiercingLevel()) {
        expect(shots.every((b) => b.pierce == 0), isTrue);
      } else {
        expect(
          shots.any((b) => b.x == 200 && b.pierce == 1 && b.damage == 2),
          isTrue,
        );
      }
    }
    expect(firstPiercingLevel(), 4);
    expect(previous, lessThanOrEqualTo(9 / 0.11 * 1.25));
  });
  test('左右僚机弹种与伤害半径来自各自配置', () {
    for (final side in [-1, 1]) {
      final wing = Wingman(side: side, x: 100, y: 200);
      expect(wing.role, side < 0 ? WingmanRole.gale : WingmanRole.heavy);
      final spec = kWingmanSpecs[wing.role]!;
      final out = <Bullet>[];
      appendWingmanShots(wing, out);
      expect(
        out.single.kind,
        side < 0 ? BulletKind.galeBolt : BulletKind.heavyBolt,
      );
      expect(out.single.damage, spec.damage);
      expect(out.single.radius, spec.radius);
    }
  });

  group('玩家弹道', () {
    test('一级火力单发直射', () {
      final player = Player(x: 200, y: 600);
      final shots = buildPlayerShots(player);

      expect(shots, hasLength(1));
      expect(shots.single.x, 200);
      expect(shots.single.y, 584);
      expect(shots.single.vx, 0);
      expect(shots.single.vy, -kPlayerBulletSpeed);
      expect(shots.single.fromPlayer, isTrue);
    });

    test('三级火力四发且左右对称', () {
      final player = Player(x: 200, y: 600)..weaponLevel = 3;
      final shots = buildPlayerShots(player);

      expect(shots, hasLength(4));
      expect(shots.map((shot) => shot.x), containsAll([194, 206, 189, 211]));
      final left = shots.firstWhere((shot) => shot.x < 200 && shot.vx < 0);
      final right = shots.firstWhere((shot) => shot.x > 200 && shot.vx > 0);
      expect(left.vx, closeTo(-right.vx, 0.0001));
      expect(left.vy, closeTo(right.vy, 0.0001));
    });

    test('五级火力七发并保持散射速度', () {
      final player = Player(x: 200, y: 600)..weaponLevel = 5;
      final shots = buildPlayerShots(player);

      expect(shots, hasLength(7));
      for (final shot in shots) {
        expect(
          math.sqrt(shot.vx * shot.vx + shot.vy * shot.vy),
          closeTo(kPlayerBulletSpeed, 0.001),
        );
        expect(shot.vy, lessThan(0));
      }
    });

    test('六级火力九发且左右对称', () {
      final player = Player(x: 200, y: 600)
        ..weaponLevel = Player.maxWeaponLevel;
      final shots = buildPlayerShots(player);

      expect(shots, hasLength(9));
      expect(shots.map((shot) => shot.x), containsAll([191, 200, 209]));
      final left = shots.firstWhere((shot) => shot.x < 200 && shot.vx < 0);
      final right = shots.firstWhere((shot) => shot.x > 200 && shot.vx > 0);
      expect(left.vx, closeTo(-right.vx, 0.0001));
    });

    test('僚机弹道向机身外侧展开且从翼尖射出', () {
      final left = Wingman(side: -1, x: 170, y: 600);
      final right = Wingman(side: 1, x: 230, y: 600);
      final out = <Bullet>[];

      appendWingmanShots(left, out);
      appendWingmanShots(right, out);

      expect(out, hasLength(2));
      expect(out[0].x, 170);
      expect(out[0].y, 591);
      expect(out[0].vx, lessThan(0));
      expect(out[1].vx, greaterThan(0));
      expect(out.every((bullet) => bullet.vy < 0), isTrue);
      expect(out.every((bullet) => bullet.fromPlayer), isTrue);
    });

    test('等级越界时收敛到有效弹道', () {
      final low = Player(x: 200, y: 600)..weaponLevel = 0;
      expect(buildPlayerShots(low), hasLength(1));

      final high = Player(x: 200, y: 600)
        ..weaponLevel = Player.maxWeaponLevel + 3;
      expect(buildPlayerShots(high), hasLength(9));
    });

    test('追加弹道直接写入目标列表', () {
      final player = Player(x: 200, y: 600)..weaponLevel = 2;
      final out = <Bullet>[];

      appendPlayerShots(player, out);
      appendPlayerShots(player, out);

      expect(out, hasLength(4));
      expect(out.every((bullet) => bullet.fromPlayer), isTrue);
      expect(out.map((bullet) => bullet.y), everyElement(584));
    });
  });
}
