import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../flame/sky_fighter_game.dart';
import '../game/achievements/achievement.dart';
import '../game/battle/battle_controller.dart';
import '../game/battle/battle_keys.dart';
import '../game/battle/battle_types.dart';
import '../game/battle/battle_tuning.dart';
import '../game/battle/double_tap.dart';
import '../game/battle/battle_viewport.dart';
import '../game/challenge/daily_challenge.dart';
import '../providers/settings_provider.dart';
import '../services/log_service.dart';
import '../services/sound_service.dart';
import '../utils/app_font.dart';
import '../utils/display_mode.dart';
import 'widgets/battle_hud.dart';
import 'widgets/battle_overlays.dart';
import 'widgets/space_backdrop.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, this.challenge});

  /// 每日挑战配置；为空时进入普通战斗。
  final DailyChallenge? challenge;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  BattleController? _controller;
  SkyFighterGame? _game;
  Size? _worldSize;
  Rect _field = Rect.zero;

  final FocusNode _focusNode = FocusNode(debugLabel: 'battle');
  final Set<LogicalKeyboardKey> _pressed = {};
  Offset? _dragLast;

  bool _paused = false;
  bool _resultVisible = false;
  bool _newRecord = false;
  bool _resultHandled = false;
  int _dailyBest = 0;
  List<Achievement> _newAchievements = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_controller?.phase == BattlePhase.playing) {
        _togglePause();
      }
    }
  }

  void _ensureGame(Size world) {
    if (_controller == null) {
      final settings = context.read<SettingsProvider>();
      final controller = BattleController(
        size: world,
        highScore: settings.highScore,
        challenge: widget.challenge,
      );
      final game = SkyFighterGame(
        controller: controller,
        logicRate: settings.logicRate,
        fontFamily: appFontFamily(),
      );
      controller.addListener(_onControllerChanged);
      _controller = controller;
      _game = game;
      _worldSize = world;
      final challenge = widget.challenge;
      LogService.info(
        '开始战斗: 战场 ${world.width.round()}x${world.height.round()}, '
        '逻辑 ${settings.logicRate.label}, 历史最高 ${settings.highScore}'
        '${challenge == null ? '' : ', 每日挑战 ${challenge.dateKey} ${challenge.modifier.label}'}',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        controller.start();
        _focusNode.requestFocus();
      });
      return;
    }
    if (world != _worldSize) {
      _worldSize = world;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller?.resize(world);
      });
    }
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.phase == BattlePhase.gameOver && !_resultHandled) {
      _resultHandled = true;
      unawaited(_handleGameOver());
    }
  }

  Future<void> _handleGameOver() async {
    final controller = _controller;
    if (controller == null) return;
    LogService.info(
      '战斗结束: 得分 ${controller.score}, 波次 ${controller.wave}, '
      '击破 ${controller.kills}, 存活 ${controller.survived.inSeconds}s',
    );
    // 留出坠机爆炸的演出时间再弹出结算。
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final outcome = await settings.finishRun(
      score: controller.score,
      wave: controller.wave,
      kills: controller.kills,
      bossKills: controller.bossKills,
      maxCombo: controller.maxCombo,
      challenge: widget.challenge,
    );
    if (!mounted) return;
    controller.setHighScore(settings.highScore);
    if (outcome.unlocked.isNotEmpty) {
      LogService.info(
        '解锁成就: ${outcome.unlocked.map((item) => item.title).join('、')}',
      );
    }
    // 结算面板盖住战场后，战场只剩静止画面，停掉引擎避免继续 60fps 全量重绘。
    _game?.pauseEngine();
    setState(() {
      _resultVisible = true;
      _newRecord = outcome.isRecord;
      _dailyBest = outcome.dailyBest;
      _newAchievements = outcome.unlocked;
      _paused = false;
    });
  }

  void _togglePause() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.phase == BattlePhase.playing) {
      controller.pause();
      _game?.pauseEngine();
      setState(() => _paused = true);
      SoundService.play(GameSound.ui);
    } else if (controller.phase == BattlePhase.paused) {
      _game?.resumeEngine();
      controller.resume();
      setState(() => _paused = false);
      _focusNode.requestFocus();
    }
  }

  void _restart() {
    final controller = _controller;
    if (controller == null) return;
    _resultHandled = false;
    setState(_resetResultState);
    _game?.resumeEngine();
    controller.start();
    _focusNode.requestFocus();
    LogService.info(
      widget.challenge == null
          ? '重新开始战斗'
          : '重新开始每日挑战 ${widget.challenge!.modifier.label}',
    );
  }

  /// 收起结算面板并清空上一局的结果，重开与首次进入共用同一份状态。
  void _resetResultState() {
    _resultVisible = false;
    _newRecord = false;
    _newAchievements = const [];
    _dailyBest = 0;
    _paused = false;
  }

  void _exitToHome() {
    Navigator.of(context).pop();
  }

  void _useBomb() {
    _controller?.useBomb();
  }

  final _doubleTap = DoubleTapDetector();
  int? _pointer;
  Duration _downAt = Duration.zero;
  Offset _downPos = Offset.zero;
  double _tapTravel = 0;
  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downAt = event.timeStamp;
    _downPos = event.localPosition;
    _tapTravel = 0;
    _dragLast = event.localPosition;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    if (_doubleTap.onUp(
      downAt: _downAt,
      upAt: event.timeStamp,
      downPos: _downPos,
      upPos: _tapTravel >= kTapMaxTravel
          ? _downPos + Offset(_tapTravel, 0)
          : event.localPosition,
    )) {
      _controller?.useResonance();
    }
    _pointer = null;
    _dragLast = null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    final last = _dragLast;
    if (last == null || _field.width <= 0) return;
    _tapTravel += (event.localPosition - last).distance;
    final scale = kWorldWidth / _field.width;
    _controller?.movePlayerBy((event.localPosition - last) * scale);
    _dragLast = event.localPosition;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyDownEvent) {
      _pressed.add(key);
    } else if (event is KeyUpEvent) {
      _pressed.remove(key);
    }
    _controller?.setMoveAxis(moveAxisForKeys(_pressed));
    _controller?.setFocusHeld(_pressed.any(isFocusKey));

    if (event is KeyDownEvent) {
      if (isResonanceKey(key)) {
        _controller?.useResonance();
      } else if (isBombKey(key)) {
        _useBomb();
      } else if (isPauseKey(key)) {
        _togglePause();
      }
    }

    return kBattleHandledKeys.contains(key)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF05070F),
      body: ImmersiveFullscreen(
        child: PopScope(
          canPop: _paused || _resultVisible,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _togglePause();
          },
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKey,
            onFocusChange: (hasFocus) {
              if (hasFocus) return;
              // 切换窗口或弹窗夺焦时清空按键，避免战机持续漂移。
              _pressed.clear();
              _controller?.setMoveAxis(Offset.zero);
              _controller?.setFocusHeld(false);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stage = Size(constraints.maxWidth, constraints.maxHeight);
                final field = BattleViewport.fit(stage);
                _field = field;
                _ensureGame(BattleViewport.worldSize(field.size));
                final controller = _controller!;
                final game = _game!;
                final playfield = Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: (event) {
                    if (_pointer == event.pointer) {
                      _pointer = null;
                      _dragLast = null;
                    }
                  },
                  child: GameWidget(key: ValueKey(game), game: game),
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const SpaceBackdrop(brightness: Brightness.dark),
                    Positioned.fromRect(
                      rect: field,
                      // 满屏时战场直接铺到屏幕边缘，不再加描边与圆角外框。
                      child: BattleViewport.fillsStage(field, stage)
                          ? playfield
                          : _PlayfieldFrame(child: playfield),
                    ),
                    // 战场铺满整屏，HUD 单独避开刘海与手势条。
                    Positioned.fill(
                      child: SafeArea(
                        child: AnimatedBuilder(
                          animation: controller,
                          builder: (context, _) => BattleHud(
                            controller: controller,
                            field: field,
                            stage: stage,
                            onPause: _togglePause,
                            onBomb: _useBomb,
                          ),
                        ),
                      ),
                    ),
                    if (_paused)
                      BattlePauseOverlay(
                        onResume: _togglePause,
                        onRestart: _restart,
                        onExit: _exitToHome,
                      ),
                    if (_resultVisible)
                      BattleResultOverlay(
                        score: controller.score,
                        best: controller.highScore,
                        wave: controller.wave,
                        kills: controller.kills,
                        survived: controller.survived,
                        isRecord: _newRecord,
                        challenge: widget.challenge,
                        dailyBest: _dailyBest,
                        unlocked: _newAchievements,
                        onRestart: _restart,
                        onExit: _exitToHome,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 战场外框：细描边与霓虹投影，把战斗区域和四周留白分开。
class _PlayfieldFrame extends StatelessWidget {
  const _PlayfieldFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x40A9E9FF)),
        boxShadow: const [
          BoxShadow(color: Color(0x3335C8FF), blurRadius: 30, spreadRadius: 2),
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(17), child: child),
    );
  }
}
