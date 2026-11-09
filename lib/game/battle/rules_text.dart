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
  '受伤会扣除 $kHitResonanceLoss 点共鸣，矛击蓄能保留。',
];

List<String> controlHints() => [
  '拖动屏幕任意位置移动战机，自动连续开火。',
  '放慢或停下手指进入凝神：判定点缩小、弹道收束。',
  '共鸣条蓄满后双击屏幕释放共鸣。',
  '点击右下角炸弹按钮，清空敌弹并重创全场敌机。',
  'Windows：方向键 / WASD 移动，Shift 凝神，空格或 B 放炸弹，R 共鸣，Esc 暂停。',
];
List<String> stanceHints() => [
  '凝神：第 $kFocusFromWave 波起，手指放慢或松开自动进入；判定点缩小至 $kFocusHitRadius，弹道与僚机向机身收束。',
  '擦弹：敌弹从判定外 $kGrazeBand 像素内掠过且未命中，得分并延长连击；运动中擦弹比凝神中更快蓄满共鸣条。',
  '共鸣：第 $kResonanceFromWave 波起，条满后双击屏幕，吞噬身边弹幕转为分数，$kResonanceInvuln 秒无敌并修复卫星。',
  '矛击：第 $kChargeFromWave 波起，凝神静止 $kChargeSeconds 秒蓄满，起手移动时射出穿透光矛；散射三束、贯穿可切割敌弹、聚能单点更重。',
];
String? systemHintForWave(int wave) {
  if (wave == kFocusFromWave) return '凝神：放慢移动，判定缩小；贴近弹幕有擦弹加分';
  if (wave == kResonanceFromWave) return '共鸣条蓄满后双击屏幕：吞噬身边弹幕';
  if (wave == kChargeFromWave) return '静止蓄力，起手移动释放矛击';
  return null;
}
