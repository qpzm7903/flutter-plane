import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../challenge/daily_challenge.dart';
import 'battle_collision.dart';
import 'battle_effects.dart';
import 'battle_tuning.dart';
import 'battle_types.dart';
import 'boss_catalog.dart';
import 'bullet_field.dart';
import 'enemy_motion.dart';
import 'enemy_weapons.dart';
import 'pickup_rules.dart';
import 'player_weapon.dart';
import 'wave_director.dart';
import 'stance_rules.dart';
import 'rules_text.dart';

/// 战斗控制器：纯逻辑的弹幕战场，负责玩家、敌机、弹道、碰撞、波次与计分。
///
/// 渲染层按世界坐标（宽度固定 [kWorldWidth]）缩放绘制，界面层只读取状态，
/// 因此同一套逻辑可以在 Android、Windows 与 Web 上保持一致，并可直接单测。
/// 具体职责拆到 [BattleEffects]（特效）、[WaveDirector]（波次）、
/// `player_weapon` / `enemy_weapons`（弹道）与 `battle_collision`（碰撞）。
class BattleController extends ChangeNotifier {
  BattleController({
    required Size size,
    int seed = 20261107,
    this._highScore = 0,
    this.challenge,
  }) : _size = size,
       _seed = seed,
       _rng = math.Random(seed),
       _starRng = math.Random(seed ^ 0x5F3759DF),
       _director = WaveDirector(seed: seed) {
    _effects = BattleEffects(_rng, _starRng);
    player = Player(
      x: size.width / 2,
      y: size.height - kPlayerStartBottomOffset,
    );
    _effects.resetStars(_size);
  }

  /// 每日挑战配置；普通战斗为 null。
  final DailyChallenge? challenge;

  /// 当前战场修正，普通战斗使用中性数值。
  ChallengeModifier get challengeModifier =>
      challenge?.modifier ?? ChallengeModifier.standard;

  /// 开场操作提示的持续时间，与 HUD 的淡出时长保持一致。
  static const double hintDuration = kBattleHintDuration;

  final int _seed;
  final math.Random _rng;
  final math.Random _starRng;
  late final BattleEffects _effects;
  WaveDirector _director;

  late Player player;
  final List<Enemy> enemies = [];
  final List<Bullet> playerBullets = [];
  final List<Bullet> enemyBullets = [];
  final List<PowerUp> powerUps = [];
  final List<Wingman> wingmen = [];

  List<Particle> get particles => _effects.particles;
  List<ScorePopup> get popups => _effects.popups;
  List<Star> get stars => _effects.stars;

  final List<BattleEvent> _events = [];
  final List<SpawnRequest> _spawnScratch = [];
  final ValueNotifier<int> _bossHp = ValueNotifier<int>(0);
  final _resonanceMeter = ValueNotifier<int>(0);
  ValueListenable<int> get resonanceMeter => _resonanceMeter;
  final _graze = GrazeLedger();
  int grazes = 0;
  double grazePulse = 0, resonanceArm = 0;
  double _emptyResonanceCooldown = 0;
  double _moveAccum = 0;
  bool _focusHeld = false;
  int _hintedWave = 0;
  void setFocusHeld(bool held) => _focusHeld = held;
  Offset _moveAxis = Offset.zero;
  Size _size;
  int _highScore;
  int _runs = 0;
  double _gapTimer = 1.4;
  double _hudTimer = 0;
  int _lastHudSignature = 0;
  double _trailTimer = 0;
  double _shootCooldown = 0;
  final DropLedger _drops = DropLedger();

  BattlePhase phase = BattlePhase.ready;
  int score = 0;
  int wave = 0;
  int kills = 0;
  int combo = 0;
  double comboTimer = 0;

  /// 单局最高连击与击破 Boss 数，结算时写入累计战绩与成就。
  int maxCombo = 0;
  int bossKills = 0;

  double shake = 0;
  double flash = 0;
  double elapsed = 0;
  Duration survived = Duration.zero;

  Size get size => _size;

  int get highScore => _highScore;

  BossVariant get bossVariant => bossVariantForWave(wave);

  String get bossName => bossNameForWave(wave);

  int get multiplier => comboMultiplier(combo);

  Enemy? get boss {
    for (final enemy in enemies) {
      if (enemy.isBoss && !enemy.dead) return enemy;
    }
    return null;
  }

  double get bossHpRatio => boss?.hpRatio ?? 0;

  /// Boss 血量（千分比）：血条单独监听它，Boss 战期间不必重建整个 HUD。
  ValueListenable<int> get bossHp => _bossHp;

  String get waveLabel {
    if (wave <= 0) return '待命';
    if (_director.bossWave) return 'BOSS 波';
    return '第 $wave 波';
  }

  /// 开始新一轮战斗，清空全部战场状态。
  void start() {
    _runs++;
    final modifier = challengeModifier;
    _director = WaveDirector(seed: challenge?.seed ?? _seed + _runs * 7919);
    player =
        Player(x: _size.width / 2, y: _size.height - kPlayerStartBottomOffset)
          ..lives = math.min(
            Player.maxLives,
            math.max(1, Player.startLives + modifier.startLivesDelta),
          )
          ..weaponLevel = modifier.startWeaponLevel;
    enemies.clear();
    playerBullets.clear();
    enemyBullets.clear();
    powerUps.clear();
    wingmen.clear();
    _effects.clear();
    _events.clear();
    score = 0;
    wave = 0;
    kills = 0;
    combo = 0;
    comboTimer = 0;
    maxCombo = 0;
    bossKills = 0;
    shake = 0;
    flash = 0;
    elapsed = 0;
    survived = Duration.zero;
    _gapTimer = kFirstWaveGap;
    _hudTimer = 0;
    _lastHudSignature = 0;
    _trailTimer = 0;
    _shootCooldown = 0;
    _drops.clearRun();
    _graze.clearRun();
    grazes = 0;
    grazePulse = resonanceArm = _emptyResonanceCooldown = 0;
    _moveAccum = 0;
    _focusHeld = false;
    _hintedWave = 0;
    _resonanceMeter.value = 0;
    _moveAxis = Offset.zero;
    _bossHp.value = 0;
    _effects.resetStars(_size);
    phase = BattlePhase.playing;
    notifyListeners();
  }

  void pause() {
    if (phase != BattlePhase.playing) return;
    phase = BattlePhase.paused;
    notifyListeners();
  }

  void resume() {
    if (phase != BattlePhase.paused) return;
    phase = BattlePhase.playing;
    notifyListeners();
  }

  void setHighScore(int value) {
    if (value == _highScore) return;
    _highScore = value;
    notifyListeners();
  }

  /// 键盘方向轴：长度不超过 1 的向量。
  void setMoveAxis(Offset axis) {
    final length = axis.distance;
    _moveAxis = length > 1 ? axis / length : axis;
  }

  /// 指针拖动：按手指位移平移战机，越界自动收拢。
  void movePlayerBy(Offset delta) {
    if (phase != BattlePhase.playing || !player.alive) return;
    _moveAccum += delta.distance;
    player.x += delta.dx;
    player.y += delta.dy;
    clampPlayerToArena(player, _size);
    player.tilt = clampDouble(player.tilt + delta.dx * 0.03, -1, 1);
  }

  /// 使用炸弹：清空敌弹并对全场敌机造成伤害。
  void useBomb() {
    if (phase != BattlePhase.playing || !player.alive || player.bombs <= 0) {
      return;
    }
    player.bombs--;
    flash = 0.62;
    shake = math.max(shake, 16);
    _emit(BattleEvent.bomb);
    for (final bullet in enemyBullets) {
      _effects.burst(
        Offset(bullet.x, bullet.y),
        count: 1,
        color: 0xFF8BE9FD,
        speed: 60,
        size: 2.2,
        life: 0.3,
      );
    }
    enemyBullets.clear();
    for (final enemy in enemies) {
      if (enemy.dead) continue;
      final damage = enemy.isBoss
          ? enemy.maxHp * kBombBossDamageRatio
          : kBombDamage;
      _damageEnemy(enemy, damage);
    }
    _effects.addPopup(
      ScorePopup(x: _size.width / 2, y: _size.height * 0.55, text: '全屏轰炸'),
    );
    notifyListeners();
  }

  int _scaled(int value) =>
      (value * multiplier * challengeModifier.scoreScale).round();

  void armResonance() {
    if (phase == BattlePhase.playing &&
        player.alive &&
        canResonate(player, wave)) {
      resonanceArm = kDoubleTapWindow;
    }
  }

  void useResonance() {
    if (phase != BattlePhase.playing ||
        !player.alive ||
        !canResonate(player, wave)) {
      return;
    }
    var available = 0;
    for (final bullet in enemyBullets) {
      final dx = bullet.x - player.x, dy = bullet.y - player.y;
      if (!bullet.dead &&
          dx * dx + dy * dy <= kResonanceRadius * kResonanceRadius) {
        available++;
      }
    }
    if (available < kResonanceMinConvert) {
      if (_emptyResonanceCooldown <= 0) {
        _effects.addPopup(
          ScorePopup(x: player.x, y: player.y - 32, text: '无弹可吞'),
        );
        _emptyResonanceCooldown = 0.8;
      }
      return;
    }
    player.resonance = 0;
    resonanceArm = 0;
    var converted = 0;
    final center = Offset(player.x, player.y);
    for (final bullet in enemyBullets) {
      final dx = bullet.x - player.x, dy = bullet.y - player.y;
      if (bullet.dead ||
          dx * dx + dy * dy > kResonanceRadius * kResonanceRadius) {
        continue;
      }
      bullet.dead = true;
      if (converted < 12) {
        _effects.absorbBurst(center, Offset(bullet.x, bullet.y));
      }
      converted++;
    }
    final gain =
        math.min(converted, kResonanceMaxConvert) *
        _scaled(kResonanceBulletScore);
    score += gain;
    player.invuln = math.max(player.invuln, kResonanceInvuln);
    var repaired = false;
    for (final wing in wingmen) {
      if (wing.role != WingmanRole.guard) continue;
      repaired |= wing.overheat > 0 || wing.energy < kGuardMaxEnergy;
      wing.energy = kGuardMaxEnergy;
      wing.overheat = 0;
    }
    if (repaired) {
      _effects.addPopup(
        ScorePopup(
          x: player.x,
          y: player.y - 46,
          text: '卫星复位',
          color: 0xFF9BFFEA,
        ),
      );
    }
    if (wave >= kChargeFromWave) {
      player.charge = 1;
      player.chargePower =
          1 + math.min(converted, kLancePowerCapBullets) * kLancePowerPerBullet;
    }
    if (combo > 0) comboTimer = kComboWindow;
    flash = math.max(flash, 0.2);
    shake = math.max(shake, 10);
    _emit(BattleEvent.resonance);
    _effects.absorbRing(center);
    _effects.addPopup(
      ScorePopup(
        x: player.x,
        y: player.y - 32,
        text: '共鸣 吞噬 ×$converted  +$gain',
        color: 0xFF9BFFEA,
      ),
    );
    _resonanceMeter.value = 0;
    notifyListeners();
  }

  void resize(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final scaleX = size.width / _size.width;
    _size = size;
    player.x *= scaleX;
    clampPlayerToArena(player, size);
    for (final enemy in enemies) {
      clampEnemyToArena(enemy, size);
    }
    _effects.resetStars(_size);
    notifyListeners();
  }

  /// 本步累积的事件（不复制），渲染层消费后调用 [clearEvents]。
  List<BattleEvent> get pendingEvents => _events;

  void clearEvents() => _events.clear();

  void update(double dt) {
    if (dt <= 0) return;
    if (phase == BattlePhase.gameOver || phase == BattlePhase.ready) {
      _updateEffects(dt);
      return;
    }
    if (phase != BattlePhase.playing) return;

    elapsed += dt;
    grazePulse = math.max(0, grazePulse - 4 * dt);
    resonanceArm = math.max(0, resonanceArm - dt);
    _emptyResonanceCooldown = math.max(0, _emptyResonanceCooldown - dt);
    _effects.updateStars(dt, _size);
    _updatePlayer(dt);
    _updateWaves(dt);
    _updateEnemies(dt);
    _updateBullets(dt);
    _updatePowerUps(dt);
    _collide(dt);
    _updateEffects(dt);

    if (comboTimer > 0) {
      comboTimer -= dt;
      if (comboTimer <= 0) combo = 0;
    }
    _shootCooldown = math.max(0, _shootCooldown - dt);
    shake = shake < 0.05 ? 0 : shake * math.exp(-5.2 * dt);
    flash = math.max(0, flash - 2.4 * dt);
    _hudTimer += dt;
    if (_hudTimer < kHudRefreshInterval) return;
    _hudTimer = 0;
    _syncBossHp();
    _resonanceMeter.value = (player.resonance / kResonanceMax * 1000)
        .round()
        .clamp(0, 1000);
    // 开场提示需要连续淡出，其余时间只在 HUD 可见数值真的变化时才通知。
    // Boss 血条由独立的 bossHp 通知驱动，不再拖着整棵 HUD 按 10Hz 重建。
    final signature = _hudSignature();
    if (elapsed >= hintDuration && signature == _lastHudSignature) return;
    _lastHudSignature = signature;
    notifyListeners();
  }

  /// 把 Boss 血量同步到独立通知器：只有血条订阅它，与 HUD 主体解耦。
  void _syncBossHp() {
    final target = boss;
    final permille = target == null
        ? 0
        : (target.hpRatio * 1000).round().clamp(0, 1000);
    if (_bossHp.value != permille) _bossHp.value = permille;
  }

  @override
  void dispose() {
    _bossHp.dispose();
    _resonanceMeter.dispose();
    super.dispose();
  }

  /// HUD 上可见数值的指纹，用于跳过没有变化的刷新。
  int _hudSignature() => Object.hash(
    score,
    wave,
    player.lives,
    player.bombs,
    player.weaponLevel,
    player.overdrive,
    player.route?.index,
    player.rapid > 0 ? player.rapid.ceil() : 0,
    player.wingmen,
    combo,
    multiplier,
    phase,
  );

  // ---------------------------------------------------------------- 玩家

  void _updatePlayer(double dt) {
    final p = player;
    if (!p.alive) return;
    _graze.refill(dt);
    final keyScale = _focusHeld && wave >= kFocusFromWave
        ? kFocusKeySpeedScale
        : 1.0;
    p.invuln = math.max(0, p.invuln - dt);
    p.shield = math.max(0, p.shield - dt);
    p.rapid = math.max(0, p.rapid - dt);
    if (_moveAxis != Offset.zero) {
      p.x += _moveAxis.dx * kPlayerSpeed * keyScale * dt;
      p.y += _moveAxis.dy * kPlayerSpeed * keyScale * dt;
      clampPlayerToArena(p, _size);
      p.tilt += (_moveAxis.dx - p.tilt) * math.min(1, dt * 9);
    } else {
      p.tilt += (0 - p.tilt) * math.min(1, dt * 7);
    }

    _moveAccum += _moveAxis.distance * kPlayerSpeed * keyScale * dt;
    if (updateStance(p, dt, moved: _moveAccum, held: _focusHeld, wave: wave)) {
      appendChargeLance(p, playerBullets);
      if (p.chargePower > 1.05) {
        _effects.addPopup(
          ScorePopup(
            x: p.x,
            y: p.y - 32,
            text: '矛击 ×${p.chargePower.toStringAsFixed(1)}',
          ),
        );
      }
      p.chargePower = 1;
      _emit(BattleEvent.lance);
    }
    _moveAccum = 0;
    p.fireCooldown -= dt;
    if (p.fireCooldown <= 0) {
      p.fireCooldown = playerFireInterval(
        p.weaponLevel,
        rapid: p.rapid > 0,
        route: p.overdrive > 0 ? p.route : null,
      );
      appendPlayerShots(p, playerBullets);
      if (_shootCooldown <= 0) {
        _shootCooldown = kShootSoundInterval;
        _emit(BattleEvent.shoot);
      }
    }

    _trailTimer += dt;
    while (_trailTimer >= kPlayerTrailInterval) {
      _trailTimer -= kPlayerTrailInterval;
      _effects.addPlayerTrail(Offset(p.x, p.y), shielded: p.shield > 0);
    }
    _updateWingmen(dt);
  }

  /// 僚机追随玩家两侧，按固定间隔向正上方偏外开火。
  void _updateWingmen(double dt) {
    for (final wing in wingmen) {
      final targetX =
          player.x +
          wing.side *
              kWingmanOffsetX *
              (1 - kFocusWingmanSqueeze * player.squeeze);
      final targetY = player.y + wingmanOffsetY(wing.role);
      final follow = math.min(1, dt * kWingmanFollowLerp);
      wing.x += (targetX - wing.x) * follow;
      wing.y += (targetY - wing.y) * follow;
      if (wing.role == WingmanRole.guard) {
        if (wing.overheat > 0) {
          wing.overheat = math.max(0, wing.overheat - dt);
          if (wing.overheat == 0) wing.energy = kGuardRestoreEnergy;
        } else {
          wing.energy = math.min(
            kGuardMaxEnergy,
            wing.energy + kGuardRegenPerSec * dt,
          );
        }
        continue;
      }
      wing.cooldown -= dt;
      if (wing.cooldown > 0) continue;
      wing.cooldown = kWingmanSpecs[wing.role]!.fireInterval;
      appendWingmanShots(wing, playerBullets);
    }
  }

  // ---------------------------------------------------------------- 波次

  void _updateWaves(double dt) {
    final spawns = _spawnScratch;
    spawns.clear();
    _director.updateInto(dt, spawns);
    for (final request in spawns) {
      _spawnEnemy(request);
    }
    if (_director.spawning || enemies.isNotEmpty) return;
    _gapTimer -= dt;
    if (_gapTimer > 0) return;
    _director.startNextWave();
    wave = _director.wave;
    final hint = systemHintForWave(wave);
    if (hint != null && _hintedWave != wave) {
      _hintedWave = wave;
      _effects.addPopup(
        ScorePopup(
          x: _size.width / 2,
          y: _size.height * 0.42,
          text: hint,
          color: 0xFF8BE9FD,
        ),
      );
    }
    _gapTimer = kBetweenWaveGap;
    _effects.addPopup(
      ScorePopup(
        x: _size.width / 2,
        y: _size.height * 0.36,
        text: _director.bossWave ? '⚠ $bossName 来袭' : '第 $wave 波',
        color: _director.bossWave ? 0xFFFF6B6B : 0xFF8BE9FD,
      ),
    );
    _emit(_director.bossWave ? BattleEvent.bossAppear : BattleEvent.waveStart);
    if (_director.bossWave) flash = 0.22;
    notifyListeners();
  }

  void _spawnEnemy(SpawnRequest request) {
    final difficulty = waveDifficulty(wave) * challengeModifier.enemyHpScale;
    enemies.add(
      Enemy(
        kind: request.kind,
        pattern: request.pattern,
        x: request.x,
        y: request.kind == EnemyKind.boss ? kBossSpawnY : kEnemySpawnY,
        difficulty: difficulty,
        driftPhase: request.phase,
        variant: request.variant,
      ),
    );
    // Boss 一入场就让血条读到满血，避免首帧短暂显示为空。
    if (request.kind == EnemyKind.boss) _bossHp.value = 1000;
  }

  // ---------------------------------------------------------------- 敌机

  void _updateEnemies(double dt) {
    // 原地压缩：死掉的敌机直接跳过，避免每一步 removeWhere 新建闭包。
    var write = 0;
    for (var read = 0; read < enemies.length; read++) {
      final enemy = enemies[read];
      if (enemy.dead) continue;
      enemy.age += dt;
      enemy.hitFlash = math.max(0, enemy.hitFlash - dt);
      if (enemy.isBoss) {
        _updateBoss(enemy, dt);
      } else {
        advanceEnemy(
          enemy,
          dt,
          targetX: enemy.pattern == EnemyPattern.chase ? player.x : null,
        );
        if (enemy.y > _size.height + kEnemyCullMargin) {
          enemy.dead = true;
        } else if (enemy.y > kEnemyFireMinY &&
            enemy.y < _size.height * kEnemyFireMaxRatio) {
          updateEnemyFire(
            enemy,
            dt,
            wave: wave,
            targetX: player.x,
            targetY: player.y,
            out: enemyBullets,
            speedScale: challengeModifier.enemyBulletSpeedScale,
          );
        }
      }
      if (!enemy.dead) enemies[write++] = enemy;
    }
    if (write < enemies.length) enemies.length = write;
  }

  void _updateBoss(Enemy boss, double dt) {
    if (!advanceBossEntry(boss, dt)) return;
    hoverBoss(boss, _size);
    boss.attackTimer -= dt;
    if (boss.attackTimer > 0) return;

    final cycle = boss.attackPhase % 4;
    final speed =
        bossBarrageSpeed(wave) * challengeModifier.enemyBulletSpeedScale;
    boss.attackPhase++;
    boss.attackTimer = bossBarrageInterval(wave);
    enemyBullets.addAll(
      buildBossBarrage(
        boss: boss,
        target: Offset(player.x, player.y),
        cycle: cycle,
        speed: speed,
        variant: boss.variant,
      ),
    );
  }

  void _damageEnemy(Enemy enemy, double damage) {
    if (enemy.dead) return;
    enemy.hp -= damage;
    enemy.hitFlash = kEnemyHitFlashDuration;
    if (enemy.hp <= 0) _killEnemy(enemy);
  }

  void _killEnemy(Enemy enemy) {
    if (enemy.dead) return;
    enemy.dead = true;
    kills++;
    combo++;
    maxCombo = math.max(maxCombo, combo);
    comboTimer = kComboWindow;
    if (enemy.isBoss) bossKills++;
    final gain = _scaled(enemy.spec.score);
    score += gain;
    final big = enemy.isBoss || enemy.kind == EnemyKind.elite;
    _effects.addPopup(
      ScorePopup(
        x: enemy.x,
        y: enemy.y,
        text: '+$gain',
        color: enemy.isBoss ? 0xFFFFD54F : null,
      ),
    );
    _effects.explode(
      Offset(enemy.x, enemy.y),
      big: big,
      color: enemy.spec.explosionColor,
    );
    shake = math.max(shake, enemy.isBoss ? 18 : (big ? 8 : 3));
    if (enemy.isBoss) {
      flash = 0.5;
      _emit(BattleEvent.bigExplosion);
      final drops = _drops.bossDrops(player, _rng.nextDouble(), wave: wave);
      for (var i = 0; i < drops.length; i++) {
        _dropAt(enemy.x + (i - 1) * kBossDropOffsetX, enemy.y, drops[i]);
      }
      _effects.addPopup(
        ScorePopup(
          x: enemy.x,
          y: enemy.y - 26,
          text: '击破 $bossName',
          color: 0xFFFFD54F,
        ),
      );
      // Boss 血条要立即消失，这里单独通知一次；普通击破交给 10Hz 刷新合并。
      _syncBossHp();
      notifyListeners();
    } else {
      _emit(big ? BattleEvent.bigExplosion : BattleEvent.explosion);
      final chanceRoll = _rng.nextDouble();
      final kindRoll = _rng.nextDouble();
      final drop = _drops.rollKill(
        kind: enemy.kind,
        wave: wave,
        player: player,
        dropScale: challengeModifier.dropScale,
        chanceRoll: chanceRoll,
        kindRoll: kindRoll,
      );
      if (drop != null) _dropAt(enemy.x, enemy.y, drop);
    }
  }

  // ---------------------------------------------------------------- 弹道

  void _updateBullets(double dt) {
    advanceBullets(
      playerBullets,
      dt,
      worldWidth: _size.width,
      worldHeight: _size.height,
      margin: kPlayerBulletCullMargin,
    );
    advanceBullets(
      enemyBullets,
      dt,
      worldWidth: _size.width,
      worldHeight: _size.height,
      margin: kEnemyBulletCullMargin,
    );
  }

  // ---------------------------------------------------------------- 补给

  void _updatePowerUps(double dt) {
    var write = 0;
    for (var read = 0; read < powerUps.length; read++) {
      final item = powerUps[read];
      item.age += dt;
      item.y += item.vy * dt;
      item.x += math.sin(item.age * 2.4) * 18 * dt;
      if (item.y > _size.height + kPowerUpCullMargin) item.dead = true;
      if (!item.dead) powerUps[write++] = item;
    }
    if (write < powerUps.length) powerUps.length = write;
  }

  void _dropAt(double x, double y, PowerUpKind kind) {
    powerUps.add(
      PowerUp(
        x: clampDouble(x, kEnemySideMargin, _size.width - kEnemySideMargin),
        y: y,
        kind: kind,
      ),
    );
  }

  void _collectPowerUp(PowerUp item) {
    item.dead = true;
    final position = Offset(item.x, item.y);
    final outcome = applyPickup(
      item.kind,
      player,
      multiplier: multiplier,
      route: coreRouteAt(item.age),
    );
    score += outcome.score;
    _effects.addPopup(
      ScorePopup(
        x: item.x,
        y: item.y,
        text: outcome.text,
        color: outcome.color,
      ),
    );
    if (outcome.spawnWingman) {
      final wing = Wingman(
        side: wingmanSideFor(player.wingmen),
        x: player.x,
        y: player.y,
      );
      if (wing.role == WingmanRole.guard) {
        wing.energy = kGuardMaxEnergy;
        wing.y = player.y - kGuardOffsetY;
      } else {
        wing.cooldown = kWingmanSpecs[wing.role]!.initialCooldown;
      }
      wingmen.add(wing);
    }
    _effects.burst(
      position,
      count: 10,
      color: 0xFF7FD8FF,
      speed: 120,
      size: 2.2,
      life: 0.4,
    );
    _emit(BattleEvent.powerUp);
  }

  // ---------------------------------------------------------------- 碰撞

  void _collide(double dt) {
    _collidePlayerShots(dt);
    if (player.alive) {
      _collideGuard();
      _collideEnemyShots(dt);
    }
    _collideBodies();
    _collidePowerUps();
  }

  /// 扫掠检测：先按线段包围盒排除远处目标，再做线段与圆的精确判定。
  bool _sweepHits(
    Bullet bullet,
    double dt,
    double centerX,
    double centerY,
    double reach,
  ) => sweepHitsCircleXY(
    centerX: centerX,
    centerY: centerY,
    reach: reach,
    fromX: bullet.x - bullet.vx * dt,
    fromY: bullet.y - bullet.vy * dt,
    toX: bullet.x,
    toY: bullet.y,
  );

  void _collidePlayerShots(double dt) {
    for (final bullet in playerBullets) {
      if (bullet.dead) continue;
      // 扫掠起点只算一次：同一颗子弹要对每架敌机做判定，起点没有必要
      // 在循环里重复乘减。
      final fromX = bullet.x - bullet.vx * dt;
      final fromY = bullet.y - bullet.vy * dt;
      if (bullet.cuts) {
        for (final shot in enemyBullets) {
          if (!shot.dead &&
              _sweepHits(
                bullet,
                dt,
                shot.x,
                shot.y,
                bullet.radius + shot.radius,
              )) {
            shot.dead = true;
            _effects.grazeSpark(Offset(shot.x, shot.y), 0xFFB8E6FF);
          }
        }
      }
      for (final enemy in enemies) {
        if (enemy.dead ||
            identical(enemy, bullet.lastHit) ||
            identical(enemy, bullet.prevHit)) {
          continue;
        }
        final reach = enemy.radius + bullet.radius;
        if (!sweepHitsCircleXY(
          centerX: enemy.x,
          centerY: enemy.y,
          reach: reach,
          fromX: fromX,
          fromY: fromY,
          toX: bullet.x,
          toY: bullet.y,
        )) {
          continue;
        }
        _damageEnemy(enemy, bullet.damage);
        if (bullet.kind == BulletKind.chargeLance) {
          _effects.grazeSpark(Offset(bullet.x, bullet.y), 0xFFFFE9A8);
        } else {
          _effects.spark(Offset(bullet.x, bullet.y), 0xFFB7F4FF);
        }
        if (bullet.pierce > 0 && !enemy.isBoss) {
          bullet.pierce--;
          bullet.prevHit = bullet.lastHit;
          bullet.lastHit = enemy;
          continue;
        }
        bullet.dead = true;
        break;
      }
    }
  }

  void _collideGuard() {
    for (final guard in wingmen) {
      if (guard.role != WingmanRole.guard ||
          guard.overheat > 0 ||
          guard.energy <= 0) {
        continue;
      }
      for (final bullet in enemyBullets) {
        if (bullet.dead ||
            !circlesOverlapXY(
              bullet.x,
              bullet.y,
              bullet.radius,
              guard.x,
              guard.y,
              kGuardRadius,
            )) {
          continue;
        }
        bullet.dead = true;
        _effects.spark(Offset(bullet.x, bullet.y), 0xFF9BFFEA);
        guard.energy -= 1;
        if (guard.energy <= 0) {
          guard.overheat = kGuardOverheat;
          break;
        }
      }
    }
  }

  void _collideEnemyShots(double dt) {
    final px = player.x;
    final py = player.y;
    for (final bullet in enemyBullets) {
      if (bullet.dead) continue;
      final reach = player.hitRadius + bullet.radius;
      if (_sweepHits(bullet, dt, px, py, reach)) {
        bullet.dead = true;
        _hitPlayer();
        break;
      }
      if (wave < kGrazeFromWave ||
          player.invuln > 0 ||
          !player.alive ||
          bullet.grazed) {
        continue;
      }
      final dx = bullet.x - px, dy = bullet.y - py;
      final band = Player.radius + kGrazeBand + bullet.radius;
      if (dx * dx + dy * dy > band * band) continue;
      bullet.grazed = true;
      final reward = _graze.credit(player, wave: wave);
      if (reward == null) continue;
      grazePulse = 1;
      grazes = _graze.total;
      score += _scaled(reward.score);
      if (combo > 0) {
        comboTimer = math.min(kComboWindow, comboTimer + reward.comboExtend);
      }
      _effects.grazeSpark(Offset(bullet.x, bullet.y), 0xFF9BFFEA);
    }
  }

  void _collideBodies() {
    final px = player.x;
    final py = player.y;
    for (final enemy in enemies) {
      if (enemy.dead || !player.alive) continue;
      if (circlesOverlapXY(
        enemy.x,
        enemy.y,
        enemy.radius,
        px,
        py,
        player.hitRadius,
      )) {
        _damageEnemy(enemy, enemy.isBoss ? kRamBossDamage : kRamDamage);
        _hitPlayer();
      }
    }
  }

  void _collidePowerUps() {
    final px = player.x;
    final py = player.y;
    var write = 0;
    for (var read = 0; read < powerUps.length; read++) {
      final item = powerUps[read];
      if (item.dead) continue;
      if (circlesOverlapXY(
        item.x,
        item.y,
        PowerUp.radius + 4,
        px,
        py,
        Player.radius,
      )) {
        _collectPowerUp(item);
      }
      if (!item.dead) powerUps[write++] = item;
    }
    if (write < powerUps.length) powerUps.length = write;
  }

  void _hitPlayer() {
    final center = Offset(player.x, player.y);
    if (!player.alive || player.invuln > 0) return;
    if (player.shield > 0) {
      player.shield = 0;
      player.invuln = kShieldBreakInvuln;
      shake = math.max(shake, 8);
      flash = math.max(flash, 0.16);
      _emit(BattleEvent.shieldBreak);
      _effects.burst(
        center,
        count: 16,
        color: 0xFF7FD8FF,
        speed: 170,
        size: 2.4,
      );
      notifyListeners();
      return;
    }
    player.lives--;
    player.chargePower = 1;
    applyHitPenalty(player);
    player.invuln = kHitInvuln;
    shake = math.max(shake, 14);
    flash = math.max(flash, 0.38);
    _emit(BattleEvent.playerHit);
    _effects.explode(center, big: true, color: 0xFF4FD1FF);
    enemyBullets.removeWhere((bullet) {
      final delta = Offset(bullet.x, bullet.y) - center;
      return delta.distanceSquared < kHitClearRadius * kHitClearRadius;
    });
    if (player.lives <= 0) {
      _gameOver();
    } else {
      notifyListeners();
    }
  }

  void _gameOver() {
    player.alive = false;
    player.lives = 0;
    phase = BattlePhase.gameOver;
    survived = Duration(milliseconds: (elapsed * 1000).round());
    flash = 0.85;
    shake = 24;
    _emit(BattleEvent.gameOver);
    _effects.explode(Offset(player.x, player.y), big: true, color: 0xFFFFD54F);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 特效

  void _updateEffects(double dt) {
    _effects.update(dt);
    if (phase != BattlePhase.gameOver) return;
    for (final enemy in enemies) {
      enemy.hitFlash = math.max(0, enemy.hitFlash - dt);
    }
    shake = shake < 0.05 ? 0 : shake * math.exp(-3 * dt);
    flash = math.max(0, flash - 1.6 * dt);
    _effects.updateStars(dt, _size);
  }

  void _emit(BattleEvent event) {
    if (_events.length >= 24) return;
    _events.add(event);
  }
}
