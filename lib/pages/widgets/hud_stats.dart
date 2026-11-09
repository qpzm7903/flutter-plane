import 'package:flutter/material.dart';

import '../../game/battle/battle_types.dart';
import '../../game/battle/battle_tuning.dart';
import '../../theme/app_theme.dart';

/// HUD 状态条目：同一份数据同时供紧凑横条与宽屏面板渲染。
///
/// 图标、配色、短文案与完整文案只在这里定义，两套布局共用同一份结果，
/// 不会出现「横条显示 5、侧栏显示 6」这种数值不一致。
class HudStat {
  const HudStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.shortValue,
    required this.fullValue,
    this.stripIconSize = 14,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String shortValue;
  final String fullValue;
  final double stripIconSize;
}

/// 按当前战机状态生成 HUD 条目；僚机与急速只在生效时出现。
List<HudStat> hudStatsFor(Player player) => [
  HudStat(
    icon: Icons.rocket_launch_rounded,
    color: appCyan,
    label: '生命',
    shortValue: '×${player.lives}',
    fullValue: '${player.lives}',
  ),
  HudStat(
    icon: Icons.local_fire_department_rounded,
    color: appAmber,
    label: '炸弹',
    shortValue: '×${player.bombs}',
    fullValue: '${player.bombs}',
  ),
  HudStat(
    icon: Icons.bolt_rounded,
    color: player.overdrive > 0
        ? Color(kWeaponRoutes[player.route]!.argb)
        : const Color(0xFF9BE8FF),
    label: '火力',
    shortValue: player.overdrive > 0
        ? '${player.fireTier}${kWeaponRoutes[player.route]!.glyph}'
        : '${player.weaponLevel}',
    fullValue: player.overdrive > 0
        ? '${player.fireTier} 级 · ${kWeaponRoutes[player.route]!.label}'
        : '${player.weaponLevel} 级',
    stripIconSize: 15,
  ),
  if (player.wingmen > 0)
    HudStat(
      icon: Icons.flight_rounded,
      color: const Color(0xFF9BFFEA),
      label: '僚机',
      shortValue: '×${player.wingmen}',
      fullValue: '${player.wingmen} 架',
    ),
  if (player.rapid > 0)
    HudStat(
      icon: Icons.timer_rounded,
      color: const Color(0xFFFFE082),
      label: '急速',
      shortValue: '${player.rapid.ceil()}s',
      fullValue: '${player.rapid.ceil()} 秒',
    ),
];

String firepowerLabel(Player p) => p.overdrive > 0
    ? '火力 ${p.fireTier} · ${kWeaponRoutes[p.route]!.label}'
    : '火力 ${p.weaponLevel}';

class HudMeter {
  const HudMeter({
    required this.visible,
    required this.ratio,
    required this.ready,
    required this.label,
  });
  final bool visible, ready;
  final double ratio;
  final String label;
}

HudMeter resonanceMeterFor(int permille, int wave) {
  final ready = wave >= kResonanceFromWave && permille >= 1000;
  return HudMeter(
    visible: wave >= kGrazeFromWave,
    ratio: (permille / 1000).clamp(0, 1),
    ready: ready,
    label: ready ? '共鸣就绪 · 双击' : '共鸣',
  );
}
