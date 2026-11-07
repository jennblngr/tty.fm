import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Streaming quality for one network situation.
enum StreamQuality {
  original('Original', null, null),
  opusHigh('Opus 192 kb/s', 'opus', 192),
  opusMedium('Opus 128 kb/s', 'opus', 128),
  opusLow('Opus 96 kb/s', 'opus', 96);

  const StreamQuality(this.label, this.format, this.bitrate);
  final String label;
  final String? format;
  final int? bitrate;
}

/// The bundled colour themes. Only the names live here: the palettes are in
/// ui/theme.dart.
enum ThemeName {
  catppuccinMocha('catppuccin mocha', dark: true),
  dracula('dracula', dark: true),
  nord('nord', dark: true),
  gruvboxDark('gruvbox dark', dark: true),
  tokyoNight('tokyo night', dark: true),
  rosePine('rosé pine', dark: true),
  oneDark('one dark', dark: true),
  catppuccinLatte('catppuccin latte', dark: false),
  solarizedLight('solarized light', dark: false),
  gruvboxLight('gruvbox light', dark: false),
  rosePineDawn('rosé pine dawn', dark: false),
  oneLight('one light', dark: false);

  const ThemeName(this.label, {required this.dark});
  final String label;
  final bool dark;
}

/// User preferences (not secrets: the token lives in secure storage).
@immutable
class Settings {
  const Settings({
    this.remoteUrl = '',
    this.lanUrl = '',
    this.qualityLocal = StreamQuality.original,
    this.qualityRemoteWifi = StreamQuality.opusHigh,
    this.qualityCellular = StreamQuality.opusMedium,
    this.followSystem = true,
    this.darkTheme = ThemeName.catppuccinMocha,
    this.lightTheme = ThemeName.catppuccinLatte,
    this.fixedTheme = ThemeName.catppuccinMocha,
    this.downloadQuality = StreamQuality.original,
    this.downloadWifiOnly = false,
    this.hideArchived = false,
  });

  /// Address used everywhere (typically the Tailscale name).
  final String remoteUrl;

  /// Optional LAN address, preferred when reachable.
  final String lanUrl;
  final StreamQuality qualityLocal;
  final StreamQuality qualityRemoteWifi;
  final StreamQuality qualityCellular;

  /// On: [darkTheme] or [lightTheme] depending on the system. Off: always
  /// [fixedTheme], picked from either list.
  final bool followSystem;
  final ThemeName darkTheme;
  final ThemeName lightTheme;
  final ThemeName fixedTheme;

  /// Quality of offline copies, and whether to download only off cellular.
  final StreamQuality downloadQuality;
  final bool downloadWifiOnly;

  /// Leaves the archived tracks out of the albums, and the albums whose
  /// tracks are all archived out of the library.
  final bool hideArchived;

  bool get configured => remoteUrl.isNotEmpty;

  Settings copyWith({
    String? remoteUrl,
    String? lanUrl,
    StreamQuality? qualityLocal,
    StreamQuality? qualityRemoteWifi,
    StreamQuality? qualityCellular,
    bool? followSystem,
    ThemeName? darkTheme,
    ThemeName? lightTheme,
    ThemeName? fixedTheme,
    StreamQuality? downloadQuality,
    bool? downloadWifiOnly,
    bool? hideArchived,
  }) => Settings(
    remoteUrl: remoteUrl ?? this.remoteUrl,
    lanUrl: lanUrl ?? this.lanUrl,
    qualityLocal: qualityLocal ?? this.qualityLocal,
    qualityRemoteWifi: qualityRemoteWifi ?? this.qualityRemoteWifi,
    qualityCellular: qualityCellular ?? this.qualityCellular,
    followSystem: followSystem ?? this.followSystem,
    darkTheme: darkTheme ?? this.darkTheme,
    lightTheme: lightTheme ?? this.lightTheme,
    fixedTheme: fixedTheme ?? this.fixedTheme,
    downloadQuality: downloadQuality ?? this.downloadQuality,
    downloadWifiOnly: downloadWifiOnly ?? this.downloadWifiOnly,
    hideArchived: hideArchived ?? this.hideArchived,
  );
}

/// Set in main() once SharedPreferences is loaded.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

bool get _mobile => Platform.isAndroid || Platform.isIOS;

class SettingsNotifier extends Notifier<Settings> {
  SharedPreferences get _p => ref.read(sharedPrefsProvider);

  @override
  Settings build() {
    T pick<T extends Enum>(List<T> values, String key, T def) => values.asNameMap()[_p.getString(key)] ?? def;
    // Before the theme list there was only a light/dark/system choice.
    final legacyMode = _p.getString('themeMode');
    return Settings(
      remoteUrl: _p.getString('remoteUrl') ?? '',
      lanUrl: _p.getString('lanUrl') ?? '',
      qualityLocal: pick(StreamQuality.values, 'qualityLocal', StreamQuality.original),
      qualityRemoteWifi: pick(StreamQuality.values, 'qualityRemoteWifi', StreamQuality.opusHigh),
      qualityCellular: pick(StreamQuality.values, 'qualityCellular', StreamQuality.opusMedium),
      followSystem: _p.getBool('followSystem') ?? (legacyMode == null || legacyMode == 'system'),
      darkTheme: pick(ThemeName.values, 'darkTheme', ThemeName.catppuccinMocha),
      lightTheme: pick(ThemeName.values, 'lightTheme', ThemeName.catppuccinLatte),
      fixedTheme: pick(
        ThemeName.values,
        'fixedTheme',
        legacyMode == 'light' ? ThemeName.catppuccinLatte : ThemeName.catppuccinMocha,
      ),
      // Phones: smaller files, and no downloads over cellular by default.
      downloadQuality: pick(
        StreamQuality.values,
        'downloadQuality',
        _mobile ? StreamQuality.opusHigh : StreamQuality.original,
      ),
      downloadWifiOnly: _p.getBool('downloadWifiOnly') ?? _mobile,
      hideArchived: _p.getBool('hideArchived') ?? false,
    );
  }

  Future<void> update(Settings s) async {
    state = s;
    await Future.wait([
      _p.setString('remoteUrl', s.remoteUrl),
      _p.setString('lanUrl', s.lanUrl),
      _p.setString('qualityLocal', s.qualityLocal.name),
      _p.setString('qualityRemoteWifi', s.qualityRemoteWifi.name),
      _p.setString('qualityCellular', s.qualityCellular.name),
      _p.setBool('followSystem', s.followSystem),
      _p.setString('darkTheme', s.darkTheme.name),
      _p.setString('lightTheme', s.lightTheme.name),
      _p.setString('fixedTheme', s.fixedTheme.name),
      _p.setString('downloadQuality', s.downloadQuality.name),
      _p.setBool('downloadWifiOnly', s.downloadWifiOnly),
      _p.setBool('hideArchived', s.hideArchived),
    ]);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

/// Normalises user input: adds http:// and strips trailing slashes.
String normalizeUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return s;
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}
