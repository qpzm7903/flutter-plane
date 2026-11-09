import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_types.dart';
import 'package:sky_fighter/game/battle/wave_director.dart';

void main() {
  test('教学编队、后期加压、边界与确定性', () {
    final a = WaveDirector(seed: 55), b = WaveDirector(seed: 55);
    for (var wave = 1; wave <= 80; wave++) {
      a.startNextWave();
      b.startNextWave();
      final aa = <SpawnRequest>[], bb = <SpawnRequest>[];
      for (var step = 0; step < 640; step++) {
        final ar = a.update(0.01), br = b.update(0.01);
        expect(ar.length, br.length);
        aa.addAll(ar);
        bb.addAll(br);
      }
      expect(a.spawning, isFalse);
      expect(b.spawning, isFalse);
      expect(aa.length, lessThanOrEqualTo(28));
      for (var i = 0; i < aa.length; i++) {
        expect(aa[i].x, inInclusiveRange(34, kWorldWidth - 34));
        expect(
          [aa[i].kind, aa[i].x, aa[i].pattern, aa[i].phase, aa[i].variant],
          [bb[i].kind, bb[i].x, bb[i].pattern, bb[i].phase, bb[i].variant],
        );
      }
      int count(EnemyKind k) => aa.where((r) => r.kind == k).length;
      if (wave == 1) {
        expect(aa, hasLength(6));
        expect(count(EnemyKind.scout), 6);
      }
      if (wave == 2) expect(count(EnemyKind.fighter), 1);
      if (wave <= 3) {
        expect(
          aa.every(
            (r) => [
              EnemyKind.scout,
              EnemyKind.fighter,
              EnemyKind.bomber,
            ].contains(r.kind),
          ),
          isTrue,
        );
      }
      if (wave == 13) {
        expect(count(EnemyKind.interceptor), 2);
        expect(count(EnemyKind.drone), 4);
        expect(count(EnemyKind.elite), 2);
        expect(aa, hasLength(24));
      }
      if (wave == 17) {
        expect(count(EnemyKind.fortress), 2);
        expect(aa, hasLength(24));
      }
    }
  });

  group('WaveDirector', () {
    test('首波在调用前保持待命', () {
      final director = WaveDirector();
      expect(director.wave, 0);
      expect(director.spawning, isFalse);
      expect(director.update(1), isEmpty);
    });

    test('每 4 波为 Boss 波', () {
      final director = WaveDirector(seed: 3);
      for (var i = 1; i <= 12; i++) {
        director.startNextWave();
        expect(director.wave, i);
        expect(director.bossWave, i % 4 == 0);
        while (director.spawning) {
          director.update(10);
        }
      }
    });

    test('生成请求在战场宽度内', () {
      final director = WaveDirector(seed: 11);
      for (var wave = 1; wave <= 10; wave++) {
        director.startNextWave();
        final requests = <SpawnRequest>[];
        while (director.spawning) {
          requests.addAll(director.update(10));
        }
        for (final request in requests) {
          expect(request.x, greaterThanOrEqualTo(34));
          expect(request.x, lessThanOrEqualTo(kWorldWidth - 34));
        }
        if (!director.bossWave) {
          expect(requests, isNotEmpty);
        }
      }
    });

    test('生成按延迟排队，不会同一帧全部出现', () {
      final director = WaveDirector(seed: 5)..startNextWave();
      final first = director.update(0.01);
      expect(first.length, lessThan(2));
      expect(director.spawning, isTrue);
      final rest = <SpawnRequest>[];
      for (var i = 0; i < 200; i++) {
        rest.addAll(director.update(0.1));
      }
      expect(rest, isNotEmpty);
      expect(director.spawning, isFalse);
    });

    test('高波次会加入轰炸机与精英机', () {
      final director = WaveDirector(seed: 9);
      director.startNextWave();
      while (director.spawning) {
        director.update(10);
      }
      for (var i = 0; i < 5; i++) {
        director.startNextWave();
        while (director.spawning) {
          director.update(10);
        }
      }
      director.startNextWave();
      final kinds = <EnemyKind>{};
      while (director.spawning) {
        kinds.addAll(director.update(10).map((request) => request.kind));
      }
      expect(kinds.contains(EnemyKind.elite), isTrue);
      expect(kinds.contains(EnemyKind.bomber), isTrue);
    });

    test('高波次加入自爆无人机、截击机与重装堡垒', () {
      final director = WaveDirector(seed: 21);
      for (var i = 0; i < 9; i++) {
        director.startNextWave();
        while (director.spawning) {
          director.update(10);
        }
      }
      // 第 9 波不是 Boss 波，应包含全部新增敌机。
      expect(director.wave, 9);
      expect(director.bossWave, isFalse);
      director.startNextWave();
      final kinds = <EnemyKind>{};
      while (director.spawning) {
        kinds.addAll(director.update(10).map((request) => request.kind));
      }
      expect(kinds, contains(EnemyKind.drone));
      expect(kinds, contains(EnemyKind.interceptor));
      expect(kinds, contains(EnemyKind.fortress));
    });

    test('Boss 形态按三种形态轮换，生成请求带上形态', () {
      final director = WaveDirector(seed: 13);
      final variants = <BossVariant>[];
      for (var wave = 1; wave <= 12; wave++) {
        director.startNextWave();
        if (director.bossWave) {
          variants.add(director.bossVariant);
          final requests = <SpawnRequest>[];
          while (director.spawning) {
            requests.addAll(director.update(10));
          }
          expect(requests, hasLength(1));
          expect(requests.single.kind, EnemyKind.boss);
          expect(requests.single.variant, director.bossVariant);
        } else {
          while (director.spawning) {
            director.update(10);
          }
        }
      }
      expect(variants, [
        BossVariant.scorpion,
        BossVariant.leviathan,
        BossVariant.wraith,
      ]);
    });

    test('updateInto 把到期请求写入调用方列表，队列空时不改动', () {
      final director = WaveDirector(seed: 31)..startNextWave();
      final out = <SpawnRequest>[];
      for (var i = 0; i < 300 && director.spawning; i++) {
        director.updateInto(0.1, out);
      }
      expect(out, isNotEmpty);
      expect(out.length, greaterThan(3));
      expect(director.spawning, isFalse);

      // 生成队列已清空：调用方列表原样保留，不会被清空或继续追写。
      final kept = <SpawnRequest>[
        const SpawnRequest(
          kind: EnemyKind.scout,
          x: 100,
          pattern: EnemyPattern.straight,
        ),
      ];
      director.updateInto(1, kept);
      expect(kept, hasLength(1));
    });
  });
}
