import 'battle_tuning.dart';
import 'battle_types.dart';
import 'boss_catalog.dart';
import 'player_weapon.dart';

/// 玩法说明文案：上限、档位与间隔全部取自调参表。
///
/// 之前这些数字在说明弹窗里各抄一遍，调整火力上限或连击档位后文案容易过期；
/// 现在数值只有一处出处，说明与实战始终保持一致。
const String kBattleInputHint = '拖动屏幕移动 · 自动开火 · 右下角释放炸弹';

/// 目标说明。
List<String> battleGoalHints() => [
  '击落一波又一波敌机，躲避弹幕并尽量保持连击。',
  '每 $kBossWaveInterval 波会遭遇一艘 Boss 母舰，击破可获得高额分数。',
  '生命耗尽即战斗结束，最高分与本局波次自动保存。',
];

/// 补给说明，按 HUD 中的常见关注顺序排列。
List<String> supplyHints() => [
  '火力：提升弹道等级，最高 ${Player.maxWeaponLevel} 级；${firstPiercingLevel()} 级起主炮可穿透一架普通敌机。',
  '进化核心：满级后出现，字样与颜色循环切换，在想要的路线上接取；同路线升阶（最多 ${Player.maxOverdrive} 阶），换路线降一阶；第 $kOverdriveFromWave 波起，Boss 按需掉落。',
  '护盾：展开能量罩，抵挡一次伤害。',
  '炸弹：补充一枚全屏炸弹，上限 ${Player.maxBombs} 枚；Boss 必出，精英机/堡垒每 $kEliteBombEvery 次击破必出，炸弹告急时另有保底。',
  '僚机：左翼疾风僚机速射、右翼重炮僚机重击，第三架为护卫卫星，吸收敌弹但会过热；最多 ${Player.maxWingmen} 架。',
  '分数：立即获得额外得分。',
  '急速：限时提升射速。',
];

/// 连击说明。
List<String> comboHints() => [
  '连续击破敌机会累积连击，'
      '$kComboTier2x / $kComboTier3x / $kComboTier4x 连击提升分数倍率。',
  '停火超过 $kComboWindow 秒连击归零，倍率最高 ×4。',
];

/// 每日挑战说明。
List<String> dailyChallengeHints() => [
  '每天刷新固定种子与战场修正，独立计分并记录今日最佳与连续天数。',
  '累计击破与成就在普通战斗和每日挑战中共同推进。',
];

List<String> routeHints() => [
  for (final route in WeaponRoute.values)
    '${kWeaponRoutes[route]!.label}：${kWeaponRoutes[route]!.blurb}',
  '受伤先降一阶过载，再降火力等级；护盾可保护过载。',
];
