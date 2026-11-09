import 'dart:math' as math;
import 'dart:ui';

import 'battle_types.dart';

/// 战场特效：粒子、飘字与星空。
///
/// 与战斗判定解耦，只负责视觉元素的生命周期与生成参数，便于单独测试与调优。
/// 粒子数量有上限并回收复用，密集弹幕下不会持续制造垃圾对象。
class BattleEffects {
  BattleEffects(this._rng, this._starRng);

  static const int maxTrailParticles = 420;
  static const int maxParticles = 460;
  static const int maxPopups = 60;

  /// 回收池上限：与同屏上限同量级即可，再多只是白占内存。
  static const int maxPooledParticles = 480;

  final math.Random _rng;
  final math.Random _starRng;

  final List<Particle> particles = [];
  final List<ScorePopup> popups = [];
  final List<Star> stars = [];

  /// 已消失但仍可复用的粒子对象。
  final List<Particle> _pool = [];

  /// 阻力系数到衰减因子的缓存，每个更新步清空复用，不再逐步新建 Map。
  final Map<int, double> _damping = {};

  void clear() {
    for (final particle in particles) {
      _recycle(particle);
    }
    particles.clear();
    popups.clear();
  }

  void resetStars(Size world) {
    stars.clear();
    final count = (world.width * world.height / 5200).round().clamp(40, 110);
    for (var i = 0; i < count; i++) {
      stars.add(
        Star(
          x: _starRng.nextDouble() * world.width,
          y: _starRng.nextDouble() * world.height,
          speed: 18 + _starRng.nextDouble() * 72,
          size: 0.6 + _starRng.nextDouble() * 1.5,
          alpha: 0.18 + _starRng.nextDouble() * 0.6,
        ),
      );
    }
  }

  void update(double dt) {
    // 阻力系数只有几种，按系数缓存一次衰减因子，避免每颗粒子都调用 exp；
    // 缓存表跨步复用，热路径上不产生新的 Map 与闭包。
    final damping = _damping..clear();

    // 原地压缩：把存活的粒子前移，死掉的直接回收，避免两次遍历与 removeWhere。
    var write = 0;
    for (var read = 0; read < particles.length; read++) {
      final particle = particles[read];
      particle.life -= dt;
      if (particle.dead) {
        _recycle(particle);
        continue;
      }
      final key = (particle.drag * 100).round();
      var factor = damping[key];
      if (factor == null) {
        factor = math.exp(-particle.drag * dt);
        damping[key] = factor;
      }
      particle.vx *= factor;
      particle.vy *= factor;
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
      particles[write++] = particle;
    }
    if (write < particles.length) particles.length = write;

    var popupWrite = 0;
    for (var read = 0; read < popups.length; read++) {
      final popup = popups[read];
      popup.life -= dt;
      if (popup.dead) continue;
      popup.y -= 24 * dt;
      popups[popupWrite++] = popup;
    }
    if (popupWrite < popups.length) popups.length = popupWrite;
  }

  void updateStars(double dt, Size world) {
    for (final star in stars) {
      star.y += star.speed * dt;
      if (star.y > world.height + 4) {
        star.y = -4;
        star.x = _starRng.nextDouble() * world.width;
      }
    }
  }

  /// 战机尾焰：持续小颗粒，护盾展开时换成蓝色。
  void addPlayerTrail(Offset position, {required bool shielded}) {
    particles.add(
      _acquire(
        x: position.dx + (_rng.nextDouble() - 0.5) * 6,
        y: position.dy + 14,
        vx: (_rng.nextDouble() - 0.5) * 14,
        vy: 90,
        life: 0.26,
        size: 2.4 + _rng.nextDouble() * 1.6,
        color: shielded ? 0xFF7FD8FF : 0xFF4FD1FF,
        kind: ParticleKind.trail,
        drag: 2.4,
      ),
    );
    _trim(maxTrailParticles);
  }

  void addPopup(ScorePopup popup) {
    popups.add(popup);
    if (popups.length > maxPopups) {
      popups.removeRange(0, popups.length - maxPopups);
    }
  }

  /// 敌机爆炸：火花、烟雾、冲击环，大型目标追加碎片。
  void explode(Offset position, {required bool big, required int color}) {
    burst(
      position,
      count: big ? 26 : 12,
      color: color,
      speed: big ? 240 : 150,
      size: big ? 3.4 : 2.2,
      life: big ? 0.8 : 0.5,
    );
    burst(
      position,
      count: big ? 10 : 4,
      color: 0xFF2A3358,
      speed: big ? 90 : 55,
      size: big ? 9 : 5,
      kind: ParticleKind.smoke,
      life: big ? 1.1 : 0.7,
    );
    burst(
      position,
      count: 2,
      color: 0xFFFFFFFF,
      speed: 40,
      size: big ? 18 : 9,
      kind: ParticleKind.ring,
      life: 0.36,
    );
    if (big) {
      burst(
        position,
        count: 8,
        color: 0xFFFFD54F,
        speed: 190,
        size: 3,
        kind: ParticleKind.debris,
        life: 0.9,
      );
    }
  }

  int _fx = 0;
  void grazeSpark(Offset position, int color) {
    for (var i = 0; i < 2; i++) {
      final angle = _fx++ * 2.399963;
      particles.add(
        _acquire(
          x: position.dx,
          y: position.dy,
          vx: math.cos(angle) * 65,
          vy: math.sin(angle) * 65,
          life: 0.22,
          size: 1.8,
          color: color,
          kind: ParticleKind.spark,
          drag: 2.2,
        ),
      );
    }
    _trim(maxParticles);
  }

  void absorbBurst(Offset center, Offset from) {
    particles.add(
      _acquire(
        x: from.dx,
        y: from.dy,
        vx: (center.dx - from.dx) * 4,
        vy: (center.dy - from.dy) * 4,
        life: 0.25,
        size: 2.2,
        color: 0xFF9BFFEA,
        kind: ParticleKind.spark,
        drag: 0,
      ),
    );
    _trim(maxParticles);
  }

  void absorbRing(Offset center) {
    particles.add(
      _acquire(
        x: center.dx,
        y: center.dy,
        vx: 0,
        vy: 0,
        life: 0.5,
        size: 34,
        color: 0xFF9BFFEA,
        kind: ParticleKind.ring,
        drag: 0,
      ),
    );
    _trim(maxParticles);
  }

  void spark(Offset position, int color) {
    burst(position, count: 3, color: color, speed: 90, size: 1.8, life: 0.22);
  }

  /// 向四周随机方向喷射粒子，速度、大小与寿命都带随机抖动。
  void burst(
    Offset position, {
    required int count,
    required int color,
    double speed = 160,
    double size = 2.6,
    ParticleKind kind = ParticleKind.spark,
    double life = 0.5,
  }) {
    for (var i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final velocity = speed * (0.3 + _rng.nextDouble() * 0.9);
      particles.add(
        _acquire(
          x: position.dx,
          y: position.dy,
          vx: math.cos(angle) * velocity,
          vy: math.sin(angle) * velocity,
          life: life * (0.6 + _rng.nextDouble() * 0.7),
          size: size * (0.7 + _rng.nextDouble() * 0.7),
          color: color,
          kind: kind,
          drag: kind == ParticleKind.smoke ? 1.1 : 2.2,
        ),
      );
    }
    _trim(maxParticles);
  }

  /// 取一颗粒子：优先复用回收池里的对象，池空时才新建。
  Particle _acquire({
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
    if (_pool.isEmpty) {
      return Particle(
        x: x,
        y: y,
        vx: vx,
        vy: vy,
        life: life,
        size: size,
        color: color,
        kind: kind,
        drag: drag,
      );
    }
    return _pool.removeLast()..reset(
      x: x,
      y: y,
      vx: vx,
      vy: vy,
      life: life,
      size: size,
      color: color,
      kind: kind,
      drag: drag,
    );
  }

  void _recycle(Particle particle) {
    if (_pool.length < maxPooledParticles) _pool.add(particle);
  }

  void _trim(int limit) {
    final overflow = particles.length - limit;
    if (overflow <= 0) return;
    for (var i = 0; i < overflow; i++) {
      _recycle(particles[i]);
    }
    particles.removeRange(0, overflow);
  }

  /// 回收池当前大小，供测试校验复用是否生效。
  int get pooledParticles => _pool.length;
}
