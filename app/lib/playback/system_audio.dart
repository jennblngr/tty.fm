import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as svc;

import '../data/models.dart';
import 'audio_engine.dart';
import 'playback_controller.dart';

/// Bridges [PlaybackController] to the OS media controls via audio_service:
/// Android notification / lock screen / Bluetooth headset buttons, macOS
/// Now Playing and media keys, iOS control centre. It holds no logic: every
/// command is forwarded to the controller.
class SystemAudioHandler extends svc.BaseAudioHandler with svc.SeekHandler {
  SystemAudioHandler(this._c, this._artUri) {
    _subs.add(_c.states.listen(_publish));
    _publish(_c.state);
  }

  final PlaybackController _c;
  final Uri? Function(Track track) _artUri;
  final _subs = <StreamSubscription<dynamic>>[];
  int? _lastTrackId;
  int _lastQueueLength = -1;

  /// Playing state as last reported to the OS.
  bool _reportedPlaying = false;

  /// Running while a drop of `playing` that nobody asked for is held back.
  Timer? _graceTimer;

  /// How long a pause nobody asked for (source reopened after a network
  /// change, track transition, rebuffering) is reported as still playing.
  ///
  /// On Android, reporting `playing: false` makes audio_service leave the
  /// foreground (`androidStopForegroundOnPause`). With another app in front,
  /// the process is then cached and frozen within seconds: the sound stops,
  /// and resumes where it was when the app is brought back. Android 12+ also
  /// refuses to re-enter the foreground from the background, so playing
  /// again does not help. A locked screen is not affected: the app is still
  /// the top activity and is never frozen.
  static const transientPauseGrace = Duration(seconds: 10);

  svc.MediaItem _item(Track t) => svc.MediaItem(
    id: '${t.id}',
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: t.duration,
    artUri: _artUri(t),
  );

  /// Whether to report the session as playing to the OS.
  bool _playingForSystem(PlaybackState s) {
    if (s.playing || s.current == null || _c.pauseRequested) {
      _graceTimer?.cancel();
      _graceTimer = null;
      return s.playing;
    }
    if (!_reportedPlaying) return false;
    // Unrequested stop while playing: hold the foreground for a while, then
    // report the pause if playback did not come back by itself.
    _graceTimer ??= Timer(transientPauseGrace, () {
      _graceTimer = null;
      _reportedPlaying = false;
      _publish(_c.state);
    });
    return _graceTimer != null;
  }

  void _publish(PlaybackState s) {
    final playing = _playingForSystem(s);
    _reportedPlaying = playing;
    final cur = s.current;
    if (cur?.id != _lastTrackId) {
      _lastTrackId = cur?.id;
      mediaItem.add(cur == null ? null : _item(cur).copyWith(duration: s.duration));
    }
    if (s.queue.length != _lastQueueLength) {
      _lastQueueLength = s.queue.length;
      queue.add([for (final q in s.queue) _item(q.track)]);
    }
    playbackState.add(
      svc.PlaybackState(
        controls: [
          svc.MediaControl.skipToPrevious,
          playing ? svc.MediaControl.pause : svc.MediaControl.play,
          svc.MediaControl.skipToNext,
        ],
        systemActions: const {svc.MediaAction.seek, svc.MediaAction.seekForward, svc.MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: cur == null
            ? svc.AudioProcessingState.idle
            : s.buffering
            ? svc.AudioProcessingState.buffering
            : svc.AudioProcessingState.ready,
        playing: playing,
        updatePosition: _c.position,
        queueIndex: s.index < 0 ? null : s.index,
        shuffleMode: s.shuffle ? svc.AudioServiceShuffleMode.all : svc.AudioServiceShuffleMode.none,
        repeatMode: switch (s.repeat) {
          RepeatMode.off => svc.AudioServiceRepeatMode.none,
          RepeatMode.all => svc.AudioServiceRepeatMode.all,
          RepeatMode.one => svc.AudioServiceRepeatMode.one,
        },
      ),
    );
  }

  /// Republishes the current item and queue with fresh artwork URLs.
  void refreshArtwork() {
    _lastTrackId = null;
    _lastQueueLength = -1;
    _publish(_c.state);
  }

  @override
  Future<void> play() => _c.play();
  @override
  Future<void> pause() => _c.pause();
  @override
  Future<void> stop() => _c.pause();
  @override
  Future<void> skipToNext() => _c.next();
  @override
  Future<void> skipToPrevious() => _c.previous();
  @override
  Future<void> skipToQueueItem(int index) => _c.jumpTo(index);
  @override
  Future<void> seek(Duration position) async {
    await _c.seek(position);
    _publish(_c.state);
  }

  @override
  Future<void> setShuffleMode(svc.AudioServiceShuffleMode shuffleMode) =>
      _c.setShuffle(shuffleMode != svc.AudioServiceShuffleMode.none);
  @override
  Future<void> setRepeatMode(svc.AudioServiceRepeatMode repeatMode) => _c.setRepeat(switch (repeatMode) {
    svc.AudioServiceRepeatMode.none => RepeatMode.off,
    svc.AudioServiceRepeatMode.one => RepeatMode.one,
    _ => RepeatMode.all,
  });

  /// Platforms where audio_service provides system integration.
  static bool get supported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}
