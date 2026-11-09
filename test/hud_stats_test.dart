import 'package:sky_fighter/game/battle/battle_tuning.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/pages/widgets/hud_stats.dart';

Player buildPlayer() => Player(x: 200, y: 600);

void main() {
  for (final route in WeaponRoute.values) {
    test('$route HUD 火力简写、完整值、颜色及共享文案', () {
      final p = buildPlayer()
        ..weaponLevel = 6
        ..overdrive = 1
        ..route = route
        ..wingmen = 3;
      final spec = kWeaponRoutes[route]!;
      final stat = hudStatsFor(p)[2];
      expect(stat.shortValue, '7${spec.glyph}');
      expect(stat.fullValue, '7 级 · ${spec.label}');
      expect(stat.color.toARGB32(), spec.argb);
      expect(firepowerLabel(p), '火力 7 · ${spec.label}');
      expect(hudStatsFor(p)[3].shortValue, '×3');
      p
        ..overdrive = 0
        ..route = null;
      expect(firepowerLabel(p), '火力 6');
    });
  }

  group('HUD 状态条目', () {
    test('默认展示生命、炸弹与火力', () {
      final stats = hudStatsFor(buildPlayer());
      expect(stats.map((stat) => stat.label), ['生命', '炸弹', '火力']);
      expect(stats[0].shortValue, '×3');
      expect(stats[0].fullValue, '3');
      expect(stats[2].shortValue, '1');
      expect(stats[2].fullValue, '1 级');
    });

    test('僚机与急速只在生效时出现', () {
      final player = buildPlayer()
        ..wingmen = 2
        ..rapid = 4.2;
      final stats = hudStatsFor(player);
      expect(stats.map((stat) => stat.label), ['生命', '炸弹', '火力', '僚机', '急速']);
      expect(stats[3].shortValue, '×2');
      expect(stats[3].fullValue, '2 架');
      expect(stats[4].shortValue, '5s');
      expect(stats[4].fullValue, '5 秒');
    });

    test('每条状态都带图标与配色', () {
      final player = buildPlayer()
        ..lives = 5
        ..bombs = 3
        ..weaponLevel = Player.maxWeaponLevel
        ..wingmen = 1
        ..rapid = 1;
      for (final stat in hudStatsFor(player)) {
        expect(stat.shortValue, isNotEmpty);
        expect(stat.fullValue, isNotEmpty);
        expect(stat.color.a, greaterThan(0));
        expect(stat.stripIconSize, greaterThan(0));
      }
    });
  });
}
