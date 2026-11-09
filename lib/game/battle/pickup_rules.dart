import 'dart:math' as math;

import 'battle_tuning.dart';
import 'battle_types.dart';

/// 拾取补给后需要反馈给界面的结果。
///
/// 补给对玩家数值的改变由 [applyPickup] 完成，提示文案、配色与加分一并返回，
/// 战斗控制器只负责生成飘字与僚机实体，不再维护一长串拾取分支。
class PickupOutcome {
  const PickupOutcome({
    required this.text,
    this.color,
    this.score = 0,
    this.spawnWingman = false,
  });

  final String text;
  final int? color;
  final int score;
  final bool spawnWingman;
}

/// 把 [kind] 补给作用到 [player] 上，返回提示与加分。
///
/// 满级后的火力、炸弹与僚机补给折算成分数，公式与数值全部取自
/// `battle_tuning`，玩法说明和逻辑共用同一份上限。
PickupOutcome applyPickup(
  PowerUpKind kind,
  Player player, {
  required int multiplier,
  WeaponRoute? route,
}) {
  switch (kind) {
    case PowerUpKind.core:
      if (player.weaponLevel < Player.maxWeaponLevel) {
        return applyPickup(PowerUpKind.weapon, player, multiplier: multiplier);
      }
      final chosen = route ?? WeaponRoute.fan;
      final spec = kWeaponRoutes[chosen]!;
      if (player.overdrive > 0 && player.route != chosen) {
        player.route = chosen;
        player.overdrive = math.max(1, player.overdrive - 1);
        return PickupOutcome(text: '转向 ${spec.label}', color: spec.argb);
      }
      if (player.overdrive == Player.maxOverdrive) {
        return const PickupOutcome(
          text: '+$kCoreCapScore',
          score: kCoreCapScore,
        );
      }
      player.route = chosen;
      player.overdrive++;
      return PickupOutcome(
        text: '${spec.label}进化 ${player.overdrive == 1 ? 'Ⅰ' : 'Ⅱ'}',
        color: spec.argb,
      );
    case PowerUpKind.weapon:
      if (player.weaponLevel < Player.maxWeaponLevel) {
        player.weaponLevel++;
        return PickupOutcome(text: '火力 ${player.weaponLevel} 级');
      }
      return const PickupOutcome(
        text: '+$kWeaponCapScore',
        score: kWeaponCapScore,
      );
    case PowerUpKind.shield:
      player.shield = player.shield > kShieldPickupDuration
          ? player.shield
          : kShieldPickupDuration;
      return const PickupOutcome(text: '护盾展开', color: 0xFF7FD8FF);
    case PowerUpKind.bomb:
      if (player.bombs < Player.maxBombs) {
        player.bombs++;
        return const PickupOutcome(text: '炸弹 +1', color: 0xFFFF6B6B);
      }
      return const PickupOutcome(text: '+$kBombCapScore', score: kBombCapScore);
    case PowerUpKind.star:
      final gain = kStarPickupScore * multiplier;
      return PickupOutcome(text: '+$gain', score: gain);
    case PowerUpKind.rapid:
      final target = player.rapid + kRapidPickupDuration;
      player.rapid = target > kRapidMaxDuration ? kRapidMaxDuration : target;
      return const PickupOutcome(text: '急速射击', color: 0xFFFFE082);
    case PowerUpKind.wingman:
      if (player.wingmen < Player.maxWingmen) {
        player.wingmen++;
        return PickupOutcome(
          text: player.wingmen == Player.maxWingmen ? '护卫卫星就位' : '僚机就位',
          color: 0xFF9BFFEA,
          spawnWingman: true,
        );
      }
      return const PickupOutcome(
        text: '+$kWingmanCapScore',
        score: kWingmanCapScore,
      );
  }
}

/// 掉落账本：统一维护通用补给与炸弹保底。
class DropLedger {
  int pity = 0, bombPity = 0, eliteKills = 0;

  /// 距上次核心掉落的非 Boss 击破数；新局立即就绪。
  int coreKills = kCoreCooldownKills;

  void clearRun() {
    reset();
    coreKills = kCoreCooldownKills;
  }

  /// 随机池不含核心；满级武器掉落在波次和击破冷却均满足时转化。
  PowerUpKind resolveDrop(
    PowerUpKind kind,
    Player player, {
    required int wave,
  }) {
    if (kind == PowerUpKind.weapon &&
        wave >= kOverdriveFromWave &&
        player.weaponLevel == Player.maxWeaponLevel &&
        player.overdrive < Player.maxOverdrive &&
        coreKills >= kCoreCooldownKills) {
      coreKills = 0;
      return PowerUpKind.core;
    }
    return kind;
  }

  void reset() {
    pity = 0;
    bombPity = 0;
    eliteKills = 0;
  }

  /// 非 Boss 击破固定传入两次抽签，保底不改变随机数消耗。
  PowerUpKind? rollKill({
    required EnemyKind kind,
    required int wave,
    required Player player,
    required double dropScale,
    required double chanceRoll,
    required double kindRoll,
  }) {
    if (coreKills < kCoreCooldownKills) coreKills++;
    bombPity++;
    if (isEliteClass(kind) && eliteKills < kEliteBombEvery) eliteKills++;
    final bombLimit = player.bombs == 0
        ? kBombPityKillsEmpty
        : kBombPityKillsHeld;
    if (player.bombs < Player.maxBombs &&
        ((isEliteClass(kind) && eliteKills >= kEliteBombEvery) ||
            bombPity >= bombLimit)) {
      reset();
      return PowerUpKind.bomb;
    }
    final pityDrop = pity >= dropPityLimitFor(wave);
    if (chanceRoll <
            (kEnemySpecs[kind]!.dropChance * dropScale).clamp(0.0, 1.0) ||
        pityDrop) {
      final result = pityDrop && player.weaponLevel < 3
          ? PowerUpKind.weapon
          : powerUpKindForRoll(kindRoll);
      pity = 0;
      if (result == PowerUpKind.bomb) reset();
      return resolveDrop(result, player, wave: wave);
    }
    pity++;
    return null;
  }

  /// 从左到右按需补给、保证炸弹、随机补给，并结清账本。
  List<PowerUpKind> bossDrops(
    Player player,
    double kindRoll, {
    int wave = kOverdriveFromWave,
  }) {
    reset();
    final left = player.weaponLevel < 5
        ? PowerUpKind.weapon
        : player.wingmen < 2
        ? PowerUpKind.wingman
        : player.weaponLevel < Player.maxWeaponLevel
        ? PowerUpKind.weapon
        : wave >= kOverdriveFromWave && player.overdrive == 0
        ? PowerUpKind.core
        : player.wingmen < Player.maxWingmen
        ? PowerUpKind.wingman
        : wave >= kOverdriveFromWave && player.overdrive < Player.maxOverdrive
        ? PowerUpKind.core
        : PowerUpKind.shield;
    if (left == PowerUpKind.core) coreKills = 0;
    return [
      left,
      player.bombs < Player.maxBombs ? PowerUpKind.bomb : PowerUpKind.shield,
      resolveDrop(powerUpKindForRoll(kindRoll), player, wave: wave),
    ];
  }
}

/// 受伤先降过载，再降基础火力；僚机数量与状态保持。
void applyHitPenalty(Player player) {
  player.resonance = math.max(0, player.resonance - kHitResonanceLoss);
  if (player.overdrive > 0) {
    player.overdrive = math.max(0, player.overdrive - kWeaponLossPerHit);
    if (player.overdrive == 0) player.route = null;
  } else {
    player.weaponLevel = math.max(1, player.weaponLevel - kWeaponLossPerHit);
  }
}
