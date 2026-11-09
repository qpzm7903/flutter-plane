import 'dart:math' as math;
import 'dart:ui';

import 'battle_types.dart';

/// 战场调参表：难度曲线、边界、掉落与战斗节奏集中在这里。
///
/// 逻辑层、HUD 与玩法说明都从同一份数值出发，避免同一个公式在多处各写一遍
/// 后悄悄走样；调整手感时只需要改这一处。

// ---------------------------------------------------------------- 边界与裁剪

/// 玩家战机的可活动范围。
const double kPlayerSideMargin = 16;
const double kPlayerTopLimit = 44;
const double kPlayerBottomMargin = 26;

/// 战机在战场底部的初始高度偏移。
const double kPlayerStartBottomOffset = 84;

/// 窗口缩放后敌机允许的横向范围。
const double kEnemySideMargin = 20;

/// 敌机与 Boss 的出生高度（战场上方）。
const double kEnemySpawnY = -24;
const double kBossSpawnY = -60;

/// 越过战场边界多远后回收实体。
const double kEnemyCullMargin = 60;
const double kPlayerBulletCullMargin = 24;
const double kEnemyBulletCullMargin = 30;
const double kPowerUpCullMargin = 30;

/// 敌机开始与停止开火的纵向区间。
const double kEnemyFireMinY = 6;
const double kEnemyFireMaxRatio = 0.78;

/// 把玩家战机收拢回可活动范围；返回是否发生了位移。
///
/// 拖动、键盘与窗口缩放三条路径共用同一份边界，避免各自写一套 clamp
/// 之后出现「拖动能贴边、键盘却不行」的不一致。
bool clampPlayerToArena(Player player, Size world) {
  final x = clampDouble(
    player.x,
    kPlayerSideMargin,
    world.width - kPlayerSideMargin,
  );
  final y = clampDouble(
    player.y,
    kPlayerTopLimit,
    world.height - kPlayerBottomMargin,
  );
  final moved = x != player.x || y != player.y;
  player.x = x;
  player.y = y;
  return moved;
}

/// 把敌机收拢回战场的横向范围。
void clampEnemyToArena(Enemy enemy, Size world) {
  enemy.x = clampDouble(
    enemy.x,
    kEnemySideMargin,
    world.width - kEnemySideMargin,
  );
}

// ---------------------------------------------------------------- 难度曲线

/// 每一波带来的血量与射速修正。
const double kWaveDifficultyStep = 0.09;
const double kEarlyDifficultyStep = 0.05;
const double kLateDifficultyStep = 0.12;
const int kEarlyWaveLast = 3, kLateWaveFrom = 13;
const double kEnemyFireScaleFloor = 0.55;

/// 第 [wave] 波的敌机强度系数。
double waveDifficulty(int wave) =>
    1 +
    kEarlyDifficultyStep * (wave - 1).clamp(0, kEarlyWaveLast - 1) +
    kWaveDifficultyStep *
        (wave - kEarlyWaveLast).clamp(0, kLateWaveFrom - kEarlyWaveLast - 1) +
    kLateDifficultyStep * math.max(0, wave - kLateWaveFrom + 1);

/// 后期敌机射速加快的系数：与血量共用同一条难度曲线。
double enemyFireIntervalScale(int wave) =>
    math.max(kEnemyFireScaleFloor, 1 / math.sqrt(waveDifficulty(wave)));

// ---------------------------------------------------------------- 玩家火力

/// 火力等级每提升一级缩短的射击间隔。
const double kWeaponFireStepPerLevel = 0.008;

/// 急速射击状态下的射击间隔系数。
const double kRapidFireIntervalScale = 0.62;

/// 当前火力与急速状态下的射击间隔（秒）。
double playerFireInterval(
  int weaponLevel, {
  required bool rapid,
  WeaponRoute? route,
}) {
  final level = math.max(1, weaponLevel);
  final base =
      (kBaseFireInterval - kWeaponFireStepPerLevel * (level - 1)) *
      (route == null ? 1 : kWeaponRoutes[route]!.fireIntervalScale);
  return rapid ? base * kRapidFireIntervalScale : base;
}

// ---------------------------------------------------------------- 连击

const int kComboTier2x = 12;
const int kComboTier3x = 30;
const int kComboTier4x = 60;

/// 连击中断的静默时长。
const double kComboWindow = 2.6;

/// 连击数对应的分数倍率。
int comboMultiplier(int combo) {
  if (combo >= kComboTier4x) return 4;
  if (combo >= kComboTier3x) return 3;
  if (combo >= kComboTier2x) return 2;
  return 1;
}

// ---------------------------------------------------------------- 掉落与补给

/// 连续多少架未掉落补给后强制掉落一次。
const int kDropPityLimit = 20;

/// 开局库存与各类保底的阈值。
const int kStartBombs = 2, kEliteBombEvery = 4;
const int kBombPityKillsEmpty = 24, kBombPityKillsHeld = 48;
const int kEarlyDropWaves = 2, kEarlyDropPityLimit = 10;
const double kBossDropOffsetX = 26;

/// 随机补给权重，累计阈值由此表推导。
const Map<PowerUpKind, int> kPowerUpWeights = {
  PowerUpKind.weapon: 34,
  PowerUpKind.shield: 20,
  PowerUpKind.bomb: 8,
  PowerUpKind.star: 12,
  PowerUpKind.rapid: 14,
  PowerUpKind.wingman: 12,
};
int dropPityLimitFor(int wave) =>
    wave <= kEarlyDropWaves ? kEarlyDropPityLimit : kDropPityLimit;
bool isEliteClass(EnemyKind kind) =>
    kind == EnemyKind.elite || kind == EnemyKind.fortress;
PowerUpKind powerUpKindForRoll(double roll) {
  var total = 0;
  for (final entry in kPowerUpWeights.entries) {
    total += entry.value;
    if (roll < total / 100) return entry.key;
  }
  return PowerUpKind.wingman;
}

/// 拾取效果与满级折算分数。
const double kShieldPickupDuration = 10;
const double kRapidPickupDuration = 6;
const double kRapidMaxDuration = 12;
const int kWeaponCapScore = 300;
const int kBombCapScore = 200;
const int kStarPickupScore = 250;
const int kWingmanCapScore = 250;

// ---------------------------------------------------------------- 僚机

/// 僚机相对机身的横向与纵向站位。
const double kWingmanOffsetX = 27;
const double kWingmanOffsetY = 13;

/// 僚机追随玩家的收敛速度（越大越跟手）。
const double kWingmanFollowLerp = 11;

/// 僚机共用弹速，角色只改变节奏与弹体规格。
const double kWingmanBulletSpeed = 540;

/// 左右僚机的射击参数与入场节拍。
class WingmanSpec {
  const WingmanSpec({
    required this.fireInterval,
    required this.damage,
    required this.radius,
    required this.spreadAngle,
    required this.bulletKind,
    this.initialCooldown = 0,
  });
  final double fireInterval, damage, radius, spreadAngle, initialCooldown;
  final int bulletKind;
}

const Map<WingmanRole, WingmanSpec> kWingmanSpecs = {
  WingmanRole.gale: WingmanSpec(
    fireInterval: 0.24,
    damage: 0.8,
    radius: 2.8,
    spreadAngle: 0.06,
    bulletKind: BulletKind.galeBolt,
  ),
  WingmanRole.heavy: WingmanSpec(
    fireInterval: 0.60,
    damage: 2,
    radius: 4,
    spreadAngle: 0.04,
    bulletKind: BulletKind.heavyBolt,
    initialCooldown: 0.2,
  ),
};

// ---------------------------------------------------------------- 伤害

/// 炸弹对普通敌机与 Boss 的伤害。
const double kBombDamage = 40;
const double kBombBossDamageRatio = 0.16;

/// 与玩家机体相撞时敌机承受的伤害。
const double kRamDamage = 24;
const double kRamBossDamage = 30;

/// 受伤后的无敌时间，以及护盾破碎后的短暂无敌。
const double kHitInvuln = 2;
const double kShieldBreakInvuln = 1.1;

/// 受伤时清除身边敌弹的半径。
const double kHitClearRadius = 100;

/// 每次受伤损失的火力等级。
const int kWeaponLossPerHit = 1;

// ---------------------------------------------------------------- 战斗节奏

/// 开局等待第一波敌机的时间。
const double kFirstWaveGap = 1.2;

/// 一波清空后到下一波的间隔。
const double kBetweenWaveGap = 2.6;

/// 开场操作提示的持续时间，与 HUD 淡出时长保持一致。
const double kBattleHintDuration = 6;

/// HUD 的刷新周期（10Hz）。
const double kHudRefreshInterval = 0.1;

/// 尾焰粒子的生成间隔。
const double kPlayerTrailInterval = 0.05;

/// 射击音效的最小间隔。
const double kShootSoundInterval = 0.12;

/// 敌机受击闪白的持续时间。
const double kEnemyHitFlashDuration = 0.09;

class RouteSpec {
  const RouteSpec({
    required this.label,
    required this.glyph,
    required this.argb,
    required this.fireIntervalScale,
    required this.blurb,
  });
  final String label, glyph, blurb;
  final int argb;
  final double fireIntervalScale;
}

const kWeaponRoutes = {
  WeaponRoute.fan: RouteSpec(
    label: '散射',
    glyph: '散',
    argb: 0xFF2EF2A8,
    fireIntervalScale: 0.88,
    blurb: '扩大扇面覆盖，擅长清场；单点伤害提升有限。',
  ),
  WeaponRoute.pierce: RouteSpec(
    label: '贯穿',
    glyph: '贯',
    argb: 0xFFB8E6FF,
    fireIntervalScale: 1,
    blurb: '纵向贯穿两架普通敌机，中路重击；边路较弱。',
  ),
  WeaponRoute.focus: RouteSpec(
    label: '聚能',
    glyph: '聚',
    argb: 0xFF8C7BFF,
    fireIntervalScale: 1.2,
    blurb: '放弃覆盖，弹道向中路汇聚，擅长单点爆发。',
  ),
};
const int kOverdriveFromWave = 5, kCoreCooldownKills = 30, kCoreCapScore = 400;
const double kCoreCycleSeconds = 0.9;
WeaponRoute coreRouteAt(double age) =>
    WeaponRoute.values[(age / kCoreCycleSeconds).floor() %
        WeaponRoute.values.length];
int wingmanSideFor(int countAfterPickup) => switch (countAfterPickup) {
  1 => -1,
  2 => 1,
  _ => 0,
};
double wingmanOffsetY(WingmanRole role) =>
    role == WingmanRole.guard ? -kGuardOffsetY : kWingmanOffsetY;
const double kGuardOffsetY = 34,
    kGuardRadius = 15,
    kGuardMaxEnergy = 12,
    kGuardRegenPerSec = 0.6,
    kGuardOverheat = 6,
    kGuardRestoreEnergy = 6;

// ---- 姿态与共鸣
const int kFocusFromWave = 3,
    kGrazeFromWave = 3,
    kResonanceFromWave = 5,
    kChargeFromWave = 6;
const double kFocusHitRadius = 6.5,
    kMoveSpeedSmoothing = 12,
    kFocusEnterSpeed = 42,
    kFocusExitSpeed = 60,
    kFocusEnterDelay = 0.12,
    kFocusRiseRate = 6,
    kFocusFallRate = 9,
    kFocusKeySpeedScale = 0.45,
    kFocusSqueezeX = 0.4,
    kFocusSqueezeAngle = 0.4,
    kFocusWingmanSqueeze = 0.35;
const double kGrazeBand = 14, kGrazeTokensPerSec = 10, kGrazeBucketCapacity = 4;
const int kResonanceBulletScore = 20, kResonanceMaxConvert = 60;
const double kResonanceMax = 100,
    kResonanceCost = 100,
    kResonanceRadius = 170,
    kResonanceInvuln = 1,
    kHitResonanceLoss = 20,
    kChargeSeconds = 1.5,
    kChargeDecayPerSec = 0.6,
    kChargeLanceSpeed = 760,
    kTapMaxDuration = 0.18,
    kTapMaxTravel = 14,
    kDoubleTapWindow = 0.32;
const int kChargePierce = 99;

class ChargeSpec {
  const ChargeSpec({
    required this.angles,
    required this.damage,
    required this.radius,
    this.cutsBullets = false,
  });
  final List<double> angles;
  final double damage, radius;
  final bool cutsBullets;
}

const kChargeSpecDefault = ChargeSpec(angles: [0], damage: 14, radius: 7);
const kChargeSpecs = {
  WeaponRoute.fan: ChargeSpec(angles: [-0.15, 0, 0.15], damage: 9, radius: 5.5),
  WeaponRoute.pierce: ChargeSpec(
    angles: [0],
    damage: 14,
    radius: 6,
    cutsBullets: true,
  ),
  WeaponRoute.focus: ChargeSpec(angles: [0], damage: 26, radius: 8),
};

const double kSqueezeRiseRate = 2.5,
    kSqueezeRiseHeld = 8,
    kSqueezeFallRate = 12,
    kSqueezeSeconds = 0.4,
    kDoubleTapMaxGap = 56,
    kLancePowerPerBullet = 0.05,
    kLancePowerMax = 3.0,
    kLanceRadiusGrowth = 0.2;
const int kResonanceMinConvert = 4, kLancePowerCapBullets = 40;

class GrazeReward {
  const GrazeReward({
    required this.resonance,
    required this.score,
    required this.comboExtend,
  });
  final double resonance, comboExtend;
  final int score;
}

const kGrazeRewardMoving = GrazeReward(
  resonance: 4,
  score: 10,
  comboExtend: 0.25,
);
const kGrazeRewardFocused = GrazeReward(
  resonance: 2,
  score: 6,
  comboExtend: 0.15,
);
GrazeReward grazeRewardFor(double focus) =>
    focus < 0.5 ? kGrazeRewardMoving : kGrazeRewardFocused;
