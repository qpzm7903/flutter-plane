import 'dart:ui';

/// 战机与僚机的矢量轮廓。
///
/// 战斗渲染与首页徽标共用同一份路径，避免两处各描一遍后外形悄悄走样。
final Path playerHullPath = Path()
  ..moveTo(0, -17)
  ..lineTo(4.5, -6)
  ..lineTo(14, 3)
  ..lineTo(14, 8.5)
  ..lineTo(5, 7)
  ..lineTo(3.2, 12)
  ..lineTo(-3.2, 12)
  ..lineTo(-5, 7)
  ..lineTo(-14, 8.5)
  ..lineTo(-14, 3)
  ..lineTo(-4.5, -6)
  ..close();

/// 僚机的小型护航轮廓。
final Path wingmanHullPath = Path()
  ..moveTo(0, -9)
  ..lineTo(6.5, 6)
  ..lineTo(0, 3.2)
  ..lineTo(-6.5, 6)
  ..close();

/// 重炮僚机：宽梯形机身与双炮管。
final Path wingmanHeavyHullPath = Path()
  ..moveTo(-4, -7)
  ..lineTo(4, -7)
  ..lineTo(9, 6)
  ..lineTo(-9, 6)
  ..close()
  ..addRect(const Rect.fromLTWH(-7, -12, 2.5, 12))
  ..addRect(const Rect.fromLTWH(4.5, -12, 2.5, 12));

/// 护卫卫星：半径 6 的六边形，渲染时复用。
final Path wingmanGuardHullPath = Path()
  ..moveTo(0, -6)
  ..lineTo(5.196, -3)
  ..lineTo(5.196, 3)
  ..lineTo(0, 6)
  ..lineTo(-5.196, 3)
  ..lineTo(-5.196, -3)
  ..close();
