import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/battle/battle_controller.dart';
import '../game/battle/battle_types.dart';
import '../game/logic_rate.dart';
import '../services/sound_service.dart';
import 'battle_visuals.dart';
import 'draw_batches.dart';

/// 战场渲染组件：按固定步长推进逻辑，用 Canvas 绘制星空、战机、弹幕与爆炸。
///
/// 所有图形都是程序化矢量绘制，仓库不存放任何图片、字体或音频资源。
class BattleFieldComponent extends PositionComponent {
  BattleFieldComponent({
    required this.controller,
    required this.logicRate,
    this.fontFamily,
  }) : _clock = FixedStepClock(logicRate.step),
       super(priority: 1);

  final BattleController controller;
  final LogicRate logicRate;
  final String? fontFamily;
  final FixedStepClock _clock;

  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  final Paint _glow = Paint();
  final DotBatch _dots = DotBatch();
  final DotBatch _dotsUnder = DotBatch();
  final CapsuleBatch _capsules = CapsuleBatch();
  final SegmentBatch _segments = SegmentBatch();
  final SegmentBatch _segmentsTop = SegmentBatch();

  /// 文本缓存分两层：先按文本取样式表，再用整型样式键取排版结果。
  /// 热路径上不再拼接 `文本|字号|颜色|字重` 字符串，飘字与补给标签
  /// 每帧数百次查找也不会产生临时字符串。
  final Map<String, Map<int, TextPainter>> _textCache = {};
  int _textPainterCount = 0;

  /// 量化透明度后复用的 [Color]，避免逐帧为淡出中的粒子与血条新建颜色。
  final Map<int, Color> _colorCache = {};

  static const int _whiteArgb = 0xFFFFFFFF;
  static const int _starStreakArgb = 0xFF7FD8FF;
  static final int _playerShieldArgb = kPlayerBulletGlow.toARGB32();
  static final int _playerShieldTrimArgb = kPlayerBulletBody.toARGB32();
  static final int _enemyEngineGlowArgb = kEnemyEngineGlow.toARGB32();
  static const int _bossCoreCrackArgb = 0xFFFF5252;

  /// 文本样式缓存上限：超过后整组淘汰最早的一条文本。
  static const int _maxCachedPainters = 120;

  /// 颜色缓存上限：量化档位与调色板都有限，正常不会触顶。
  static const int _maxCachedColors = 512;

  Size _backgroundSize = Size.zero;
  ui.Picture? _backgroundPicture;

  static final RRect _powerUpBox = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: 21, height: 21),
    const Radius.circular(5),
  );

  static final Path _wingFlame = Path()
    ..moveTo(-3, 0)
    ..lineTo(0, 7)
    ..lineTo(3, 0)
    ..close();

  /// 玩家尾焰按闪烁幅度预先建好 8 条路径，逐帧只按下标取用。
  static final List<Path> _playerFlames = [
    for (var i = 0; i < 8; i++)
      Path()
        ..moveTo(-4, 11)
        ..lineTo(0, 11 + 6 + i * 8 / 7)
        ..lineTo(4, 11)
        ..close(),
  ];

  @override
  void update(double dt) {
    _clock.advance(dt, (span) {
      controller.update(span);
      _flushEvents();
    });
  }

  @override
  void onRemove() {
    _backgroundPicture?.dispose();
    _backgroundPicture = null;
    for (final styles in _textCache.values) {
      for (final painter in styles.values) {
        painter.dispose();
      }
    }
    _textCache.clear();
    _textPainterCount = 0;
    _colorCache.clear();
    super.onRemove();
  }

  void _flushEvents() {
    final events = controller.pendingEvents;
    if (events.isEmpty) return;
    var played = 0;
    for (final event in events) {
      // 同一步内重复的事件只播一次，用位掩码去重，避免每步新建 Set。
      final bit = 1 << event.index;
      if (played & bit != 0) continue;
      played |= bit;
      SoundService.play(_soundOf(event));
    }
    controller.clearEvents();
  }

  static GameSound _soundOf(BattleEvent event) => switch (event) {
    BattleEvent.shoot => GameSound.shoot,
    BattleEvent.explosion => GameSound.explosion,
    BattleEvent.bigExplosion => GameSound.bigExplosion,
    BattleEvent.powerUp => GameSound.powerUp,
    BattleEvent.playerHit => GameSound.playerHit,
    BattleEvent.shieldBreak => GameSound.powerUp,
    BattleEvent.bomb => GameSound.bomb,
    BattleEvent.waveStart => GameSound.warning,
    BattleEvent.bossAppear => GameSound.warning,
    BattleEvent.gameOver => GameSound.gameOver,
  };

  @override
  void render(Canvas canvas) {
    final world = controller.size;
    if (world.width <= 0 || world.height <= 0) return;
    final sx = size.x / world.width;
    final sy = size.y / world.height;
    if (sx <= 0 || sy <= 0) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.x, size.y));
    canvas.scale(sx, sy);
    _drawBackground(canvas, world);

    final shake = controller.shake;
    canvas.save();
    if (shake > 0.1) {
      final t = controller.elapsed;
      canvas.translate(
        math.sin(t * 71.3) * shake,
        math.cos(t * 59.7) * shake * 0.7,
      );
    }
    _drawStars(canvas);
    _drawPowerUps(canvas, world);
    _drawBullets(canvas);
    _drawEnemies(canvas);
    _drawWingmen(canvas);
    _drawPlayer(canvas);
    _drawParticles(canvas, world);
    _drawPopups(canvas, world);
    canvas.restore();

    if (controller.flash > 0.01) {
      _fill.color = _fadeColor(_whiteArgb, controller.flash * 0.55);
      canvas.drawRect(Rect.fromLTWH(0, 0, world.width, world.height), _fill);
    }
    canvas.restore();
  }

  // ------------------------------------------------------------ 背景与星空

  /// 背景是静态画面：按战场尺寸录制一次 [ui.Picture]，之后每帧只提交一次
  /// 绘制，省掉三个全屏渐变着色器的重复求值与填充。
  void _drawBackground(Canvas canvas, Size world) {
    var picture = _backgroundPicture;
    if (picture == null || _backgroundSize != world) {
      _backgroundSize = world;
      final rect = Rect.fromLTWH(0, 0, world.width, world.height);
      final recorder = ui.PictureRecorder();
      final background = Canvas(recorder);
      background.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF070B1E), Color(0xFF0C1734), Color(0xFF05070F)],
            stops: [0, 0.52, 1],
          ).createShader(rect),
      );
      background.drawRect(
        rect,
        Paint()
          ..shader =
              const RadialGradient(
                colors: [Color(0x335C2E91), Color(0x00000000)],
              ).createShader(
                Rect.fromCircle(
                  center: Offset(world.width * 0.18, world.height * 0.18),
                  radius: world.width * 0.85,
                ),
              ),
      );
      background.drawRect(
        rect,
        Paint()
          ..shader =
              const RadialGradient(
                colors: [Color(0x2E1A6E8C), Color(0x00000000)],
              ).createShader(
                Rect.fromCircle(
                  center: Offset(world.width * 0.9, world.height * 0.78),
                  radius: world.width * 0.8,
                ),
              ),
      );
      picture = recorder.endRecording();
      _backgroundPicture?.dispose();
      _backgroundPicture = picture;
    }
    canvas.drawPicture(picture);
  }

  void _drawStars(Canvas canvas) {
    for (final star in controller.stars) {
      _dots.add(_whiteArgb, star.x, star.y, star.size, star.alpha);
      if (star.speed > 62) {
        _capsules.add(
          _starStreakArgb,
          star.x,
          star.y - 3.5,
          3.5,
          star.size * 0.9,
          star.alpha * 0.5,
        );
      }
    }
    _capsules.flush(canvas);
    _dots.flush(canvas);
  }

  // ------------------------------------------------------------ 玩家

  /// 僚机：小型护航机，带淡青色描边与持续闪烁的尾焰。
  void _drawWingmen(Canvas canvas) {
    if (controller.wingmen.isEmpty || !controller.player.alive) return;
    for (final wing in controller.wingmen) {
      final visual = kWingmanVisuals[wing.role]!;
      canvas.save();
      canvas.translate(wing.x, wing.y);
      _fill.color = visual.flame;
      canvas.save();
      canvas.translate(0, 5);
      // 尾焰长度随高光闪烁，复用同一条路径缩放绘制。
      canvas.scale(1, 0.75 + 0.25 * math.sin(controller.elapsed * 38));
      canvas.drawPath(_wingFlame, _fill);
      canvas.restore();
      _fill.color = visual.fill;
      canvas.drawPath(visual.path, _fill);
      _stroke
        ..color = visual.trim
        ..strokeWidth = 1.2;
      canvas.drawPath(visual.path, _stroke);
      _fill.color = const Color(0xFFE6FFFF);
      canvas.drawCircle(const Offset(0, -1.6), 1.5, _fill);
      _glow.color = visual.trim.withValues(alpha: 0.53);
      canvas.drawCircle(const Offset(0, 7), 2.2, _glow);
      canvas.restore();
    }
  }

  void _drawPlayer(Canvas canvas) {
    final player = controller.player;
    if (!player.alive) return;
    if (player.invuln > 0 && (controller.elapsed * 12).floor().isEven) return;

    canvas.save();
    canvas.translate(player.x, player.y);
    canvas.rotate(player.tilt * 0.16);

    // 尾焰：按正弦闪烁幅度取用预建路径，不再逐帧构造 Path。
    final flicker = 10 + math.sin(controller.elapsed * 42) * 4;
    final flame = _playerFlames[((flicker - 6) / 8 * 7).round().clamp(0, 7)];
    _fill.color = const Color(0xBB2B6BFF);
    canvas.drawPath(flame, _fill);
    _fill.color = const Color(0xE67FD8FF);
    canvas.save();
    canvas.scale(0.55, 0.75);
    canvas.translate(0, 5);
    canvas.drawPath(flame, _fill);
    canvas.restore();

    final path = playerHullPath;
    _fill.color = kPlayerHullShadow;
    canvas.save();
    canvas.scale(1.18);
    canvas.drawPath(path, _fill);
    canvas.restore();
    _fill.color = kPlayerHull;
    canvas.drawPath(path, _fill);
    _stroke
      ..color = kPlayerTrim
      ..strokeWidth = 1.5;
    canvas.drawPath(path, _stroke);

    // 座舱与高光
    _fill.color = const Color(0xFFDDF7FF);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -5), width: 5.4, height: 10),
      _fill,
    );
    _fill.color = const Color(0xCC7FD8FF);
    canvas.drawRect(const Rect.fromLTWH(-9.5, 3.4, 19, 2.2), _fill);

    if (player.shield > 0) {
      final pulse = 0.55 + 0.25 * math.sin(controller.elapsed * 9);
      _stroke
        ..color = _fadeColor(_playerShieldArgb, pulse)
        ..strokeWidth = 1.8;
      canvas.drawCircle(Offset.zero, 24, _stroke);
      _fill.color = _fadeColor(_playerShieldArgb, 0.08);
      canvas.drawCircle(Offset.zero, 24, _fill);
      _stroke
        ..color = _fadeColor(_playerShieldTrimArgb, pulse * 0.8)
        ..strokeWidth = 2.2;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: 27),
        controller.elapsed * 2.2,
        1.1,
        false,
        _stroke,
      );
    }
    canvas.restore();
  }

  // ------------------------------------------------------------ 敌机

  void _drawEnemies(Canvas canvas) {
    for (final enemy in controller.enemies) {
      if (enemy.dead) continue;
      final visual = visualFor(enemy);
      final appear = (enemy.age / 0.28).clamp(0.0, 1.0);
      final pulse = 0.9 + 0.1 * math.sin(enemy.age * 6);
      canvas.save();
      canvas.translate(enemy.x, enemy.y);
      _drawEnemyBody(
        canvas,
        enemy,
        visual,
        appear: appear,
        pulse: pulse,
        hit: enemy.hitFlash > 0,
      );
      canvas.restore();
    }
  }

  /// 机体绘制：普通敌机与 Boss 共用轮廓、炮塔与核心，只在尺寸和 Boss
  /// 专属的辉光、受损裂纹上分支。
  void _drawEnemyBody(
    Canvas canvas,
    Enemy enemy,
    EnemyVisual visual, {
    required double appear,
    required double pulse,
    required bool hit,
  }) {
    final hullArgb = hit ? _whiteArgb : visual.hull.toARGB32();
    final trimArgb = hit ? _whiteArgb : visual.trim.toARGB32();
    final coreArgb = visual.core.toARGB32();
    _fill.color = _fadeColor(hullArgb, appear);
    canvas.drawPath(visual.path, _fill);
    _stroke
      ..color = _fadeColor(trimArgb, appear)
      ..strokeWidth = visual.strokeWidth;
    canvas.drawPath(visual.path, _stroke);

    final turretRadius = enemy.isBoss ? 6.5 : 4.6;
    final turretStroke = enemy.isBoss ? 1.2 : 1.1;
    for (final turret in visual.turrets) {
      _fill.color = _fadeColor(hullArgb, appear);
      canvas.drawCircle(turret, turretRadius, _fill);
      _stroke
        ..color = _fadeColor(trimArgb, appear)
        ..strokeWidth = turretStroke;
      canvas.drawCircle(turret, turretRadius, _stroke);
    }

    if (enemy.isBoss) {
      _glow.color = _fadeColor(coreArgb, appear * pulse * 0.35);
      canvas.drawCircle(Offset.zero, visual.glowRadius, _glow);
      _fill.color = _fadeColor(coreArgb, appear * pulse);
      canvas.drawCircle(Offset.zero, visual.coreRadius, _fill);
      _fill.color = _fadeColor(_whiteArgb, appear * 0.9);
      canvas.drawCircle(Offset.zero, 4, _fill);
      if (enemy.hpRatio < 0.5) {
        _stroke
          ..color = _fadeColor(_bossCoreCrackArgb, appear * 0.8)
          ..strokeWidth = 1.2;
        canvas.drawLine(const Offset(-12, -4), const Offset(-4, 6), _stroke);
        canvas.drawLine(const Offset(18, 2), const Offset(26, 14), _stroke);
      }
      return;
    }

    _fill.color = _fadeColor(coreArgb, appear * pulse);
    canvas.drawCircle(Offset(0, visual.coreOffsetY), visual.coreRadius, _fill);
    _glow.color = _fadeColor(_enemyEngineGlowArgb, appear * 0.8);
    canvas.drawCircle(Offset(0, enemy.radius * 0.62), 2.4, _glow);
  }

  // ------------------------------------------------------------ 弹幕

  void _drawBullets(Canvas canvas) {
    // 玩家弹：辉光、弹体与弹芯一次遍历收集完再统一提交，
    // 每颗子弹只走一遍列表，不再分三趟读写批绘制缓冲。
    for (final bullet in controller.playerBullets) {
      final s = playerShotStyle(bullet.kind);
      _dots.add(s.glowArgb, bullet.x, bullet.y, s.glowRadius, s.glowAlpha);
      _segments.add(
        s.bodyArgb,
        bullet.x - bullet.vx * s.bodyK,
        bullet.y - bullet.vy * s.bodyK,
        bullet.x + bullet.vx * s.bodyK,
        bullet.y + bullet.vy * s.bodyK,
        s.bodyWidth,
        1,
      );
      _segmentsTop.add(
        s.coreArgb,
        bullet.x - bullet.vx * s.coreK,
        bullet.y - bullet.vy * s.coreK,
        bullet.x + bullet.vx * s.coreK,
        bullet.y + bullet.vy * s.coreK,
        s.coreWidth,
        1,
      );
      for (var i = 1; i <= s.tailDots; i++) {
        final k = i * 12 / kPlayerBulletSpeed;
        _dots.add(
          s.glowArgb,
          bullet.x - bullet.vx * k,
          bullet.y - bullet.vy * k,
          s.glowRadius / (i + 1),
          s.glowAlpha,
        );
      }
    }
    _dots.flush(canvas);
    _segments.flush(canvas);
    _segmentsTop.flush(canvas);

    // 敌弹：辉光写入下层桶，弹体与弹芯写入上层桶，一次遍历完成收集。
    // 两个桶分别提交，保持「全部辉光在下、弹芯在上」的既有层级。
    for (final bullet in controller.enemyBullets) {
      final argb = enemyBulletArgb(bullet.kind);
      _dotsUnder.add(argb, bullet.x, bullet.y, bullet.radius * 2.4, 0.26);
      _dots.add(argb, bullet.x, bullet.y, bullet.radius, 1);
      _dots.add(_whiteArgb, bullet.x, bullet.y, bullet.radius * 0.42, 0.85);
    }
    _dotsUnder.flush(canvas);
    _dots.flush(canvas);
  }

  // ------------------------------------------------------------ 补给

  void _drawPowerUps(Canvas canvas, Size world) {
    for (final item in controller.powerUps) {
      if (item.x < -24 || item.x > world.width + 24) continue;
      if (item.y < -24 || item.y > world.height + 24) continue;
      final argb = kPowerUpArgb[item.kind]!;
      canvas.save();
      canvas.translate(item.x, item.y);
      canvas.rotate(item.age * 1.8);
      _fill.color = _fadeColor(argb, 0.18);
      canvas.drawCircle(Offset.zero, 17, _fill);
      _fill.color = const Color(0xFF101A33);
      canvas.drawRRect(_powerUpBox, _fill);
      _stroke
        ..color = _fadeColor(argb, 1)
        ..strokeWidth = 1.8;
      canvas.drawRRect(_powerUpBox, _stroke);
      canvas.restore();

      final label = kPowerUpLabels[item.kind]![0];
      final painter = _text(
        label,
        size: 11,
        color: _fadeColor(argb, 1),
        weight: FontWeight.w700,
      );
      painter.paint(
        canvas,
        Offset(item.x - painter.width / 2, item.y - painter.height / 2),
      );
    }
  }

  // ------------------------------------------------------------ 粒子与飘字

  void _drawParticles(Canvas canvas, Size world) {
    for (final particle in controller.particles) {
      // 边缘爆炸的碎片会飞出战场，屏幕外的直接跳过，省掉批绘制写入。
      if (particle.x < -24 ||
          particle.x > world.width + 24 ||
          particle.y < -24 ||
          particle.y > world.height + 24) {
        continue;
      }
      final fade = (1 - particle.progress).clamp(0.0, 1.0);
      switch (particle.kind) {
        case ParticleKind.spark:
        case ParticleKind.trail:
          _dots.add(
            particle.color,
            particle.x,
            particle.y,
            particle.size * (0.5 + fade * 0.5),
            fade,
          );
        case ParticleKind.smoke:
          _dots.add(
            particle.color,
            particle.x,
            particle.y,
            particle.size * (1 + particle.progress * 1.6),
            fade * 0.4,
          );
        case ParticleKind.ring:
          _stroke
            ..color = _fadeColor(particle.color, fade * 0.8)
            ..strokeWidth = 1.6;
          canvas.drawCircle(
            Offset(particle.x, particle.y),
            particle.size * (1 + particle.progress * 4),
            _stroke,
          );
        case ParticleKind.debris:
          // 旋转的碎片本质上是一条短线段，并入线段批绘制后不再逐颗
          // save / translate / rotate / drawRect。
          final angle = particle.progress * 6;
          final half = particle.size * 1.1;
          final dx = math.cos(angle) * half;
          final dy = math.sin(angle) * half;
          _segments.add(
            particle.color,
            particle.x - dx,
            particle.y - dy,
            particle.x + dx,
            particle.y + dy,
            particle.size * 0.9,
            fade,
          );
      }
    }
    _dots.flush(canvas);
    _segments.flush(canvas);
  }

  void _drawPopups(Canvas canvas, Size world) {
    for (final popup in controller.popups) {
      if (popup.x < -40 ||
          popup.x > world.width + 40 ||
          popup.y < -30 ||
          popup.y > world.height + 30) {
        continue;
      }
      final alpha = ((popup.life / 0.8) * 4).ceil() / 4;
      final color = _fadeColor(popup.color ?? 0xFFE8F6FF, alpha);
      final painter = _text(popup.text, size: 13, color: color);
      painter.paint(
        canvas,
        Offset(popup.x - painter.width / 2, popup.y - painter.height / 2),
      );
    }
  }

  /// 按量化后的透明度取缓存的 [Color]：同色同档位只构造一次，
  /// 淡出中的飘字、护盾与 Boss 核心不再每帧新建颜色对象。
  Color _fadeColor(int argb, double alpha) {
    final level = alpha <= 0
        ? 0
        : alpha >= 1
        ? 16
        : (alpha * 16).round();
    final key = argb * 24 + level;
    final cached = _colorCache[key];
    if (cached != null) return cached;
    if (_colorCache.length >= _maxCachedColors) _colorCache.clear();
    final color = Color(argb).withValues(alpha: level / 16);
    _colorCache[key] = color;
    return color;
  }

  TextPainter _text(
    String text, {
    double size = 12,
    Color color = Colors.white,
    FontWeight weight = FontWeight.w600,
  }) {
    final styles = _textCache[text] ??= <int, TextPainter>{};
    final styleKey =
        color.toARGB32() * 4096 + (size * 10).round() * 8 + weight.value ~/ 100;
    final cached = styles[styleKey];
    if (cached != null) return cached;
    if (_textPainterCount >= _maxCachedPainters) _evictOldestText();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: 0.4,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    styles[styleKey] = painter;
    _textPainterCount++;
    return painter;
  }

  /// 淘汰最早收录的一条文本及其全部字号/颜色变体。
  void _evictOldestText() {
    final oldest = _textCache.keys.first;
    final styles = _textCache.remove(oldest);
    if (styles == null) return;
    for (final painter in styles.values) {
      painter.dispose();
    }
    _textPainterCount -= styles.length;
  }

  /// 已缓存的文本排版数量，供测试确认逐帧复用而不是反复重建。
  int get cachedTextPainters => _textPainterCount;

  /// 已缓存的颜色数量，供测试确认量化后不再逐帧增长。
  int get cachedColors => _colorCache.length;
}
