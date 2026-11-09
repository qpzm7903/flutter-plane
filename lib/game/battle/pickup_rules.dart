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
}) {
  switch (kind) {
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
        return const PickupOutcome(
          text: '僚机就位',
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
      return result;
    }
    pity++;
    return null;
  }

  /// 从左到右按需补给、保证炸弹、随机补给，并结清账本。
  List<PowerUpKind> bossDrops(Player player, double kindRoll) {
    reset();
    return [
      player.weaponLevel < 5
          ? PowerUpKind.weapon
          : player.wingmen < Player.maxWingmen
          ? PowerUpKind.wingman
          : PowerUpKind.shield,
      player.bombs < Player.maxBombs ? PowerUpKind.bomb : PowerUpKind.shield,
      powerUpKindForRoll(kindRoll),
    ];
  }
}
