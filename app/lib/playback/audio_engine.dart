/// A playable source handed to the engine.
class EngineSource {
  const EngineSource(this.url, {this.headers = const {}});
  final String url;
  final Map<String, String> headers;
}

enum RepeatMode { off, all, one }

/// The playing entry of the engine playlist: its index, and a key that is
/// the same for the same media (its URI), so that a track moved within the
/// playlist can be told from a new track.
typedef EngineEntry = ({int index, String key});

/// The low-level player. The engine owns an ordered playlist that mirrors
/// the controller's queue so it can prefetch and play gaplessly; the
/// controller stays the single source of truth for what that queue is.
abstract class AudioEngine {
  Stream<EngineEntry> get index;
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<Duration> get position;
  Stream<Duration> get duration;

  /// Emits when playback reached the end of the playlist.
  Stream<void> get completed;
  Stream<String> get errors;

  Future<void> open(List<EngineSource> sources, {int index = 0, Duration start = Duration.zero, bool play = true});
  Future<void> add(EngineSource source);

  /// Moves the item at [from] so that it ends up at index [to].
  Future<void> move(int from, int to);
  Future<void> remove(int index);
  Future<void> jump(int index);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setRepeat(RepeatMode mode);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}
