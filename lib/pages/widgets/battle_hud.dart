import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/battle/battle_controller.dart';
import '../../game/battle/battle_types.dart';
import '../../game/battle/rules_text.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'hud_stats.dart';

/// 战斗 HUD：得分、生命、炸弹、波次、连击与 Boss 血条。
///
/// 全部元素悬浮在战场四周，不参与战场尺寸计算，提示变化不会推动战场布局。
class BattleHud extends StatelessWidget {
  const BattleHud({
    super.key,
    required this.controller,
    required this.field,
    required this.stage,
    required this.onPause,
    required this.onBomb,
  });

  final BattleController controller;
  final Rect field;
  final Size stage;
  final VoidCallback onPause;
  final VoidCallback onBomb;

  static const Color _ink = Color(0xF2FFFFFF);
  static const Color _muted = Color(0x99FFFFFF);

  @override
  Widget build(BuildContext context) {
    final leftMargin = field.left;
    final rightMargin = stage.width - field.right;
    final wide = leftMargin >= 176 && rightMargin >= 176;

    return Stack(
      children: [
        if (wide)
          ..._wideLayout(leftMargin, rightMargin)
        else
          ..._compactLayout(),
        if (controller.boss != null) _bossBar(wide),
        _hint(),
      ],
    );
  }

  // ---------------------------------------------------------------- 紧凑布局

  List<Widget> _compactLayout() => [
    Positioned(left: 10, top: 8, child: _scorePanel(compact: true)),
    Positioned(
      right: 8,
      top: 8,
      child: _roundButton(
        icon: Icons.pause_rounded,
        tooltip: '暂停',
        onTap: onPause,
      ),
    ),
    if (controller.combo >= 2)
      Positioned(right: 10, top: 62, child: _comboBadge()),
    Positioned(
      left: 10,
      top: 76,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusStrip(),
          const SizedBox(height: 6),
          _resonanceMeter(),
        ],
      ),
    ),
    Positioned(left: 10, bottom: 10, child: _wavePanel(compact: true)),
    Positioned(right: 12, bottom: 12, child: _bombButton()),
  ];

  // ---------------------------------------------------------------- 宽屏布局
  // 桌面与大平板把 HUD 放进战场两侧的留白，战场本身保持干净。

  List<Widget> _wideLayout(double leftMargin, double rightMargin) {
    final panelWidth = (leftMargin - 32).clamp(150.0, 210.0);
    return [
      Positioned(
        left: 16,
        top: 18,
        width: panelWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _scorePanel(),
            const SizedBox(height: 10),
            _wavePanel(column: true),
            const SizedBox(height: 10),
            _statusPanel(),
            if (controller.combo >= 2) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: _comboBadge()),
            ],
          ],
        ),
      ),
      Positioned(
        right: 16,
        top: 18,
        width: (rightMargin - 32).clamp(120.0, 190.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _roundButton(
                icon: Icons.pause_rounded,
                tooltip: '暂停',
                onTap: onPause,
              ),
            ),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerRight, child: _bombButton()),
          ],
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------- 组件

  Widget _panel({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xC20A1326),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x33FFFFFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _scorePanel({bool compact = false}) => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '得分',
          style: TextStyle(
            fontSize: 9.5,
            letterSpacing: 2.4,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        Text(
          formatScore(controller.score),
          style: TextStyle(
            fontSize: compact ? 21 : 27,
            height: 1.18,
            fontWeight: FontWeight.w800,
            color: _ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          '最高 ${formatScore(controller.highScore)}',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: appAmber,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );

  /// 会随战斗变化的状态条目来自 [hudStatsFor]，紧凑横条与宽屏面板不会
  /// 各自维护一份而出现数值不一致。
  List<HudStat> _statusStats() => hudStatsFor(controller.player);

  Widget _statusStrip() {
    final stats = _statusStats();
    return _panel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Icon(
              stats[i].icon,
              size: stats[i].stripIconSize,
              color: stats[i].color,
            ),
            const SizedBox(width: 3),
            Text(
              stats[i].shortValue,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPanel() {
    final stats = _statusStats();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '战机状态',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.6,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (var i = 0; i < stats.length; i++) ...[
            SizedBox(height: i == 0 ? 8 : 6),
            _statRow(stats[i]),
          ],
          const SizedBox(height: 6),
          _resonanceMeter(wide: true),
        ],
      ),
    );
  }

  Widget _resonanceMeter({bool wide = false}) => IgnorePointer(
    child: ValueListenableBuilder<int>(
      valueListenable: controller.resonanceMeter,
      builder: (context, value, child) {
        final meter = resonanceMeterFor(value, controller.wave);
        if (!meter.visible) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResonanceBar(meter: meter),
            if (wide)
              Text(
                '擦弹 ${controller.grazes}',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
          ],
        );
      },
    ),
  );

  Widget _statRow(HudStat stat) => Row(
    children: [
      Icon(stat.icon, size: 15, color: stat.color),
      const SizedBox(width: 6),
      Text(stat.label, style: const TextStyle(fontSize: 11.5, color: _muted)),
      const Spacer(),
      Text(
        stat.fullValue,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
    ],
  );

  Widget _wavePanel({bool compact = false, bool column = false}) => _panel(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 9 : 12,
      vertical: compact ? 6 : 9,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.graphic_eq_rounded, size: 15, color: appCyan),
        const SizedBox(width: 5),
        Text(
          controller.waveLabel,
          style: TextStyle(
            fontSize: compact ? 11.5 : 12.5,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        if (column) const Spacer() else const SizedBox(width: 10),
        Text(
          controller.challenge == null
              ? firepowerLabel(controller.player)
              : '挑战 · ${controller.challengeModifier.label}',
          style: TextStyle(
            fontSize: compact ? 10.5 : 11,
            color: controller.challenge == null
                ? const Color(0xFF9BE8FF)
                : appAmber,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _bossBar(bool wide) {
    final boss = controller.boss;
    if (boss == null) return const SizedBox.shrink();
    return Positioned(
      left: (stage.width - math.min(360, stage.width - 24)) / 2,
      top: wide ? 14 : 112,
      width: math.min(360, stage.width - 24),
      child: _panel(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        // 血量走独立通知器：Boss 战期间只有这条血条重建，HUD 其余部分不动。
        child: ValueListenableBuilder<int>(
          valueListenable: controller.bossHp,
          builder: (context, permille, _) {
            final ratio = permille > 0
                ? permille / 1000
                : boss.hpRatio.clamp(0.0, 1.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: appCrimson,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        controller.bossName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Text(
                      '${(ratio * 100).ceil()}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: appCrimson,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(height: 6, color: const Color(0x33FFFFFF)),
                      FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          height: 6,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [appCrimson, appAmber],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _comboBadge() {
    final multiplier = controller.multiplier;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xC21A1206),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: (multiplier > 1 ? appAmber : const Color(0x66FFFFFF))
                .withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${controller.combo} 连击',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            if (multiplier > 1) ...[
              const SizedBox(width: 6),
              Text(
                '×$multiplier',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: appAmber,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) => Container(
    decoration: BoxDecoration(
      color: const Color(0xC20A1326),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x44FFFFFF)),
    ),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      color: _ink,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
    ),
  );

  Widget _bombButton() {
    final enabled = controller.player.bombs > 0;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onBomb : null,
          customBorder: const CircleBorder(),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFFFFB74D), Color(0xFFE0524C)],
                center: Alignment(-0.3, -0.4),
              ),
              border: Border.all(color: const Color(0xFFFFE0A3), width: 1.4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66FF6B4A),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 28,
                  color: Colors.white,
                ),
                Positioned(
                  right: 6,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC1A0B06),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${controller.player.bombs}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint() {
    if (controller.elapsed >= BattleController.hintDuration ||
        controller.phase != BattlePhase.playing) {
      return const SizedBox.shrink();
    }
    final fade = (1 - controller.elapsed / BattleController.hintDuration).clamp(
      0.0,
      1.0,
    );
    return Positioned(
      left: 0,
      right: 0,
      bottom: 92,
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: fade * 0.85,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0x99061120),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: const Text(
                kBattleInputHint,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xE6FFFFFF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResonanceBar extends StatefulWidget {
  const _ResonanceBar({required this.meter});
  final HudMeter meter;
  @override
  State<_ResonanceBar> createState() => _ResonanceBarState();
}

class _ResonanceBarState extends State<_ResonanceBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(microseconds: 833333),
  );
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _ResonanceBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.meter.ready && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.meter.ready) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, child) => Semantics(
      label: widget.meter.label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '共鸣',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(width: 5),
          Opacity(
            opacity: widget.meter.ready
                ? 0.75 + 0.25 * math.sin(_pulse.value * math.pi * 2)
                : 1,
            child: Container(
              width: 88,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: widget.meter.ratio,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: widget.meter.ready
                          ? [appAmber, const Color(0xFFFFE9A8)]
                          : [appCyan, const Color(0xFF2EF2A8)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.meter.ready)
            const Padding(
              padding: EdgeInsets.only(left: 5),
              child: Text(
                '双击',
                style: TextStyle(fontSize: 11, color: appAmber),
              ),
            ),
        ],
      ),
    ),
  );
}
