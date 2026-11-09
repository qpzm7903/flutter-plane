import 'package:flutter/material.dart';

import '../../game/battle/rules_text.dart';
import '../../theme/app_theme.dart';

/// 玩法说明弹窗：操作、目标、补给与连击规则。
Future<void> showHowToPlay(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _HowToPlayDialog(),
  );
}

class _HowToPlayDialog extends StatelessWidget {
  const _HowToPlayDialog();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.help_outline_rounded, color: colors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    '玩法说明',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const _Section(
                icon: Icons.touch_app_rounded,
                title: '操作',
                lines: [
                  '拖动屏幕任意位置移动战机，自动连续开火。',
                  '点击右下角炸弹按钮，清空敌弹并重创全场敌机。',
                  'Windows：方向键 / WASD 移动，空格或 B 放炸弹，Esc 暂停。',
                ],
              ),
              _Section(
                icon: Icons.flag_rounded,
                title: '目标',
                lines: battleGoalHints(),
              ),
              _Section(
                icon: Icons.card_giftcard_rounded,
                title: '补给',
                lines: supplyHints(),
              ),
              _Section(
                icon: Icons.account_tree_rounded,
                title: '进化路线',
                lines: routeHints(),
              ),
              _Section(
                icon: Icons.bolt_rounded,
                title: '连击',
                lines: comboHints(),
                accent: appAmber,
              ),
              _Section(
                icon: Icons.event_available_rounded,
                title: '每日挑战',
                lines: dailyChallengeHints(),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('明白了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.lines,
    this.accent,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = accent ?? colors.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 22),
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 12.2,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
