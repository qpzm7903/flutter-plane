import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_controller.dart';

void main() {
  test('v0.6 first two waves deterministic frame snapshot', () {
    final c = BattleController(size: const Size(400, 700), seed: 42)..start();
    addTearDown(c.dispose);
    c.player.invuln = 10000;
    var hash = 2166136261, frames = 0;
    while (c.wave < 3 && frames < 30000) {
      if (frames % 180 == 0) {
        c.setMoveAxis(Offset(frames % 360 == 0 ? 0.15 : -0.15, 0));
      }
      c.update(1 / 60);
      frames++;
      final p = c.player;
      final state = [
        c.wave,
        c.score,
        c.combo,
        c.comboTimer,
        c.kills,
        c.elapsed,
        c.phase.index,
        p.x,
        p.y,
        p.lives,
        p.bombs,
        p.weaponLevel,
        p.overdrive,
        p.route?.index,
        p.invuln,
        p.fireCooldown,
        p.tilt,
        [
          for (final e in c.enemies)
            [
              e.kind.index,
              e.pattern.index,
              e.x,
              e.y,
              e.hp,
              e.age,
              e.fireCooldown,
              e.dead,
            ],
        ],
        [
          for (final b in c.playerBullets)
            [
              b.x,
              b.y,
              b.vx,
              b.vy,
              b.radius,
              b.damage,
              b.kind,
              b.pierce,
              b.dead,
            ],
        ],
        [
          for (final b in c.enemyBullets)
            [b.x, b.y, b.vx, b.vy, b.radius, b.damage, b.kind, b.dead],
        ],
        [
          for (final u in c.powerUps) [u.x, u.y, u.kind.index, u.age, u.dead],
        ],
        [
          for (final v in c.particles)
            [v.x, v.y, v.vx, v.vy, v.life, v.size, v.color, v.kind.index],
        ],
        [
          for (final v in c.popups) [v.x, v.y, v.text, v.life],
        ],
      ];
      // Wave-three teaching popup is a v0.7 feature; stop before hashing its frame.
      if (c.wave >= 3) break;
      for (final byte in utf8.encode(jsonEncode(state))) {
        hash = ((hash ^ byte) * 16777619) & 0xffffffff;
      }
    }
    // Captured from v0.6.0 commit 3bbb5b7 with this exact fixed-step script.
    expect(frames, 2462);
    expect(hash, 752886552);
    expect(c.player.focus, 0);
    expect(c.player.resonance, 0);
    expect(c.player.charge, 0);
    expect(c.wave, 3);
  });
}
