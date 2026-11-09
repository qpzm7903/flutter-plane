import 'dart:ui';

import '../game/battle/battle_types.dart';
import '../game/battle/battle_tuning.dart';
import '../game/ship_geometry.dart';

export '../game/ship_geometry.dart';

/// 敌机矢量外观：机体、描边、核心颜色与轮廓路径都按类型集中声明。
///
/// 渲染层只按 [EnemyKind] 查表，不再在每个绘制分支里重复 switch，
/// 新增敌机类型时只需补充一条视觉配置。
class EnemyVisual {
  const EnemyVisual({
    required this.hull,
    required this.trim,
    required this.core,
    required this.coreRadius,
    required this.path,
    this.coreOffsetY = 0,
    this.strokeWidth = 1.4,
    this.turrets = const [],
    this.glowRadius = 20,
  });

  final Color hull;
  final Color trim;
  final Color core;
  final double coreRadius;
  final double coreOffsetY;
  final double strokeWidth;
  final Path path;

  /// 炮塔相对坐标：Boss 侧翼与重装堡垒的炮口。
  final List<Offset> turrets;
  final double glowRadius;
}

final Path bossHullPath = Path()
  ..moveTo(0, 38)
  ..lineTo(-15, 27)
  ..lineTo(-37, 19)
  ..lineTo(-46, 3)
  ..lineTo(-30, -5)
  ..lineTo(-38, -22)
  ..lineTo(-12, -14)
  ..lineTo(0, -27)
  ..lineTo(12, -14)
  ..lineTo(38, -22)
  ..lineTo(30, -5)
  ..lineTo(46, 3)
  ..lineTo(37, 19)
  ..lineTo(15, 27)
  ..close();

final Map<EnemyKind, EnemyVisual> kEnemyVisuals = {
  EnemyKind.scout: EnemyVisual(
    hull: const Color(0xFF6E2431),
    trim: const Color(0xFFFF9E6B),
    core: const Color(0xFFFFD166),
    coreRadius: 3.2,
    path: Path()
      ..moveTo(0, 12)
      ..lineTo(-11, -3)
      ..lineTo(-4, -7)
      ..lineTo(0, -3)
      ..lineTo(4, -7)
      ..lineTo(11, -3)
      ..close(),
  ),
  EnemyKind.fighter: EnemyVisual(
    hull: const Color(0xFF7C2A33),
    trim: const Color(0xFFFF7A59),
    core: const Color(0xFFFFB347),
    coreRadius: 3.2,
    path: Path()
      ..moveTo(0, 15)
      ..lineTo(-6, 3)
      ..lineTo(-16, -3)
      ..lineTo(-9, -9)
      ..lineTo(0, -5)
      ..lineTo(9, -9)
      ..lineTo(16, -3)
      ..lineTo(6, 3)
      ..close(),
  ),
  EnemyKind.bomber: EnemyVisual(
    hull: const Color(0xFF5E1F3A),
    trim: const Color(0xFFFF6B8B),
    core: const Color(0xFFFF8A80),
    coreRadius: 3.2,
    path: Path()
      ..moveTo(0, 20)
      ..lineTo(-10, 10)
      ..lineTo(-20, 3)
      ..lineTo(-14, -8)
      ..lineTo(0, -12)
      ..lineTo(14, -8)
      ..lineTo(20, 3)
      ..lineTo(10, 10)
      ..close(),
  ),
  EnemyKind.interceptor: EnemyVisual(
    hull: const Color(0xFF6B4A1E),
    trim: const Color(0xFFFFE082),
    core: const Color(0xFFFFF3C4),
    coreRadius: 2.8,
    path: Path()
      ..moveTo(0, 16)
      ..lineTo(-7, 2)
      ..lineTo(-17, -4)
      ..lineTo(-8, -9)
      ..lineTo(0, -5)
      ..lineTo(8, -9)
      ..lineTo(17, -4)
      ..lineTo(7, 2)
      ..close(),
  ),
  EnemyKind.drone: EnemyVisual(
    hull: const Color(0xFF5A2118),
    trim: const Color(0xFFFF7043),
    core: const Color(0xFFFFD180),
    coreRadius: 2.6,
    path: Path()
      ..moveTo(0, 11)
      ..lineTo(-10, 2)
      ..lineTo(-6, -8)
      ..lineTo(0, -5)
      ..lineTo(6, -8)
      ..lineTo(10, 2)
      ..close(),
  ),
  EnemyKind.fortress: EnemyVisual(
    hull: const Color(0xFF2E2450),
    trim: const Color(0xFFB388FF),
    core: const Color(0xFFE1D4FF),
    coreRadius: 6,
    coreOffsetY: 1,
    strokeWidth: 1.8,
    turrets: const [Offset(-18, 6), Offset(18, 6)],
    path: Path()
      ..moveTo(0, 24)
      ..lineTo(-12, 16)
      ..lineTo(-28, 10)
      ..lineTo(-24, -4)
      ..lineTo(-12, -8)
      ..lineTo(0, -14)
      ..lineTo(12, -8)
      ..lineTo(24, -4)
      ..lineTo(28, 10)
      ..lineTo(12, 16)
      ..close(),
  ),
  EnemyKind.elite: EnemyVisual(
    hull: const Color(0xFF5A1B4C),
    trim: const Color(0xFFFF6BC4),
    core: const Color(0xFFFF8FD1),
    coreRadius: 5.5,
    coreOffsetY: 2,
    strokeWidth: 2,
    path: Path()
      ..moveTo(0, 25)
      ..lineTo(-9, 11)
      ..lineTo(-23, 4)
      ..lineTo(-16, -7)
      ..lineTo(-20, -16)
      ..lineTo(0, -11)
      ..lineTo(20, -16)
      ..lineTo(16, -7)
      ..lineTo(23, 4)
      ..lineTo(9, 11)
      ..close(),
  ),
  EnemyKind.boss: EnemyVisual(
    hull: const Color(0xFF3A1F4F),
    trim: const Color(0xFFFF6B9D),
    core: const Color(0xFFFFD54F),
    coreRadius: 9,
    strokeWidth: 2.2,
    turrets: const [Offset(-30, 8), Offset(30, 8)],
    path: bossHullPath,
  ),
};

/// 深渊利维坦：更宽的双翼机体，冷色涂装与三联炮塔。
final Path leviathanHullPath = Path()
  ..moveTo(0, 34)
  ..lineTo(-16, 26)
  ..lineTo(-42, 20)
  ..lineTo(-52, 4)
  ..lineTo(-38, -10)
  ..lineTo(-20, -6)
  ..lineTo(-10, -22)
  ..lineTo(0, -32)
  ..lineTo(10, -22)
  ..lineTo(20, -6)
  ..lineTo(38, -10)
  ..lineTo(52, 4)
  ..lineTo(42, 20)
  ..lineTo(16, 26)
  ..close();

/// 幽影方舟：细长的紫晶舰体，四座相位炮塔向两侧展开。
final Path wraithHullPath = Path()
  ..moveTo(0, 36)
  ..lineTo(-14, 18)
  ..lineTo(-34, 22)
  ..lineTo(-50, 6)
  ..lineTo(-30, -8)
  ..lineTo(-36, -24)
  ..lineTo(-10, -16)
  ..lineTo(0, -30)
  ..lineTo(10, -16)
  ..lineTo(36, -24)
  ..lineTo(30, -8)
  ..lineTo(50, 6)
  ..lineTo(34, 22)
  ..lineTo(14, 18)
  ..close();

final Map<BossVariant, EnemyVisual> kBossVisuals = {
  BossVariant.scorpion: kEnemyVisuals[EnemyKind.boss]!,
  BossVariant.leviathan: EnemyVisual(
    hull: const Color(0xFF123A4A),
    trim: const Color(0xFF5FE3FF),
    core: const Color(0xFF9BFFEA),
    coreRadius: 10,
    strokeWidth: 2.2,
    turrets: const [Offset(-34, 12), Offset(0, 18), Offset(34, 12)],
    glowRadius: 24,
    path: leviathanHullPath,
  ),
  BossVariant.wraith: EnemyVisual(
    hull: const Color(0xFF2B1B46),
    trim: const Color(0xFFC792EA),
    core: const Color(0xFFE6D6FF),
    coreRadius: 8.5,
    strokeWidth: 2.2,
    turrets: const [
      Offset(-38, -2),
      Offset(-16, 12),
      Offset(16, 12),
      Offset(38, -2),
    ],
    glowRadius: 26,
    path: wraithHullPath,
  ),
};

/// 渲染入口：Boss 按形态取外观，其余敌机按类型取外观。
EnemyVisual visualFor(Enemy enemy) =>
    enemy.isBoss ? kBossVisuals[enemy.variant]! : kEnemyVisuals[enemy.kind]!;

const Color kPlayerHull = Color(0xFF2FA8FF);
const Color kPlayerHullShadow = Color(0xFF10306B);
const Color kPlayerTrim = Color(0xFF9BE8FF);
const Color kPlayerBulletGlow = Color(0xFF4FD1FF);
const Color kPlayerBulletBody = Color(0xFFB7F4FF);
const Color kEnemyEngineGlow = Color(0xFFFF8A5C);

const Map<int, Color> kEnemyBulletColors = {
  BulletKind.aimed: Color(0xFFFF9E6B),
  BulletKind.spread: Color(0xFFFF6BC4),
  BulletKind.boss: Color(0xFFFFD54F),
  BulletKind.plasma: Color(0xFF6BE8FF),
  BulletKind.phase: Color(0xFFC792EA),
};

/// 敌弹配色的 ARGB 整数表：批绘制直接取整数，避免逐帧构造 Color。
final Map<int, int> kEnemyBulletArgb = {
  for (final entry in kEnemyBulletColors.entries)
    entry.key: entry.value.toARGB32(),
};

/// 未知弹种回退到 Boss 弹配色，与逐颗绘制时的行为一致。
int enemyBulletArgb(int kind) =>
    kEnemyBulletArgb[kind] ?? kEnemyBulletArgb[BulletKind.boss]!;

const Map<PowerUpKind, Color> kPowerUpColors = {
  PowerUpKind.core: Color(0xFF2EF2A8),
  PowerUpKind.weapon: Color(0xFFFFB347),
  PowerUpKind.shield: Color(0xFF7FD8FF),
  PowerUpKind.bomb: Color(0xFFFF6B6B),
  PowerUpKind.star: Color(0xFFFFD54F),
  PowerUpKind.rapid: Color(0xFFFFE082),
  PowerUpKind.wingman: Color(0xFF9BFFEA),
};

/// 补给配色的 ARGB 整数表：渲染层按档位缓存颜色时直接取整数。
final Map<PowerUpKind, int> kPowerUpArgb = {
  for (final entry in kPowerUpColors.entries) entry.key: entry.value.toARGB32(),
};

/// 玩家弹三层样式，方向系数预计算，渲染热路径无需开方。
class PlayerShotStyle {
  const PlayerShotStyle(
    this.glowArgb,
    this.bodyArgb,
    this.coreArgb,
    this.glowRadius,
    this.bodyHalf,
    this.bodyWidth,
    this.coreHalf,
    this.coreWidth, {
    this.glowAlpha = 0.25,
    this.tailDots = 0,
  }) : bodyK = bodyHalf / kPlayerBulletSpeed,
       coreK = coreHalf / kPlayerBulletSpeed;
  final int glowArgb, bodyArgb, coreArgb, tailDots;
  final double glowRadius, glowAlpha, bodyHalf, bodyWidth, coreHalf, coreWidth;
  final double bodyK, coreK;
}

const _pulseStyle = PlayerShotStyle(
  0xFF4FD1FF,
  0xFFB7F4FF,
  0xFFFFFFFF,
  8,
  4,
  6,
  2.9,
  2.2,
);
const List<PlayerShotStyle> _playerShotStyles = [
  _pulseStyle,
  _pulseStyle,
  _pulseStyle,
  _pulseStyle,
  _pulseStyle,
  _pulseStyle,
  PlayerShotStyle(0xFF2ED9A0, 0xFF7CFFC4, 0xFFFFFFFF, 6, 5.5, 4.2, 4, 1.6),
  PlayerShotStyle(0xFF5C8CFF, 0xFF8FB4FF, 0xFFE6F0FF, 5.5, 4.5, 3.2, 3.2, 1.4),
  PlayerShotStyle(
    0xFF9FE8FF,
    0xFFE4FBFF,
    0xFFFFFFFF,
    10,
    11,
    5.2,
    9,
    2.2,
    glowAlpha: 0.375,
  ),
  PlayerShotStyle(
    0xFF4FD1FF,
    0xFFCFF8FF,
    0xFFFFFFFF,
    13,
    13,
    7.5,
    11,
    3.2,
    glowAlpha: 0.375,
    tailDots: 2,
  ),
  PlayerShotStyle(0xFF9BFFEA, 0xFF9BFFEA, 0xFFFFFFFF, 4.5, 3.5, 2.6, 2.4, 1.1),
  PlayerShotStyle(0xFF5C8CFF, 0xFF8FB8FF, 0xFFFFFFFF, 8, 6, 5.4, 4.5, 2),
  PlayerShotStyle(0xFF2EF2A8, 0xFF8CFFD6, 0xFFF0FFFA, 6, 6, 3.6, 4.5, 1.4),
  PlayerShotStyle(
    0xFFB8E6FF,
    0xFFF2FBFF,
    0xFFFFFFFF,
    11,
    16,
    5.4,
    14,
    2.2,
    glowAlpha: 0.375,
    tailDots: 3,
  ),
  PlayerShotStyle(
    0xFF8C7BFF,
    0xFFC4BBFF,
    0xFFFFFFFF,
    7,
    8,
    4.6,
    6,
    1.8,
    glowAlpha: 0.375,
  ),
  PlayerShotStyle(
    0xFFFFE9A8,
    0xFFFFFBEA,
    0xFFFFFFFF,
    14,
    22,
    6,
    19,
    2.2,
    glowAlpha: 0.375,
    tailDots: 3,
  ),
];
PlayerShotStyle playerShotStyle(int kind) =>
    kind >= 0 && kind < _playerShotStyles.length
    ? _playerShotStyles[kind]
    : _pulseStyle;

/// 左右翼各自的机体、描边与尾焰。
class WingmanVisual {
  const WingmanVisual(this.path, this.fill, this.trim, this.flame);
  final Path path;
  final Color fill, trim, flame;
}

final Map<WingmanRole, WingmanVisual> kWingmanVisuals = {
  WingmanRole.gale: WingmanVisual(
    wingmanHullPath,
    const Color(0xFF0E3B4F),
    const Color(0xFF9BFFEA),
    const Color(0xAA2B6BFF),
  ),
  WingmanRole.heavy: WingmanVisual(
    wingmanHeavyHullPath,
    const Color(0xFF162E52),
    const Color(0xFF8FB8FF),
    const Color(0xAA5C8CFF),
  ),
};

final kGuardVisual = WingmanVisual(
  wingmanGuardHullPath,
  const Color(0xFF0E3B4F),
  const Color(0xFF2EF2A8),
  const Color(0x00000000),
);

// Cached tiers keep heavy lances in a fixed number of batch buckets.
final _heavyLanceStyles = [
  for (final scale in [1.0, 1.2, 1.4])
    PlayerShotStyle(
      0xFFFFE9A8,
      0xFFFFFBEA,
      0xFFFFFFFF,
      14 * scale,
      22,
      6 * scale,
      19,
      2.2,
      glowAlpha: 0.375,
      tailDots: 3,
    ),
];
final _lanceVisualSpecs = [kChargeSpecDefault, ...kChargeSpecs.values];
PlayerShotStyle chargeLanceStyle(Bullet bullet) {
  var power = 1.0;
  for (final spec in _lanceVisualSpecs) {
    final candidate = bullet.damage / spec.damage;
    if ((bullet.radius -
                spec.radius * (1 + kLanceRadiusGrowth * (candidate - 1)))
            .abs() <
        0.0001) {
      power = candidate;
      break;
    }
  }
  return _heavyLanceStyles[power <= 1.5
      ? 0
      : power <= 2.5
      ? 1
      : 2];
}
