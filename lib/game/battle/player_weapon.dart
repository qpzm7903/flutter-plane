import 'dart:math' as math;

import 'battle_tuning.dart';
import 'battle_types.dart';

/// 单发子弹相对机身的横向偏移与发射角度（弧度，0 为正上方）。
class PlayerShot {
  const PlayerShot(
    this.offsetX,
    this.angle, {
    this.kind = BulletKind.player,
    this.damage = 1,
    this.radius = 3.4,
    this.pierce = 0,
  });
  const PlayerShot.twin(double x)
    : this(x, 0, kind: BulletKind.twin, radius: 3.2);
  const PlayerShot.needle(double x, double angle)
    : this(x, angle, kind: BulletKind.needle, radius: 3);
  const PlayerShot.lance(double x, {double damage = 2, int pierce = 1})
    : this(
        x,
        0,
        kind: BulletKind.lance,
        radius: 3.6,
        damage: damage,
        pierce: pierce,
      );
  const PlayerShot.nova(double x)
    : this(x, 0, kind: BulletKind.nova, radius: 4.2, damage: 2, pierce: 1);
  final int kind, pierce;
  final double damage, radius;

  final double offsetX;
  final double angle;
}

/// 六级弹道：等级即索引，0 级占位以便直接按等级取值。
const List<List<PlayerShot>> kPlayerWeaponPatterns = [
  [],
  [PlayerShot(0, 0)],
  [PlayerShot.twin(-5), PlayerShot.twin(5)],
  [
    PlayerShot.twin(-6),
    PlayerShot.twin(6),
    PlayerShot.needle(-11, -0.16),
    PlayerShot.needle(11, 0.16),
  ],
  [
    PlayerShot.twin(-7),
    PlayerShot.lance(0),
    PlayerShot.twin(7),
    PlayerShot.needle(-13, -0.17),
    PlayerShot.needle(13, 0.17),
  ],
  [
    PlayerShot.twin(-8),
    PlayerShot.lance(0),
    PlayerShot.twin(8),
    PlayerShot.needle(-13, -0.14),
    PlayerShot.needle(13, 0.14),
    PlayerShot.needle(-16, -0.3),
    PlayerShot.needle(16, 0.3),
  ],
  [
    PlayerShot.lance(-9, damage: 1),
    PlayerShot.nova(0),
    PlayerShot.lance(9, damage: 1),
    PlayerShot.needle(-14, -0.13),
    PlayerShot.needle(14, 0.13),
    PlayerShot.needle(-18, -0.28),
    PlayerShot.needle(18, 0.28),
    PlayerShot.needle(-21, -0.43),
    PlayerShot.needle(21, 0.43),
  ],
];

int firstPiercingLevel() => kPlayerWeaponPatterns.indexWhere(
  (shots) => shots.any((shot) => shot.pierce > 0),
);

/// 按当前火力等级生成一帧的玩家弹道。
List<Bullet> buildPlayerShots(Player player) {
  final shots = <Bullet>[];
  appendPlayerShots(player, shots);
  return shots;
}

/// 按当前火力等级把弹道追加到已有列表，战斗循环里避免每帧中转列表。
void appendPlayerShots(Player player, List<Bullet> out) {
  final level = player.weaponLevel.clamp(1, Player.maxWeaponLevel);
  final muzzleY = player.y - 16;
  for (final shot in kPlayerWeaponPatterns[level]) {
    out.add(
      Bullet(
        x: player.x + shot.offsetX,
        y: muzzleY,
        vx: math.sin(shot.angle) * kPlayerBulletSpeed,
        vy: -math.cos(shot.angle) * kPlayerBulletSpeed,
        radius: shot.radius,
        damage: shot.damage,
        kind: shot.kind,
        pierce: shot.pierce,
        fromPlayer: true,
      ),
    );
  }
}

/// 僚机的一帧弹道：左右僚机的弹道略微向外展开，避免与主机弹道重叠。
void appendWingmanShots(Wingman wingman, List<Bullet> out) {
  final spec = kWingmanSpecs[wingman.role]!;
  final angle = wingman.side * spec.spreadAngle;
  out.add(
    Bullet(
      x: wingman.x,
      y: wingman.y - 9,
      vx: math.sin(angle) * kWingmanBulletSpeed,
      vy: -math.cos(angle) * kWingmanBulletSpeed,
      radius: spec.radius,
      damage: spec.damage,
      kind: spec.bulletKind,
      fromPlayer: true,
    ),
  );
}
