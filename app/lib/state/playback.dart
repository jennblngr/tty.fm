import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/json_cache.dart';
import '../core/network.dart';
import '../core/session.dart';
import '../data/library_repository.dart';
import '../data/models.dart';
import '../offline/downloads.dart';
import '../playback/audio_engine.dart';
import '../playback/media_kit_engine.dart';
import '../playback/play_reporter.dart';
import '../playback/playback_controller.dart';

/// Engine factory, overridable in tests.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final e = MediaKitEngine();
  ref.onDispose(e.dispose);
  return e;
});

final playReporterProvider = Provider<PlayReporter>((ref) {
  final repo = ref.watch(libraryProvider);
  final r = PlayReporter(ref.watch(jsonCacheProvider), repo.reportPlays)..load();
  return r;
});

/// Builds the stream source for a track: the offline copy if any, otherwise
/// a stream URL according to the current route and quality setting.
EngineSource buildSource(Ref ref, Track t) {
  final local = ref.read(downloadsProvider.notifier).pathFor(t.id);
  if (local != null) return EngineSource(local); // downloaded: no network needed
  final api = ref.read(apiProvider);
  final q = ref.read(streamQualityProvider);
  final query = q.format == null ? '' : '?format=${q.format}&bitrate=${q.bitrate}';
  return EngineSource(api.url('/stream/${t.id}$query'), headers: api.authHeaders);
}

const _queueKey = 'playback_queue';

final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final reporter = ref.watch(playReporterProvider);
  final cache = ref.watch(jsonCacheProvider);
  final c = PlaybackController(
    ref.watch(audioEngineProvider),
    sourceFor: (t) => buildSource(ref, t),
    onPlay: reporter.add,
  );

  // Network or quality changed (left home, Wi-Fi → 4G): rebuild URLs.
  ref.listen(routeProvider, (prev, next) {
    if (prev != next) c.refreshSources();
  });
  ref.listen(streamQualityProvider, (prev, next) {
    if (prev != next) c.refreshSources();
  });
  // Logged out: stop and forget.
  ref.listen(tokenProvider, (prev, next) {
    if (next.isEmpty) {
      reporter.discard();
      c.clear();
    }
  });

  // Persist the queue (debounced) and the position while playing.
  Timer? saveTimer;
  void save() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(seconds: 2), () => cache.write(_queueKey, c.toJson()));
  }

  final sub = c.states.listen((_) => save());
  final periodic = Timer.periodic(const Duration(seconds: 15), (_) {
    if (c.state.playing) save();
  });
  ref.onDispose(() {
    sub.cancel();
    periodic.cancel();
    saveTimer?.cancel();
    c.dispose();
  });
  cache.read(_queueKey).then((j) {
    if (j is Map<String, dynamic> && c.state.queue.isEmpty) c.restore(j);
  });
  return c;
});

class PlaybackStateNotifier extends Notifier<PlaybackState> {
  @override
  PlaybackState build() {
    final c = ref.watch(playbackControllerProvider);
    final sub = c.states.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return c.state;
  }
}

final playbackStateProvider = NotifierProvider<PlaybackStateNotifier, PlaybackState>(PlaybackStateNotifier.new);

/// Current position, separate from [playbackStateProvider] to keep rebuilds
/// limited to the progress bar.
final positionProvider = StreamProvider<Duration>((ref) {
  final c = ref.watch(playbackControllerProvider);
  return c.positions;
});

/// The currently playing track (rebuilds only when it changes).
final currentTrackProvider = Provider<Track?>((ref) => ref.watch(playbackStateProvider.select((s) => s.current)));

/// Sleep timer: pause after a delay, or at the end of the current track.
class SleepTimerState {
  const SleepTimerState({this.endsAt, this.endOfTrack = false});
  final DateTime? endsAt;
  final bool endOfTrack;
}

class SleepTimer extends Notifier<SleepTimerState?> {
  Timer? _timer;
  StreamSubscription<PlaybackState>? _sub;

  @override
  SleepTimerState? build() {
    ref.onDispose(_cancel);
    return null;
  }

  void _cancel() {
    _timer?.cancel();
    _sub?.cancel();
    _timer = null;
    _sub = null;
  }

  void off() {
    _cancel();
    state = null;
  }

  void after(Duration d) {
    _cancel();
    final c = ref.read(playbackControllerProvider);
    _timer = Timer(d, () {
      c.pause();
      off();
    });
    state = SleepTimerState(endsAt: DateTime.now().add(d));
  }

  void atEndOfTrack() {
    _cancel();
    final c = ref.read(playbackControllerProvider);
    final uid = c.state.index >= 0 ? c.state.queue[c.state.index].uid : null;
    _sub = c.states.listen((s) {
      final now = s.index >= 0 && s.index < s.queue.length ? s.queue[s.index].uid : null;
      if (now != uid || !s.playing && s.index == s.queue.length - 1) {
        if (now != uid) c.pause();
        off();
      }
    });
    state = const SleepTimerState(endOfTrack: true);
  }
}

final sleepTimerProvider = NotifierProvider<SleepTimer, SleepTimerState?>(SleepTimer.new);
