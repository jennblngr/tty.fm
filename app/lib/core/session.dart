import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_info.dart';
import 'json_cache.dart';
import 'settings.dart';

const _tokenKey = '${appName}_token';

/// Authentication state: the device token, or null when logged out.
class SessionNotifier extends AsyncNotifier<String?> {
  static const _storage = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

  @override
  Future<String?> build() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  /// Logs in against [remoteUrl] (or [lanUrl] if set and reachable) and
  /// stores the server addresses and token.
  Future<void> login({
    required String remoteUrl,
    String lanUrl = '',
    required String username,
    required String password,
  }) async {
    final remote = normalizeUrl(remoteUrl);
    final lan = normalizeUrl(lanUrl);
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
    final body = {
      'username': username,
      'password': password,
      'device_name': await _deviceName(),
      'platform': Platform.operatingSystem,
    };
    Response<dynamic> res;
    try {
      res = await dio.post('${lan.isNotEmpty ? lan : remote}$apiPrefix/auth/login', data: body);
    } on DioException catch (e) {
      if (lan.isEmpty || e.response != null) rethrow;
      res = await dio.post('$remote$apiPrefix/auth/login', data: body);
    }
    final token = res.data['token'] as String;
    final settings = ref.read(settingsProvider.notifier);
    await settings.update(ref.read(settingsProvider).copyWith(remoteUrl: remote, lanUrl: lan));
    await _storage.write(key: _tokenKey, value: token);
    state = AsyncData(token);
  }

  /// Forgets the token locally (the server-side revocation is best effort)
  /// and drops the cached responses: the next login may target another
  /// server, whose ids mean different things.
  Future<void> logout({Future<void> Function()? revoke}) async {
    try {
      await revoke?.call();
    } catch (_) {}
    await _storage.delete(key: _tokenKey);
    state = const AsyncData(null);
    await ref.read(jsonCacheProvider).clear();
    await DefaultCacheManager().emptyCache(); // covers are keyed by server id
  }

  static Future<String> _deviceName() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isMacOS) return (await info.macOsInfo).computerName;
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return '${a.manufacturer} ${a.model}';
      }
      if (Platform.isIOS) return (await info.iosInfo).name;
      if (Platform.isWindows) return (await info.windowsInfo).computerName;
    } catch (_) {}
    return Platform.localHostname;
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, String?>(SessionNotifier.new);

/// The token, or '' when logged out. Convenient for synchronous callers.
final tokenProvider = Provider<String>((ref) => ref.watch(sessionProvider).value ?? '');
