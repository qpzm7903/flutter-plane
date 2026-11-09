/// Web 端字体：CanvasKit 没有系统中文字体回退，使用 soup_fonts 的思源黑体。
const String kWebFontFamily = 'SourceHanSansCN';

class AppConstants {
  AppConstants._();

  static const String appName = '苍穹战机';
  static const String version = '0.6.0';
  static const String tagline = '竖版弹幕射击 · 本地单机';

  static const String prefKeyDarkMode = 'dark_mode';
  static const String prefKeySound = 'sound_enabled';
  static const String prefKeyMusic = 'music_enabled';
  static const String prefKeyHaptics = 'haptics_enabled';
  static const String prefKeyLogicRate = 'logic_rate';
  static const String prefKeyHighScore = 'high_score';
  static const String prefKeyBestWave = 'best_wave';
  static const String prefKeyRuns = 'runs';

  static const String prefKeyAchievements = 'achievements';
  static const String prefKeyLifetimeKills = 'lifetime_kills';
  static const String prefKeyLifetimeBossKills = 'lifetime_boss_kills';
  static const String prefKeyBestCombo = 'best_combo';

  static const String prefKeyChallengeDate = 'challenge_date';
  static const String prefKeyChallengeBest = 'challenge_best';
  static const String prefKeyChallengeWave = 'challenge_wave';
  static const String prefKeyChallengePlays = 'challenge_plays';
  static const String prefKeyChallengeLastDate = 'challenge_last_date';
  static const String prefKeyChallengeStreak = 'challenge_streak';
  static const String prefKeyChallengeBestStreak = 'challenge_best_streak';
  static const String prefKeyChallengeRuns = 'challenge_runs';
  static const String prefKeyChallengeBestEver = 'challenge_best_ever';
}
