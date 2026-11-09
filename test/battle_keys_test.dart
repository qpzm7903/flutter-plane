import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sky_fighter/game/battle/battle_keys.dart';

void main() {
  group('方向键映射', () {
    test('方向键与 WASD 都能驱动移动轴', () {
      expect(
        moveAxisForKeys({LogicalKeyboardKey.arrowLeft}),
        const Offset(-1, 0),
      );
      expect(moveAxisForKeys({LogicalKeyboardKey.keyD}), const Offset(1, 0));
      expect(
        moveAxisForKeys({LogicalKeyboardKey.arrowUp}),
        const Offset(0, -1),
      );
      expect(moveAxisForKeys({LogicalKeyboardKey.keyS}), const Offset(0, 1));
    });

    test('斜向移动轴长度为 1', () {
      final axis = moveAxisForKeys({
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowDown,
      });
      expect(axis.dx, -1);
      expect(axis.dy, 1);
      expect(axis.distance, closeTo(1.4142, 0.0001));
    });

    test('相反方向同时按下时互相抵消', () {
      expect(
        moveAxisForKeys({
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.keyD,
        }),
        Offset.zero,
      );
      expect(
        moveAxisForKeys({
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.arrowDown,
        }),
        Offset.zero,
      );
    });

    test('没有按键时保持静止', () {
      expect(moveAxisForKeys({}), Offset.zero);
    });
  });

  group('功能键', () {
    test('Shift 凝神与 R 共鸣', () {
      expect(isFocusKey(LogicalKeyboardKey.shiftLeft), isTrue);
      expect(isFocusKey(LogicalKeyboardKey.shiftRight), isTrue);
      expect(isFocusKey(LogicalKeyboardKey.keyR), isFalse);
      expect(isResonanceKey(LogicalKeyboardKey.keyR), isTrue);
      expect(isResonanceKey(LogicalKeyboardKey.keyB), isFalse);
    });
    test('空格与 B 释放炸弹', () {
      expect(isBombKey(LogicalKeyboardKey.space), isTrue);
      expect(isBombKey(LogicalKeyboardKey.keyB), isTrue);
      expect(isBombKey(LogicalKeyboardKey.keyP), isFalse);
    });

    test('Esc 与 P 暂停', () {
      expect(isPauseKey(LogicalKeyboardKey.escape), isTrue);
      expect(isPauseKey(LogicalKeyboardKey.keyP), isTrue);
      expect(isPauseKey(LogicalKeyboardKey.space), isFalse);
    });

    test('已处理按键集合覆盖全部操作且不吞掉普通按键', () {
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.escape,
      ]) {
        expect(kBattleHandledKeys, contains(key));
      }
      expect(kBattleHandledKeys, hasLength(15));
      expect(kBattleHandledKeys, isNot(contains(LogicalKeyboardKey.keyQ)));
    });
  });
}
