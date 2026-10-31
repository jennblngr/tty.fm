import 'dart:async';

import '../core/json_cache.dart';
import '../data/models.dart';

/// Queues listening history and sends it in batches. Pending plays are
/// persisted so nothing is lost offline or if the app is killed.
class PlayReporter {
  PlayReporter(this._cache, this._send);

  static const _key = 'pending_plays';
  final JsonCache _cache;
  final Future<void> Function(List<PlayRecord>) _send;
  final _pending = <PlayRecord>[];
  Timer? _timer;
  bool _sending = false;

  Future<void> load() async {
    final j = await _cache.read(_key);
    if (j is List) {
      _pending.addAll([for (final p in j) PlayRecord.fromJson(p as Map<String, dynamic>)]);
    }
    if (_pending.isNotEmpty) _schedule(const Duration(seconds: 2));
  }

  void add(PlayRecord p) {
    _pending.add(p);
    _persist();
    _schedule(const Duration(seconds: 5));
  }

  void _persist() => _cache.write(_key, [for (final p in _pending) p.toJson()]);

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, flush);
  }

  Future<void> flush() async {
    if (_sending || _pending.isEmpty) return;
    _sending = true;
    final batch = List.of(_pending);
    try {
      await _send(batch);
      _pending.removeRange(0, batch.length);
      _persist();
    } catch (_) {
      _schedule(const Duration(minutes: 1)); // offline: retry later
    } finally {
      _sending = false;
    }
  }
}
