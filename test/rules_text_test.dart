import 'package:sky_fighter/game/battle/player_weapon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/boss_catalog.dart';
import 'package:sky_fighter/game/battle/rules_text.dart';

void main() {
  test('核心、卫星与路线说明来自统一配置', () {
    final text = supplyHints().join();
    expect(text, contains('进化核心'));
    expect(text, contains('${Player.maxOverdrive} 阶'));
    expect(text, contains('第 $kOverdriveFromWave 波'));
    expect(text, contains('护卫卫星'));
    expect(text, contains('${Player.maxWingmen} 架'));
    for (final spec in kWeaponRoutes.values) {
      expect(routeHints(), contains('${spec.label}：${spec.blurb}'));
    }
    expect(routeHints().join(), contains('护盾可保护过载'));
    expect(routeHints().last, contains('$kHitResonanceLoss'));
  });

  test('穿透与精英炸弹说明由规则推导', () {
    final text = supplyHints().join();
    expect(text, contains('${firstPiercingLevel()} 级起'));
    expect(text, contains('每 $kEliteBombEvery 次击破'));
  });

  group('玩法说明文案', () {
    test('补给说明覆盖全部类型并带上限数值', () {
      final hints = supplyHints();
      expect(hints, hasLength(PowerUpKind.values.length));
      expect(
        hints.any((line) => line.contains('${Player.maxWeaponLevel} 级')),
        isTrue,
      );
      expect(
        hints.any((line) => line.contains('${Player.maxBombs} 枚')),
        isTrue,
      );
      expect(
        hints.any((line) => line.contains('${Player.maxWingmen} 架')),
        isTrue,
      );
    });

    test('连击说明与调参表一致', () {
      final hints = comboHints().join('\n');
      expect(hints, contains('$kComboTier2x / $kComboTier3x / $kComboTier4x'));
      expect(hints, contains('$kComboWindow 秒'));
    });

    test('目标说明使用统一的 Boss 波间隔', () {
      final hints = battleGoalHints().join('\n');
      expect(hints, contains('每 $kBossWaveInterval 波'));
    });

    test('战斗内提示与玩法说明不重复维护', () {
      expect(kBattleInputHint, contains('拖动屏幕'));
      expect(kBattleInputHint, contains('炸弹'));
    });
  });
}
