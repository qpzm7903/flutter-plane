import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_controller.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/challenge/daily_challenge.dart';
import 'package:sky_fighter/pages/widgets/battle_hud.dart';

Future<void> pumpHud(WidgetTester tester, BattleController controller) async {
  await tester.binding.setSurfaceSize(const Size(400, 820));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF05070F),
        body: BattleHud(
          controller: controller,
          field: const Rect.fromLTWH(0, 0, 400, 820),
          stage: const Size(400, 820),
          onPause: () {},
          onBomb: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('320 dp 满状态过载 HUD 无溢出且两处火力一致', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = BattleController(size: const Size(400, 700))..start();
    addTearDown(c.dispose);
    c.wave = 5;
    c.player.resonance = 100;
    c.update(0.1);
    c.player
      ..lives = 5
      ..bombs = 3
      ..weaponLevel = 6
      ..overdrive = 1
      ..route = WeaponRoute.focus
      ..wingmen = 3
      ..rapid = 12;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BattleHud(
            controller: c,
            field: const Rect.fromLTWH(0, 0, 320, 700),
            stage: const Size(320, 700),
            onPause: () {},
            onBomb: () {},
          ),
        ),
      ),
    );
    expect(find.text('双击'), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(find.text('7聚'), findsOneWidget);
    expect(find.text('火力 7 · 聚能'), findsOneWidget);
    expect(find.text('12s'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑布局展示得分、生命与炸弹', (tester) async {
    final controller = BattleController(size: const Size(400, 820));
    addTearDown(controller.dispose);
    await pumpHud(tester, controller);

    expect(find.text('得分'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('最高 0'), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsWidgets);
  });

  testWidgets('连击达到阈值时展示倍率', (tester) async {
    final controller = BattleController(size: const Size(400, 820))..combo = 30;
    addTearDown(controller.dispose);
    await pumpHud(tester, controller);

    expect(find.text('30 连击'), findsOneWidget);
    // 生命图标同样是 ×3，连击倍率与生命各一处。
    expect(find.text('×3'), findsNWidgets(2));
  });

  testWidgets('急速射击生效时展示倒计时', (tester) async {
    final controller = BattleController(size: const Size(400, 820));
    addTearDown(controller.dispose);
    controller.player.rapid = 5.4;
    await pumpHud(tester, controller);

    expect(find.byIcon(Icons.timer_rounded), findsOneWidget);
    expect(find.text('6s'), findsOneWidget);
  });

  testWidgets('僚机编队生效时展示数量', (tester) async {
    final controller = BattleController(size: const Size(400, 820));
    addTearDown(controller.dispose);
    controller.player.wingmen = 2;
    await pumpHud(tester, controller);

    expect(find.byIcon(Icons.flight_rounded), findsOneWidget);
    expect(find.text('×2'), findsNWidgets(2));
  });

  testWidgets('Boss 出现时展示名称与血条', (tester) async {
    final controller = BattleController(size: const Size(400, 820))..wave = 4;
    controller.enemies.add(
      Enemy(
        kind: EnemyKind.boss,
        pattern: EnemyPattern.hover,
        x: 200,
        y: 100,
        difficulty: 1,
      ),
    );
    addTearDown(controller.dispose);
    await pumpHud(tester, controller);

    expect(find.text('赤蝎母舰'), findsOneWidget);
    expect(find.text('第 4 波'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('Boss 血条随独立通知器更新，无需重建整棵 HUD', (tester) async {
    final controller = BattleController(size: const Size(400, 820))..start();
    addTearDown(controller.dispose);
    final boss = Enemy(
      kind: EnemyKind.boss,
      pattern: EnemyPattern.hover,
      x: 200,
      y: 100,
      difficulty: 1,
    );
    controller.wave = 4;
    controller.enemies.add(boss);
    await pumpHud(tester, controller);
    expect(find.text('100%'), findsOneWidget);

    boss.hp = boss.maxHp * 0.5;
    // 只推进逻辑，不触发控制器对 HUD 主体的通知。
    for (var i = 0; i < 12; i++) {
      controller.update(1 / 60);
    }
    await tester.pump();

    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('每日挑战展示战场修正', (tester) async {
    final controller = BattleController(
      size: const Size(400, 820),
      challenge: const DailyChallenge(
        dateKey: '20261108',
        seed: 7,
        modifier: ChallengeModifier.barrage,
      ),
    )..start();
    addTearDown(controller.dispose);
    await pumpHud(tester, controller);

    expect(find.text('挑战 · 弹幕压制'), findsOneWidget);
  });

  testWidgets('宽屏把 HUD 放到战场两侧', (tester) async {
    final controller = BattleController(size: const Size(400, 820));
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BattleHud(
            controller: controller,
            field: const Rect.fromLTWH(400, 0, 400, 820),
            stage: const Size(1200, 860),
            onPause: () {},
            onBomb: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('战机状态'), findsOneWidget);
    expect(find.text('火力'), findsOneWidget);
    expect(find.text('待命'), findsOneWidget);
  });

  testWidgets('宽屏面板展示完整的急速倒计时', (tester) async {
    final controller = BattleController(size: const Size(400, 820));
    addTearDown(controller.dispose);
    controller.player.rapid = 5.4;
    await tester.binding.setSurfaceSize(const Size(1200, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BattleHud(
            controller: controller,
            field: const Rect.fromLTWH(400, 0, 400, 820),
            stage: const Size(1200, 860),
            onPause: () {},
            onBomb: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('急速'), findsOneWidget);
    expect(find.text('6 秒'), findsOneWidget);
    expect(find.byIcon(Icons.timer_rounded), findsOneWidget);
  });
}
