import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/flame/battle_visuals.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';

void main() {
  test('路线弹种显式样式与路线辉光色一致', () {
    for (final route in WeaponRoute.values) {
      final style = playerShotStyle(12 + route.index);
      expect(style, isNot(same(playerShotStyle(0))));
      expect(style.glowArgb, kWeaponRoutes[route]!.argb);
    }
    expect(playerShotStyle(BulletKind.rail).tailDots, 3);
    expect(kGuardVisual.path.getBounds().height, 12);
  });

  group('敌机外观配置', () {
    test('每种敌机都有轮廓与配色', () {
      for (final kind in EnemyKind.values) {
        final visual = kEnemyVisuals[kind];
        expect(visual, isNotNull, reason: '缺少 $kind 的外观配置');
        expect(visual!.path.getBounds().isEmpty, isFalse);
        expect(visual.coreRadius, greaterThan(0));
      }
    });

    test('Boss 轮廓比普通敌机更大', () {
      final bossBounds = kEnemyVisuals[EnemyKind.boss]!.path.getBounds();
      final scoutBounds = kEnemyVisuals[EnemyKind.scout]!.path.getBounds();
      expect(bossBounds.width, greaterThan(scoutBounds.width * 3));
      expect(bossBounds.height, greaterThan(scoutBounds.height * 3));
    });

    test('玩家与 Boss 轮廓闭合且尺寸稳定', () {
      expect(playerHullPath.getBounds().width, 28);
      expect(bossHullPath.getBounds().width, 92);
    });

    test('三种 Boss 形态都有独立外观与炮塔', () {
      for (final variant in BossVariant.values) {
        final visual = kBossVisuals[variant];
        expect(visual, isNotNull, reason: '缺少 $variant 的外观');
        expect(visual!.turrets, isNotEmpty);
        expect(visual.path.getBounds().isEmpty, isFalse);
      }
      expect(
        kBossVisuals[BossVariant.scorpion],
        same(kEnemyVisuals[EnemyKind.boss]),
      );
      expect(leviathanHullPath.getBounds().width, greaterThan(100));
      expect(kBossVisuals[BossVariant.leviathan]!.turrets, hasLength(3));
      expect(kBossVisuals[BossVariant.wraith]!.turrets, hasLength(4));
      expect(wraithHullPath.getBounds().width, greaterThan(90));
    });

    test('visualFor 按 Boss 形态与敌机类型取外观', () {
      final leviathan = Enemy(
        kind: EnemyKind.boss,
        pattern: EnemyPattern.hover,
        x: 200,
        y: 90,
        difficulty: 1,
        variant: BossVariant.leviathan,
      );
      expect(visualFor(leviathan), same(kBossVisuals[BossVariant.leviathan]));
      final fortress = Enemy(
        kind: EnemyKind.fortress,
        pattern: EnemyPattern.hover,
        x: 200,
        y: 120,
        difficulty: 1,
      );
      expect(visualFor(fortress), same(kEnemyVisuals[EnemyKind.fortress]));
    });
  });

  group('弹道与补给配色', () {
    test('敌弹外观覆盖全部非玩家弹种', () {
      expect(kEnemyBulletColors.keys, containsAll([1, 2, 3, 4, 5]));
      expect(kEnemyBulletColors.values.toSet(), hasLength(5));
    });

    test('补给配色覆盖全部类型', () {
      for (final kind in PowerUpKind.values) {
        expect(kPowerUpColors[kind], isNotNull);
      }
    });
  });

  group('敌机开火配置', () {
    test('可开火敌机都配置了弹数、弹速与散射角', () {
      for (final kind in [
        EnemyKind.fighter,
        EnemyKind.bomber,
        EnemyKind.elite,
        EnemyKind.interceptor,
        EnemyKind.fortress,
      ]) {
        final spec = kEnemySpecs[kind]!;
        expect(spec.fireCount, greaterThan(0), reason: '$kind 应能开火');
        expect(spec.bulletSpeed, greaterThan(0));
        expect(spec.fireInterval, greaterThan(0));
      }
      expect(kEnemySpecs[EnemyKind.bomber]!.fireSpread, greaterThan(0));
      expect(kEnemySpecs[EnemyKind.elite]!.fireCount, greaterThan(1));
      expect(kEnemySpecs[EnemyKind.fortress]!.fireMode, EnemyFireMode.radial);
      expect(
        kEnemySpecs[EnemyKind.fortress]!.fireCount,
        greaterThanOrEqualTo(8),
      );
    });

    test('侦察机、自爆机与 Boss 不走进普通开火分支', () {
      expect(kEnemySpecs[EnemyKind.scout]!.fireCount, 0);
      expect(kEnemySpecs[EnemyKind.drone]!.fireCount, 0);
      expect(kEnemySpecs[EnemyKind.boss]!.fireCount, 0);
    });
  });
}
