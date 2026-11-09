import 'package:flutter/services.dart';

/// 战斗键盘映射：方向键 / WASD 移动，空格或 B 放炸弹，Esc 或 P 暂停。
///
/// 这组映射抽成纯函数后，按键处理只需一次集合查询，不必在每次按键事件里
/// 重新构造「已处理按键」集合，也可以直接单测。

final Set<LogicalKeyboardKey> kBattleHandledKeys = {
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
};

/// 当前按下的方向键对应的移动轴，长度不超过 1。
Offset moveAxisForKeys(Set<LogicalKeyboardKey> pressed) {
  final left =
      pressed.contains(LogicalKeyboardKey.arrowLeft) ||
      pressed.contains(LogicalKeyboardKey.keyA);
  final right =
      pressed.contains(LogicalKeyboardKey.arrowRight) ||
      pressed.contains(LogicalKeyboardKey.keyD);
  final up =
      pressed.contains(LogicalKeyboardKey.arrowUp) ||
      pressed.contains(LogicalKeyboardKey.keyW);
  final down =
      pressed.contains(LogicalKeyboardKey.arrowDown) ||
      pressed.contains(LogicalKeyboardKey.keyS);
  return Offset(
    (right ? 1 : 0) - (left ? 1 : 0),
    (down ? 1 : 0) - (up ? 1 : 0),
  );
}

/// 释放全屏炸弹。
bool isBombKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyB;

/// 暂停 / 继续。
bool isPauseKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyP;

bool isFocusKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight;
bool isResonanceKey(LogicalKeyboardKey key) => key == LogicalKeyboardKey.keyR;
