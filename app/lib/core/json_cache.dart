import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent cache of API responses (one JSON file per key) with an
/// in-memory layer. Lets screens render instantly from the last known data
/// while fresh data loads.
class JsonCache {
  JsonCache(this._dir);

  final Directory _dir;
  final _mem = <String, String>{};

  static Future<JsonCache> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/api_cache');
    await dir.create(recursive: true);
    return JsonCache(dir);
  }

  File _file(String key) => File('${_dir.path}/${sha1.convert(utf8.encode(key))}.json');

  /// Raw JSON text for [key], or null.
  Future<String?> readRaw(String key) async {
    final m = _mem[key];
    if (m != null) return m;
    try {
      final s = await _file(key).readAsString();
      _mem[key] = s;
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> read(String key) async {
    final s = await readRaw(key);
    return s == null ? null : jsonDecode(s);
  }

  /// Stores [value]; returns false if it is identical to the cached one.
  Future<bool> write(String key, Object? value) async {
    final s = jsonEncode(value);
    if (_mem[key] == s) return false;
    _mem[key] = s;
    try {
      final f = _file(key);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(s, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
    return true;
  }

  Future<void> clear() async {
    _mem.clear();
    try {
      await _dir.delete(recursive: true);
      await _dir.create(recursive: true);
    } catch (_) {}
  }
}

/// Set in main() once the cache directory is opened.
final jsonCacheProvider = Provider<JsonCache>((ref) => throw UnimplementedError());
