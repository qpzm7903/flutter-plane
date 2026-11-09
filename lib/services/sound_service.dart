import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_engine.dart';
import 'log_service.dart';
import 'synth_worker.dart';
import 'tone_synth.dart';

/// 战斗反馈类型，决定提示音与震动的强弱。
enum GameSound {
  shoot,
  lance,
  resonance,
  explosion,
  bigExplosion,
  powerUp,
  playerHit,
  bomb,
  gameOver,
  warning,
  ui,
}

/// 战斗音效与触感反馈。
///
/// 音效由 [synthesizeWav] 在运行时合成，不随包携带音频文件；合成好的
/// WAV 交给 flutter_soloud 的内存音源播放，三端共用同一套实现。
class SoundService {
  SoundService._();

  static bool soundEnabled = true;
  static bool hapticsEnabled = true;

  /// 测试注入的音频出口，非空时不再触碰平台播放器。
  @visibleForTesting
  static void Function(GameSound sound)? sink;

  static final Map<GameSound, AudioSource> _sources = {};
  static final Map<GameSound, Uint8List> _clips = {};
  static Future<void>? _loading;
  static bool _loadFailed = false;

  /// 各反馈的合成配方：射击短促、爆炸厚重、拾取上行、受伤下行。
  static const Map<GameSound, List<SynthNote>> presets = {
    GameSound.shoot: [
      SynthNote(
        frequency: 1500,
        start: 0,
        duration: 0.045,
        gain: 0.16,
        sweep: 0.62,
        decay: 3.6,
        brightness: 0.7,
      ),
      SynthNote(
        frequency: 760,
        start: 0.004,
        duration: 0.05,
        gain: 0.09,
        sweep: 0.8,
        decay: 5,
      ),
    ],
    GameSound.warning: [
      SynthNote(
        frequency: 320,
        start: 0,
        duration: 0.16,
        gain: 0.3,
        sweep: 1.6,
        decay: 2.2,
        brightness: 0.8,
      ),
      SynthNote(
        frequency: 240,
        start: 0.2,
        duration: 0.22,
        gain: 0.26,
        sweep: 1.4,
        decay: 2,
      ),
    ],
    GameSound.explosion: [
      SynthNote(
        frequency: 220,
        start: 0,
        duration: 0.28,
        sweep: 0.32,
        decay: 3.4,
        noise: 0.9,
      ),
      SynthNote(
        frequency: 96,
        start: 0,
        duration: 0.34,
        gain: 0.45,
        sweep: 0.6,
        decay: 3,
        noise: 0.35,
      ),
    ],
    GameSound.bigExplosion: [
      SynthNote(
        frequency: 150,
        start: 0,
        duration: 0.7,
        gain: 0.7,
        sweep: 0.3,
        decay: 2.2,
        noise: 0.85,
      ),
      SynthNote(
        frequency: 62,
        start: 0.02,
        duration: 0.9,
        gain: 0.6,
        sweep: 0.5,
        decay: 2,
        noise: 0.4,
      ),
      SynthNote(
        frequency: 900,
        start: 0,
        duration: 0.12,
        gain: 0.2,
        noise: 0.9,
        decay: 6,
      ),
    ],
    GameSound.lance: [
      SynthNote(
        frequency: 1100,
        start: 0,
        duration: 0.18,
        gain: 0.8,
        sweep: 2600 / 1100,
        brightness: 1.5,
      ),
    ],
    GameSound.resonance: [
      SynthNote(frequency: 90, start: 0, duration: 0.32, gain: 0.6, decay: 2),
      SynthNote(frequency: 440, start: 0, duration: 0.32, gain: 0.4, sweep: 2),
    ],
    GameSound.powerUp: [
      SynthNote(frequency: 660, start: 0, duration: 0.09, gain: 0.26, decay: 2),
      SynthNote(
        frequency: 880,
        start: 0.07,
        duration: 0.1,
        gain: 0.26,
        decay: 2,
      ),
      SynthNote(
        frequency: 1320,
        start: 0.14,
        duration: 0.16,
        gain: 0.3,
        decay: 2.4,
      ),
    ],
    GameSound.playerHit: [
      SynthNote(
        frequency: 300,
        start: 0,
        duration: 0.18,
        sweep: 0.35,
        noise: 0.4,
      ),
      SynthNote(
        frequency: 90,
        start: 0,
        duration: 0.3,
        gain: 0.45,
        decay: 2.6,
        noise: 0.25,
      ),
    ],
    GameSound.bomb: [
      SynthNote(
        frequency: 120,
        start: 0,
        duration: 1.0,
        gain: 0.7,
        sweep: 0.28,
        decay: 1.5,
        noise: 0.8,
      ),
      SynthNote(
        frequency: 58,
        start: 0.05,
        duration: 1.1,
        gain: 0.6,
        sweep: 0.6,
        decay: 1.4,
        noise: 0.35,
      ),
      SynthNote(
        frequency: 1600,
        start: 0,
        duration: 0.25,
        gain: 0.2,
        sweep: 0.4,
        decay: 3,
        brightness: 0.6,
      ),
    ],
    GameSound.gameOver: [
      SynthNote(
        frequency: 440,
        start: 0,
        duration: 0.22,
        gain: 0.4,
        decay: 1.6,
      ),
      SynthNote(
        frequency: 330,
        start: 0.2,
        duration: 0.26,
        gain: 0.4,
        decay: 1.6,
      ),
      SynthNote(
        frequency: 220,
        start: 0.42,
        duration: 0.5,
        gain: 0.42,
        decay: 1.4,
      ),
    ],
    GameSound.ui: [
      SynthNote(frequency: 880, start: 0, duration: 0.05, gain: 0.14, decay: 4),
    ],
  };

  static void configure({required bool sound, required bool haptics}) {
    soundEnabled = sound;
    hapticsEnabled = haptics;
  }

  /// 预合成音效并载入 SoLoud 音源；失败时保持静默，不影响战斗。
  static Future<void> init() => _ensureLoaded();

  static Future<void> _ensureLoaded() {
    if (_loadFailed || _sources.isNotEmpty) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      await AudioEngine.ensureInitialized();
      // 全部音效的采样合成一次放到后台 isolate，主线程只负责装载音源。
      final clips = await runSynth(_synthesizeAllClips);
      _clips.addAll(clips);
      for (final sound in GameSound.values) {
        _sources[sound] = await AudioEngine.loadMem(
          'skyfighter-${sound.name}.wav',
          _clips[sound]!,
        );
      }
    } catch (error) {
      _loadFailed = true;
      _disposeAll();
      debugPrint('[SoundService] 音效初始化失败，已静音: $error');
      LogService.warning('音效初始化失败，已静音: $error');
    }
  }

  /// 某个反馈对应的合成音频，供测试校验音效配方。
  @visibleForTesting
  static Uint8List clipOf(GameSound sound) =>
      _clips.putIfAbsent(sound, () => synthesizeWav(presets[sound]!));

  static void play(GameSound sound) {
    if (soundEnabled) {
      final target = sink;
      if (target != null) {
        target(sound);
      } else {
        unawaited(_play(sound));
      }
    }
    if (!hapticsEnabled) return;
    // 射击与按钮点击每秒要触发数次，为它们发平台震动调用只会带来无效的
    // 通道开销与持续震感，震动只保留给真正的战斗反馈。
    final Future<void> Function()? haptic = switch (sound) {
      GameSound.shoot || GameSound.ui => null,
      GameSound.warning || GameSound.resonance => HapticFeedback.mediumImpact,
      GameSound.explosion ||
      GameSound.powerUp ||
      GameSound.lance => HapticFeedback.lightImpact,
      GameSound.playerHit || GameSound.bomb => HapticFeedback.heavyImpact,
      GameSound.bigExplosion || GameSound.gameOver => HapticFeedback.vibrate,
    };
    haptic?.call();
  }

  static Future<void> _play(GameSound sound) async {
    try {
      await _ensureLoaded();
      final source = _sources[sound];
      if (source == null) return;
      final soloud = SoLoud.instance;
      soloud.stopAudioSource(source);
      soloud.play(
        source,
        volume: sound == GameSound.shoot
            ? 0.55
            : sound == GameSound.lance
            ? 0.8
            : 0.9,
      );
    } catch (error) {
      debugPrint('[SoundService] 播放失败: $error');
    }
  }

  static void _disposeAll() {
    final sources = _sources.values.toList();
    _sources.clear();
    for (final source in sources) {
      unawaited(_dispose(source));
    }
  }

  static Future<void> _dispose(AudioSource source) async {
    try {
      await SoLoud.instance.disposeSource(source);
    } catch (_) {
      // 音源已失效时无需再处理。
    }
  }

  @visibleForTesting
  static void reset() {
    sink = null;
    _disposeAll();
    _clips.clear();
    _loading = null;
    _loadFailed = false;
    soundEnabled = true;
    hapticsEnabled = true;
  }
}

/// 后台 isolate 的入口：一次合成全部音效，只引用静态配方表，不捕获调用方状态。
Map<GameSound, Uint8List> _synthesizeAllClips() => {
  for (final sound in GameSound.values)
    sound: synthesizeWav(SoundService.presets[sound]!),
};
