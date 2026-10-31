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

/// User preferences (not secrets: the token lives in secure storage).
@immutable
class Settings {
  const Settings({
    this.remoteUrl = '',
    this.lanUrl = '',
    this.qualityLocal = StreamQuality.original,
    this.qualityRemoteWifi = StreamQuality.opusHigh,
    this.qualityCellular = StreamQuality.opusMedium,
    this.themeMode = ThemeMode.system,
    this.downloadQuality = StreamQuality.original,
    this.downloadWifiOnly = false,
  });

  /// Address used everywhere (typically the Tailscale name).
  final String remoteUrl;

  /// Optional LAN address, preferred when reachable.
  final String lanUrl;
  final StreamQuality qualityLocal;
  final StreamQuality qualityRemoteWifi;
  final StreamQuality qualityCellular;
  final ThemeMode themeMode;

  /// Quality of offline copies, and whether to download only off cellular.
  final StreamQuality downloadQuality;
  final bool downloadWifiOnly;

  bool get configured => remoteUrl.isNotEmpty;

  Settings copyWith({
    String? remoteUrl,
    String? lanUrl,
    StreamQuality? qualityLocal,
    StreamQuality? qualityRemoteWifi,
    StreamQuality? qualityCellular,
    ThemeMode? themeMode,
    StreamQuality? downloadQuality,
    bool? downloadWifiOnly,
  }) => Settings(
    remoteUrl: remoteUrl ?? this.remoteUrl,
    lanUrl: lanUrl ?? this.lanUrl,
    qualityLocal: qualityLocal ?? this.qualityLocal,
    qualityRemoteWifi: qualityRemoteWifi ?? this.qualityRemoteWifi,
    qualityCellular: qualityCellular ?? this.qualityCellular,
    themeMode: themeMode ?? this.themeMode,
    downloadQuality: downloadQuality ?? this.downloadQuality,
    downloadWifiOnly: downloadWifiOnly ?? this.downloadWifiOnly,
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
    return Settings(
      remoteUrl: _p.getString('remoteUrl') ?? '',
      lanUrl: _p.getString('lanUrl') ?? '',
      qualityLocal: pick(StreamQuality.values, 'qualityLocal', StreamQuality.original),
      qualityRemoteWifi: pick(StreamQuality.values, 'qualityRemoteWifi', StreamQuality.opusHigh),
      qualityCellular: pick(StreamQuality.values, 'qualityCellular', StreamQuality.opusMedium),
      themeMode: pick(ThemeMode.values, 'themeMode', ThemeMode.system),
      // Phones: smaller files, and no downloads over cellular by default.
      downloadQuality: pick(
        StreamQuality.values,
        'downloadQuality',
        _mobile ? StreamQuality.opusHigh : StreamQuality.original,
      ),
      downloadWifiOnly: _p.getBool('downloadWifiOnly') ?? _mobile,
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
      _p.setString('themeMode', s.themeMode.name),
      _p.setString('downloadQuality', s.downloadQuality.name),
      _p.setBool('downloadWifiOnly', s.downloadWifiOnly),
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
