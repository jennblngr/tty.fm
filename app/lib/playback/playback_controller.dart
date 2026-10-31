import 'dart:async';
import 'dart:math';

import '../data/models.dart';
import 'audio_engine.dart';

/// A queue entry. [uid] distinguishes the same track queued twice.
class QueueItem {
  const QueueItem(this.uid, this.track);
  final int uid;
  final Track track;
}

/// Immutable snapshot of the player. Position is published separately (it
/// changes many times per second and most widgets do not need it).
class PlaybackState {
  const PlaybackState({
    this.queue = const [],
    this.index = -1,
    this.playing = false,
    this.buffering = false,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    this.volume = 1.0,
    this.duration = Duration.zero,
    this.error,
  });

  final List<QueueItem> queue;
  final int index;
  final bool playing;
  final bool buffering;
  final bool shuffle;
  final RepeatMode repeat;
  final double volume;
  final Duration duration;
  final String? error;

  Track? get current => index >= 0 && index < queue.length ? queue[index].track : null;
  bool get hasNext => index < queue.length - 1 || (repeat == RepeatMode.all && queue.isNotEmpty);
  bool get hasPrevious => current != null;
}

typedef SourceBuilder = EngineSource Function(Track track);
typedef PlayCallback = void Function(PlayRecord play);

/// The single owner of playback logic. Every command — UI buttons, system
/// media controls, headset buttons, and later remote commands from other
/// devices — goes through these methods; the UI only renders [state].
class PlaybackController {
  PlaybackController(this._engine, {required this.sourceFor, this.onPlay, DateTime Function()? clock})
      : _now = clock ?? DateTime.now {
    _subs.addAll([
      _engine.index.listen(_onEngineIndex),
      _engine.playing.listen((p) {
        _playing = p;
        _emit();
      }),
      _engine.buffering.listen((b) {
        _buffering = b;
        _emit();
      }),
      _engine.position.listen(_onPosition),
      _engine.duration.listen((d) {
        _engineDuration = d;
        _emit();
      }),
      _engine.completed.listen((_) => _onCompleted()),
      _engine.errors.listen((e) {
        _error = e;
        _emit();
      }),
    ]);
  }

  final AudioEngine _engine;

  /// Builds the stream URL for a track (quality depends on the network).
  SourceBuilder sourceFor;
  final PlayCallback? onPlay;
  final DateTime Function() _now;
  final _subs = <StreamSubscription<dynamic>>[];
  final _states = StreamController<PlaybackState>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _rng = Random();

  var _queue = <QueueItem>[];
  var _original = <QueueItem>[]; // queue order before shuffling
  var _index = -1;
  var _playing = false;
  var _buffering = false;
  var _shuffle = false;
  var _repeat = RepeatMode.off;
  var _volume = 1.0;
  var _position = Duration.zero;
  var _engineDuration = Duration.zero;
  String? _error;
  var _nextUid = 1;
  String? _contextKind;
  int? _contextId;
  _Session? _session;
  PlaybackState _state = const PlaybackState();

  PlaybackState get state => _state;
  Stream<PlaybackState> get states => _states.stream;
  Duration get position => _position;
  Stream<Duration> get positions => _positions.stream;

  void _emit() {
    final cur = _index >= 0 && _index < _queue.length ? _queue[_index].track : null;
    _state = PlaybackState(
      queue: List.unmodifiable(_queue),
      index: _index,
      playing: _playing,
      buffering: _buffering,
      shuffle: _shuffle,
      repeat: _repeat,
      volume: _volume,
      // Transcoded streams may not report a duration: trust the library.
      duration: _engineDuration > Duration.zero ? _engineDuration : (cur?.duration ?? Duration.zero),
      error: _error,
    );
    if (!_states.isClosed) _states.add(_state);
  }

  List<QueueItem> _items(List<Track> tracks) => [for (final t in tracks) QueueItem(_nextUid++, t)];

  List<EngineSource> _sources() => [for (final q in _queue) sourceFor(q.track)];

  // --- commands -------------------------------------------------------------

  /// Replaces the queue with [tracks] and starts at [index]. With shuffle on,
  /// the chosen track plays first and the rest is shuffled.
  Future<void> playTracks(List<Track> tracks,
      {int index = 0, bool? shuffle, String? contextKind, int? contextId}) async {
    if (tracks.isEmpty) return;
    _finishSession(byUser: true);
    _contextKind = contextKind;
    _contextId = contextId;
    if (shuffle != null) _shuffle = shuffle;
    _original = _items(tracks);
    index = index.clamp(0, tracks.length - 1);
    if (_shuffle) {
      final first = _original[index];
      _queue = [first, ...(_original.toList()..removeAt(index)..shuffle(_rng))];
      _index = 0;
    } else {
      _queue = [..._original];
      _index = index;
    }
    _error = null;
    _position = Duration.zero;
    _engineDuration = Duration.zero;
    _startSession();
    _emit();
    await _open(index: _index);
  }

  /// Inserts [tracks] right after the current one.
  Future<void> playNext(List<Track> tracks) async {
    if (_queue.isEmpty) return playTracks(tracks);
    final items = _items(tracks);
    final at = _index + 1;
    final origAt = _original.indexOf(_queue[_index]) + 1;
    _queue.insertAll(at, items);
    _original.insertAll(origAt, items);
    _emit();
    for (var i = 0; i < items.length; i++) {
      await _engine.add(sourceFor(items[i].track));
      await _engine.move(_queue.length - items.length + i, at + i);
    }
  }

  /// Appends [tracks] to the end of the queue.
  Future<void> addToQueue(List<Track> tracks) async {
    if (_queue.isEmpty) return playTracks(tracks);
    final items = _items(tracks);
    _queue.addAll(items);
    _original.addAll(items);
    _emit();
    for (final it in items) {
      await _engine.add(sourceFor(it.track));
    }
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= _queue.length) return;
    if (_queue.length == 1) return clear();
    final removed = _queue.removeAt(i);
    _original.remove(removed);
    if (i == _index) {
      _finishSession(byUser: true);
      if (_index >= _queue.length) _index = _queue.length - 1;
      _startSession();
    } else if (i < _index) {
      _index--;
    }
    _emit();
    await _engine.remove(i);
  }

  /// Moves a queue entry; the current track keeps playing.
  Future<void> move(int from, int to) async {
    if (from == to || from < 0 || to < 0 || from >= _queue.length || to >= _queue.length) return;
    final cur = _queue[_index];
    _queue.insert(to, _queue.removeAt(from));
    _index = _queue.indexOf(cur);
    _emit();
    await _engine.move(from, to);
  }

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= _queue.length) return;
    if (i == _index) {
      _completed = false;
      if (_session == null) _startSession(); // replaying after the end
      await seek(Duration.zero);
    } else {
      _changeIndex(i, byUser: true);
      await _engine.jump(i);
    }
    if (!_playing) await _engine.play();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_index < _queue.length - 1) return jumpTo(_index + 1);
    if (_repeat == RepeatMode.all) return jumpTo(0);
  }

  /// Restarts the track if past 3 s (or first), else goes to the previous one.
  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_position > const Duration(seconds: 3) || _index == 0) return seek(Duration.zero);
    return jumpTo(_index - 1);
  }

  Future<void> play() async {
    if (_queue.isEmpty) return;
    if (_completed) {
      _completed = false;
      return jumpTo(0);
    }
    await _engine.play();
  }

  Future<void> pause() => _engine.pause();

  Future<void> togglePlay() => _playing ? pause() : play();

  Future<void> seek(Duration to) async {
    if (_session != null) _session!.lastPos = to;
    _position = to;
    if (!_positions.isClosed) _positions.add(to);
    await _engine.seek(to);
  }

  Future<void> setShuffle(bool on) async {
    if (on == _shuffle) return;
    _shuffle = on;
    if (_queue.isEmpty) return _emit();
    final cur = _queue[_index];
    if (on) {
      // Keep what was already played, shuffle what is coming.
      final played = _queue.sublist(0, _index + 1);
      final upcoming = _queue.sublist(_index + 1)..shuffle(_rng);
      _queue = [...played, ...upcoming];
    } else {
      _queue = [..._original];
      _index = _queue.indexOf(cur);
    }
    _emit();
    await _reopen();
  }

  Future<void> cycleRepeat() => setRepeat(RepeatMode.values[(_repeat.index + 1) % RepeatMode.values.length]);

  Future<void> setRepeat(RepeatMode mode) async {
    _repeat = mode;
    _emit();
    await _engine.setRepeat(mode);
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    _emit();
    await _engine.setVolume(_volume);
  }

  Future<void> clear() async {
    _finishSession(byUser: true);
    _queue = [];
    _original = [];
    _index = -1;
    _position = Duration.zero;
    _emit();
    await _engine.stop();
  }

  /// Rebuilds stream URLs (e.g. after switching from LAN to remote) and
  /// resumes at the same place.
  Future<void> refreshSources() async {
    if (_queue.isEmpty) return;
    await _reopen();
  }

  Future<void> _reopen() => _open(index: _index, start: _position, play: _playing);

  /// Opens the engine playlist, ignoring the index events it emits while
  /// loading (they reflect our own state, not a track change).
  Future<void> _open({required int index, Duration start = Duration.zero, bool play = true}) async {
    _opening++;
    try {
      await _engine.open(_sources(), index: index, start: start, play: play);
    } finally {
      _opening--;
    }
  }

  var _opening = 0;

  // --- persistence ------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'queue': [for (final q in _queue) q.track.toJson()],
        'original': [for (final q in _original) _queue.indexOf(q)],
        'index': _index,
        'position_ms': _position.inMilliseconds,
        'shuffle': _shuffle,
        'repeat': _repeat.name,
        'volume': _volume,
        'context_kind': _contextKind,
        'context_id': _contextId,
      };

  /// Restores a saved queue, paused at the saved position.
  Future<void> restore(Map<String, dynamic> j) async {
    final tracks = [for (final t in j['queue'] as List) Track.fromJson(t as Map<String, dynamic>)];
    if (tracks.isEmpty) return;
    _queue = _items(tracks);
    final order = (j['original'] as List?)?.cast<int>() ?? const [];
    _original = order.length == _queue.length ? [for (final i in order) _queue[i]] : [..._queue];
    _index = (j['index'] as int? ?? 0).clamp(0, _queue.length - 1);
    _position = Duration(milliseconds: j['position_ms'] as int? ?? 0);
    _shuffle = j['shuffle'] as bool? ?? false;
    _repeat = RepeatMode.values.asNameMap()[j['repeat']] ?? RepeatMode.off;
    _volume = (j['volume'] as num? ?? 1).toDouble();
    _contextKind = j['context_kind'] as String?;
    _contextId = j['context_id'] as int?;
    _startSession();
    _session!.lastPos = _position;
    _emit();
    await _engine.setRepeat(_repeat);
    await _engine.setVolume(_volume);
    await _open(index: _index, start: _position, play: false);
  }

  // --- engine events ------------------------------------------------------------

  var _completed = false;

  void _onEngineIndex(int i) {
    if (_opening > 0 || i == _index || i < 0 || i >= _queue.length) return;
    _changeIndex(i, byUser: false); // natural advance (gapless)
  }

  void _changeIndex(int i, {required bool byUser}) {
    _finishSession(byUser: byUser);
    _index = i;
    _position = Duration.zero;
    _engineDuration = Duration.zero;
    _completed = false;
    _startSession();
    _emit();
  }

  void _onPosition(Duration pos) {
    final s = _session;
    if (s != null) {
      final delta = pos - s.lastPos;
      if (_playing && delta > Duration.zero && delta < const Duration(seconds: 3)) {
        s.listened += delta;
      }
      // Repeat-one loops inside the engine without an index change.
      final dur = _state.duration;
      if (_repeat == RepeatMode.one &&
          dur > Duration.zero &&
          s.lastPos > dur - const Duration(seconds: 3) &&
          pos < const Duration(seconds: 2)) {
        _finishSession(byUser: false);
        _startSession();
      }
      _session?.lastPos = pos;
    }
    _position = pos;
    if (!_positions.isClosed) _positions.add(pos);
  }

  void _onCompleted() {
    if (_repeat != RepeatMode.off) return;
    if (_index == _queue.length - 1) {
      _finishSession(byUser: false);
      _completed = true;
      _playing = false;
      _emit();
    }
  }

  // --- listening history -------------------------------------------------------

  void _startSession() {
    if (_index < 0 || _index >= _queue.length) {
      _session = null;
      return;
    }
    _session = _Session(_queue[_index].track, _now());
  }

  /// Closes the current listening session. A play counts as skipped when
  /// the user moved on before half the track (capped at 4 minutes).
  void _finishSession({required bool byUser}) {
    final s = _session;
    _session = null;
    if (s == null) return;
    final listened = s.listened.inMilliseconds;
    final threshold = min(240000, s.track.durationMs ~/ 2);
    final skipped = byUser && listened < threshold;
    if (listened < 1000 && !skipped) return;
    onPlay?.call(PlayRecord(
      trackId: s.track.id,
      startedAt: s.startedAt,
      listenedMs: listened,
      skipped: skipped,
      contextKind: _contextKind,
      contextId: _contextId,
    ));
  }

  Future<void> dispose() async {
    _finishSession(byUser: false);
    for (final s in _subs) {
      await s.cancel();
    }
    await _states.close();
    await _positions.close();
  }
}

class _Session {
  _Session(this.track, this.startedAt);
  final Track track;
  final DateTime startedAt;
  Duration listened = Duration.zero;
  Duration lastPos = Duration.zero;
}
