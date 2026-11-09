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
  const PlayerShot.fan(double x, double angle, {int pierce = 0})
    : this(x, angle, kind: BulletKind.fanBolt, radius: 3.6, pierce: pierce);
  const PlayerShot.rail(
    double x, {
    double damage = 1,
    double radius = 3.6,
    int pierce = 2,
  }) : this(
         x,
         0,
         kind: BulletKind.rail,
         damage: damage,
         radius: radius,
         pierce: pierce,
       );
  const PlayerShot.focus(double x, double angle, {double damage = 1})
    : this(x, angle, kind: BulletKind.focusBolt, damage: damage);
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
  _kLevel6Shots,
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
  final pattern =
      player.overdrive > 0 &&
          player.route != null &&
          level == Player.maxWeaponLevel
      ? kOverdrivePatterns[player.route]![(player.overdrive - 1).clamp(
          0,
          Player.maxOverdrive - 1,
        )]
      : kPlayerWeaponPatterns[level];
  for (final shot in pattern) {
    out.add(
      Bullet(
        x: player.x + shot.offsetX * (1 - kFocusSqueezeX * player.focus),
        y: muzzleY,
        vx:
            math.sin(shot.angle * (1 - kFocusSqueezeAngle * player.focus)) *
            kPlayerBulletSpeed,
        vy:
            -math.cos(shot.angle * (1 - kFocusSqueezeAngle * player.focus)) *
            kPlayerBulletSpeed,
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

const int kMaxPierce = 2;
const _kLevel6Needles = [
  PlayerShot.needle(-14, -0.13),
  PlayerShot.needle(14, 0.13),
  PlayerShot.needle(-18, -0.28),
  PlayerShot.needle(18, 0.28),
  PlayerShot.needle(-21, -0.43),
  PlayerShot.needle(21, 0.43),
];
const _kLevel6Shots = [
  PlayerShot.lance(-9, damage: 1),
  PlayerShot.nova(0),
  PlayerShot.lance(9, damage: 1),
  ..._kLevel6Needles,
];
const Map<WeaponRoute, List<List<PlayerShot>>> kOverdrivePatterns = {
  WeaponRoute.fan: [
    [
      ..._kLevel6Shots,
      PlayerShot.fan(-23, -0.58),
      PlayerShot.fan(23, 0.58),
      PlayerShot.fan(-27, -0.76),
      PlayerShot.fan(27, 0.76),
    ],
    [
      ..._kLevel6Shots,
      PlayerShot.fan(-23, -0.58, pierce: 1),
      PlayerShot.fan(23, 0.58, pierce: 1),
      PlayerShot.fan(-27, -0.76, pierce: 1),
      PlayerShot.fan(27, 0.76, pierce: 1),
      PlayerShot.fan(-31, -0.94, pierce: 1),
      PlayerShot.fan(31, 0.94, pierce: 1),
    ],
  ],
  WeaponRoute.pierce: [
    [
      PlayerShot.rail(-9),
      PlayerShot.rail(0, damage: 3, radius: 4.2),
      PlayerShot.rail(9),
      ..._kLevel6Needles,
    ],
    [
      PlayerShot.rail(-9, damage: 2),
      PlayerShot.rail(0, damage: 3, radius: 4.2),
      PlayerShot.rail(9, damage: 2),
      ..._kLevel6Needles,
    ],
  ],
  WeaponRoute.focus: [
    [
      PlayerShot.lance(-9, damage: 1),
      PlayerShot.nova(0),
      PlayerShot.lance(9, damage: 1),
      PlayerShot.focus(-20, 0.0666, damage: 1.5),
      PlayerShot.focus(20, -0.0666, damage: 1.5),
    ],
    [
      PlayerShot.lance(-9, damage: 1),
      PlayerShot.nova(0),
      PlayerShot.lance(9, damage: 1),
      PlayerShot.focus(-20, 0.0666, damage: 1.5),
      PlayerShot.focus(20, -0.0666, damage: 1.5),
      PlayerShot.focus(-10, 0.0333),
      PlayerShot.focus(10, -0.0333),
    ],
  ],
};

void appendChargeLance(Player player, List<Bullet> out) {
  final spec =
      kChargeSpecs[player.overdrive > 0 ? player.route : null] ??
      kChargeSpecDefault;
  for (final angle in spec.angles) {
    out.add(
      Bullet(
        x: player.x,
        y: player.y - 16,
        vx: math.sin(angle) * kChargeLanceSpeed,
        vy: -math.cos(angle) * kChargeLanceSpeed,
        radius: spec.radius,
        damage: spec.damage,
        fromPlayer: true,
        kind: BulletKind.chargeLance,
        pierce: kChargePierce,
        cuts: spec.cutsBullets,
      ),
    );
  }
}
