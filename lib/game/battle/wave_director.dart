import 'dart:math' as math;

import 'battle_types.dart';
import 'boss_catalog.dart';

/// 一条待生成的敌机记录。
class SpawnRequest {
  const SpawnRequest({
    required this.kind,
    required this.x,
    required this.pattern,
    this.phase = 0,
    this.variant = BossVariant.scorpion,
  });

  final EnemyKind kind;
  final double x;
  final EnemyPattern pattern;
  final double phase;
  final BossVariant variant;
}

class _PendingSpawn {
  _PendingSpawn(this.request, this.delay);

  final SpawnRequest request;
  double delay;
}

/// 波次调度：按关卡生成编队，每 4 波出现一次 Boss。
///
/// 只负责「什么时候、在哪里生成什么敌机」，不持有战场状态，便于单独测试。
class WaveDirector {
  WaveDirector({int seed = 20261107}) : _rng = math.Random(seed);

  final math.Random _rng;
  final List<_PendingSpawn> _pending = [];

  int wave = 0;
  bool bossWave = false;
  BossVariant bossVariant = BossVariant.scorpion;

  bool get spawning => _pending.isNotEmpty;

  /// 推进生成队列，返回本帧到期的敌机。
  List<SpawnRequest> update(double dt) {
    final ready = <SpawnRequest>[];
    updateInto(dt, ready);
    return ready;
  }

  /// 推进生成队列，把本帧到期的敌机追加到 [out]。
  ///
  /// 战斗循环传入自己的复用列表，编队展开期间每步都不必新建中转 List。
  void updateInto(double dt, List<SpawnRequest> out) {
    if (_pending.isEmpty) return;
    for (final item in _pending) {
      item.delay -= dt;
    }
    while (_pending.isNotEmpty && _pending.first.delay <= 0) {
      out.add(_pending.removeAt(0).request);
    }
  }

  /// 开始下一波：Boss 波只生成 Boss，其余按关卡组合编队。
  void startNextWave() {
    wave++;
    bossWave = wave % kBossWaveInterval == 0;
    _pending.clear();
    if (bossWave) {
      bossVariant = bossVariantForWave(wave);
      _pending.add(
        _PendingSpawn(
          SpawnRequest(
            kind: EnemyKind.boss,
            x: kWorldWidth / 2,
            pattern: EnemyPattern.hover,
            variant: bossVariant,
          ),
          0.4,
        ),
      );
      return;
    }
    for (final entry in _buildFormation()) {
      _pending.add(_PendingSpawn(entry.request, entry.delay));
    }
  }

  List<_PendingSpawn> _buildFormation() {
    final entries = <_PendingSpawn>[];
    final tier = wave;

    void add(
      EnemyKind kind,
      double x,
      EnemyPattern pattern,
      double delay, {
      double phase = 0,
    }) {
      entries.add(
        _PendingSpawn(
          SpawnRequest(
            kind: kind,
            x: clampDouble(x, 34, kWorldWidth - 34),
            pattern: pattern,
            phase: phase,
          ),
          delay,
        ),
      );
    }

    // V 形侦察机编队，从正中压下来。
    final vCount = tier <= 1 ? 3 : 3 + (tier + 1) % 3;
    for (var i = 0; i < vCount; i++) {
      final offset = (i - (vCount - 1) / 2) * 32;
      add(
        EnemyKind.scout,
        kWorldWidth / 2 + offset,
        EnemyPattern.sine,
        0.15 * i,
        phase: 0.17 * i,
      );
    }

    // 横排侦察机，间隔落下。
    final lineCount = tier <= 1 ? 3 : 3 + tier % 3;
    final lineStart = 70 + _rng.nextDouble() * 40;
    for (var i = 0; i < lineCount; i++) {
      add(
        EnemyKind.scout,
        lineStart + i * (kWorldWidth - 2 * lineStart) / (lineCount - 1),
        i.isEven ? EnemyPattern.straight : EnemyPattern.sine,
        1.4 + 0.22 * i,
        phase: 0.31 * i,
      );
    }

    if (tier >= 2) {
      final left = _rng.nextBool();
      add(
        EnemyKind.fighter,
        left ? 110 : kWorldWidth - 110,
        EnemyPattern.straight,
        2.5,
      );
      if (tier != 2) {
        add(
          EnemyKind.fighter,
          left ? kWorldWidth - 110 : 110,
          EnemyPattern.dive,
          2.75,
          phase: 0.4,
        );
      }
    }

    if (tier >= 3) {
      add(
        EnemyKind.bomber,
        kWorldWidth / 2 + (_rng.nextDouble() - 0.5) * 90,
        EnemyPattern.dive,
        3.6,
      );
    }

    // 自爆无人机：左右夹击，追着玩家俯冲。
    if (tier >= 4) {
      for (var i = 0; i < 2; i++) {
        add(
          EnemyKind.drone,
          i.isEven ? 92 : kWorldWidth - 92,
          EnemyPattern.chase,
          3.3 + 0.35 * i,
          phase: 0.5 * i,
        );
      }
    }

    // 截击机：从侧翼高速切入，单发快弹点射。
    if (tier >= 5) {
      final fromLeft = _rng.nextBool();
      add(
        EnemyKind.elite,
        fromLeft ? 96 : kWorldWidth - 96,
        EnemyPattern.hover,
        4.4,
        phase: _rng.nextDouble(),
      );
      add(
        EnemyKind.interceptor,
        fromLeft ? kWorldWidth - 74 : 74,
        EnemyPattern.dive,
        3.9,
        phase: 0.25,
      );
      if (tier >= 11) {
        add(
          EnemyKind.elite,
          fromLeft ? kWorldWidth - 96 : 96,
          EnemyPattern.hover,
          5.8,
        );
      }
      if (tier >= 13) {
        add(
          EnemyKind.interceptor,
          fromLeft ? 74 : kWorldWidth - 74,
          EnemyPattern.dive,
          4.2,
        );
        add(EnemyKind.drone, 150, EnemyPattern.chase, 4.6);
        add(EnemyKind.drone, kWorldWidth - 150, EnemyPattern.chase, 4.95);
      }
    }

    if (tier >= 7) {
      for (var i = 0; i < 2; i++) {
        add(
          EnemyKind.fighter,
          kWorldWidth / 2 + (i.isEven ? -60 : 60),
          EnemyPattern.sine,
          5.2 + 0.3 * i,
          phase: 0.2 * i,
        );
      }
    }

    // 重装堡垒：悬停后环形齐射，血厚且掉率高。
    if (tier >= 8) {
      add(
        EnemyKind.fortress,
        tier >= 17
            ? kWorldWidth / 2 - 85
            : kWorldWidth / 2 + (_rng.nextDouble() - 0.5) * 60,
        EnemyPattern.hover,
        4.9,
        phase: _rng.nextDouble(),
      );
    }

    if (tier >= 17) {
      add(EnemyKind.fortress, kWorldWidth / 2 + 85, EnemyPattern.hover, 5.4);
    }

    if (tier >= 9) {
      add(
        EnemyKind.bomber,
        kWorldWidth / 2,
        EnemyPattern.straight,
        6.0,
        phase: 0.6,
      );
    }
    // 后期编队按门槛追加，提交前按时间排序，避免较早增援被队首阻塞。
    entries.sort((a, b) => a.delay.compareTo(b.delay));
    return entries;
  }
}
