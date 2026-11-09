import 'dart:ui';

import 'battle_tuning.dart' show kStartBombs;

/// 战场逻辑宽度：所有尺寸、速度都按这一宽度设计，渲染时整体缩放。
const double kWorldWidth = 400;

/// 玩家移动速度（键盘 / 手柄方向键）。
const double kPlayerSpeed = 300;

/// 玩家弹道速度与基础射击间隔。
const double kPlayerBulletSpeed = 560;
const double kBaseFireInterval = 0.15;

/// 敌机默认下落速度。
const double kEnemyFallSpeed = 58;

/// 战斗阶段。
enum BattlePhase { ready, playing, paused, gameOver }

/// 需要播放音效的战斗事件。
enum BattleEvent {
  shoot,
  explosion,
  bigExplosion,
  powerUp,
  playerHit,
  shieldBreak,
  bomb,
  waveStart,
  bossAppear,
  gameOver,
}

/// 敌机类型。
enum EnemyKind {
  scout,
  fighter,
  bomber,
  elite,
  interceptor,
  drone,
  fortress,
  boss,
}

/// Boss 形态：每 4 波出现一次，三种形态轮换，弹幕与机体外观各不相同。
enum BossVariant { scorpion, leviathan, wraith }

/// 各 Boss 形态的血量系数：越靠后的形态越耐打。
const Map<BossVariant, double> kBossHpScale = {
  BossVariant.scorpion: 1,
  BossVariant.leviathan: 1.15,
  BossVariant.wraith: 1.3,
};

/// 敌机移动方式。
enum EnemyPattern { straight, sine, dive, hover, chase }

/// 敌机开火方式。
enum EnemyFireMode { aimed, radial }

/// 弹道外观编号：渲染层据此选择颜色与半径。
class BulletKind {
  BulletKind._();

  static const int player = 0;
  static const int aimed = 1;
  static const int spread = 2;
  static const int boss = 3;
  static const int plasma = 4;

  /// 幽影方舟的相位弹：紫白色，配合第三种 Boss 的弹幕。
  static const int phase = 5;
  static const int twin = 6, needle = 7, lance = 8, nova = 9;
  static const int galeBolt = 10, heavyBolt = 11;
  static bool isPlayer(int kind) => kind == player || kind >= twin;
}

/// 敌机静态参数。
///
/// 开火弹道也在这里声明，新增敌机只需补充配置而无需改动开火分支。
class EnemySpec {
  const EnemySpec({
    required this.hp,
    required this.radius,
    required this.score,
    required this.dropChance,
    this.fireInterval = 2.4,
    this.fireCount = 0,
    this.fireSpread = 0,
    this.bulletSpeed = 0,
    this.bulletKind = BulletKind.aimed,
    this.fireMode = EnemyFireMode.aimed,
    this.explosionColor = 0xFFFFB347,
  });

  final double hp;
  final double radius;
  final int score;
  final double dropChance;
  final double fireInterval;

  /// 单次齐射的弹数，0 表示不会开火（如侦察机与 Boss）。
  final int fireCount;
  final double fireSpread;
  final double bulletSpeed;
  final int bulletKind;
  final EnemyFireMode fireMode;

  /// 击破时的爆炸配色，逻辑层无需再按敌机种类分支。
  final int explosionColor;
}

const Map<EnemyKind, EnemySpec> kEnemySpecs = {
  EnemyKind.scout: EnemySpec(hp: 3, radius: 11, score: 60, dropChance: 0.04),
  EnemyKind.fighter: EnemySpec(
    hp: 10,
    radius: 14,
    score: 130,
    dropChance: 0.14,
    fireInterval: 2.1,
    fireCount: 1,
    bulletSpeed: 185,
    explosionColor: 0xFFFF7A59,
  ),
  EnemyKind.bomber: EnemySpec(
    hp: 26,
    radius: 19,
    score: 280,
    dropChance: 0.3,
    fireInterval: 2.5,
    fireCount: 3,
    fireSpread: 0.22,
    bulletSpeed: 155,
    bulletKind: BulletKind.spread,
    explosionColor: 0xFFFF5252,
  ),
  EnemyKind.elite: EnemySpec(
    hp: 52,
    radius: 24,
    score: 620,
    dropChance: 0.6,
    fireInterval: 2.2,
    fireCount: 5,
    fireSpread: 0.17,
    bulletSpeed: 175,
    bulletKind: BulletKind.spread,
    explosionColor: 0xFFFF4FA3,
  ),
  EnemyKind.interceptor: EnemySpec(
    hp: 8,
    radius: 13,
    score: 190,
    dropChance: 0.16,
    fireInterval: 1.7,
    fireCount: 1,
    bulletSpeed: 300,
    explosionColor: 0xFFFFE082,
  ),
  EnemyKind.drone: EnemySpec(
    hp: 5,
    radius: 10,
    score: 100,
    dropChance: 0.05,
    explosionColor: 0xFFFF7043,
  ),
  EnemyKind.fortress: EnemySpec(
    hp: 84,
    radius: 26,
    score: 900,
    dropChance: 0.7,
    fireInterval: 2.6,
    fireCount: 10,
    bulletSpeed: 125,
    bulletKind: BulletKind.spread,
    fireMode: EnemyFireMode.radial,
    explosionColor: 0xFFB388FF,
  ),
  EnemyKind.boss: EnemySpec(
    hp: 180,
    radius: 38,
    score: 2000,
    dropChance: 1,
    fireInterval: 1.9,
    explosionColor: 0xFFFFD54F,
  ),
};

/// 玩家战机状态。
class Player {
  Player({required this.x, required this.y});

  double x;
  double y;
  int lives = startLives;
  int bombs = kStartBombs;
  int weaponLevel = 1;

  /// 护盾剩余时间（秒），大于 0 时可抵挡一次伤害。
  double shield = 0;

  /// 急速射击剩余时间（秒），大于 0 时射击间隔缩短。
  double rapid = 0;

  /// 已召唤的僚机数量，最多 [maxWingmen] 架。
  int wingmen = 0;

  /// 无敌时间（秒），受伤后短暂闪烁。
  double invuln = 0;
  double fireCooldown = 0;

  /// 左右移动带来的机身倾斜，仅用于渲染。
  double tilt = 0;
  bool alive = true;

  static const double radius = 11;
  static const int startLives = 3;
  static const int maxLives = 5;
  static const int maxBombs = 3;
  static const int maxWeaponLevel = 6;
  static const int maxWingmen = 2;
}

enum WingmanRole { gale, heavy }

/// 僚机：在玩家两侧护航并自动开火。
class Wingman {
  Wingman({required this.side, required this.x, required this.y});

  /// -1 为左翼，1 为右翼。
  final int side;
  WingmanRole get role => side < 0 ? WingmanRole.gale : WingmanRole.heavy;
  double x;
  double y;
  double cooldown = 0;
}

/// 敌机实例。
class Enemy {
  Enemy({
    required this.kind,
    required this.pattern,
    required this.x,
    required this.y,
    required this.difficulty,
    this.driftPhase = 0,
    this.variant = BossVariant.scorpion,
  }) : spec = kEnemySpecs[kind]!,
       baseX = x,
       hoverY = 96 + 46 * ((driftPhase * 7) % 1) {
    maxHp =
        spec.hp *
        difficulty *
        (kind == EnemyKind.boss ? kBossHpScale[variant]! : 1);
    hp = maxHp;
    vy = kind == EnemyKind.boss
        ? 0
        : kEnemyFallSpeed * (0.85 + 0.3 * driftPhase);
    if (pattern == EnemyPattern.dive) vy *= 1.4;
  }

  final EnemyKind kind;
  final EnemyPattern pattern;
  final EnemySpec spec;
  final double difficulty;
  final double driftPhase;
  final BossVariant variant;
  final double baseX;
  final double hoverY;

  double x;
  double y;
  double vy = 0;
  late double hp;
  late double maxHp;

  double age = 0;
  double fireCooldown = 0;
  double hitFlash = 0;

  /// Boss 专属：入场完成、当前弹幕阶段与节奏。
  bool entered = false;
  int attackPhase = 0;
  double attackTimer = 1.2;
  double hoverTimer = 0;

  bool dead = false;

  bool get isBoss => kind == EnemyKind.boss;
  double get radius => spec.radius;
  double get hpRatio => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0, 1);
}

/// 子弹：玩家与敌机共用，[kind] 决定渲染样式。
class Bullet {
  Bullet({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.damage,
    required this.fromPlayer,
    this.kind = 0,
    this.pierce = 0,
  });

  double x;
  double y;
  final double vx;
  final double vy;
  final double radius;
  final double damage;
  final bool fromPlayer;

  /// 弹种编号，敌弹与玩家各级弹道的取值见 [BulletKind]。
  final int kind;

  /// 剩余普通敌机穿透次数；上次命中引用避免跨帧重复结算。
  int pierce;
  Enemy? lastHit;
  bool dead = false;
}

/// 补给类型。
enum PowerUpKind { weapon, shield, bomb, star, rapid, wingman }

const Map<PowerUpKind, String> kPowerUpLabels = {
  PowerUpKind.weapon: '火力',
  PowerUpKind.shield: '护盾',
  PowerUpKind.bomb: '炸弹',
  PowerUpKind.star: '分数',
  PowerUpKind.rapid: '急速',
  PowerUpKind.wingman: '僚机',
};

/// 掉落的补给。
class PowerUp {
  PowerUp({required this.x, required this.y, required this.kind});

  double x;
  double y;
  final PowerUpKind kind;
  double age = 0;
  double vy = 62;
  bool dead = false;

  static const double radius = 13;
}

/// 粒子类型。
enum ParticleKind { spark, smoke, ring, debris, trail }

/// 爆炸、尾焰与拾取特效粒子。
///
/// 字段可变是为了让 [BattleEffects] 复用对象：弹幕密集时每秒钟会生成数百颗
/// 粒子，直接丢弃会让 GC 频繁介入，[reset] 把回收的粒子重新填好再用。
class Particle {
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.color,
    this.kind = ParticleKind.spark,
    this.drag = 1.6,
  }) : maxLife = life;

  double x;
  double y;
  double vx;
  double vy;
  double life;
  double maxLife;
  double size;
  int color;
  ParticleKind kind;
  double drag;

  void reset({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double life,
    required double size,
    required int color,
    required ParticleKind kind,
    required double drag,
  }) {
    this.x = x;
    this.y = y;
    this.vx = vx;
    this.vy = vy;
    this.life = life;
    maxLife = life;
    this.size = size;
    this.color = color;
    this.kind = kind;
    this.drag = drag;
  }

  bool get dead => life <= 0;
  double get progress => maxLife <= 0 ? 1 : 1 - (life / maxLife).clamp(0, 1);
}

/// 飘字：击杀得分与补给提示。
class ScorePopup {
  ScorePopup({
    required this.x,
    required this.y,
    required this.text,
    this.color,
  });

  double x;
  double y;
  final String text;
  final int? color;
  double life = 0.8;

  bool get dead => life <= 0;
}

/// 星空背景的一颗星星。
class Star {
  Star({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.alpha,
  });

  double x;
  double y;
  final double speed;
  final double size;
  final double alpha;
}

/// 敌机开火方向工具：从 `from` 指向 `to` 的单位向量。
Offset aimDirection(Offset from, Offset to) {
  final delta = to - from;
  final length = delta.distance;
  if (length < 0.0001) return const Offset(0, 1);
  return delta / length;
}

/// 把角度限制在 [min, max]。
double clampDouble(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);
