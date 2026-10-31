import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'audio_engine.dart';

/// [AudioEngine] backed by media_kit (libmpv) on every platform.
class MediaKitEngine implements AudioEngine {
  MediaKitEngine() {
    final native = _player.platform;
    if (native is NativePlayer) {
      // Gapless transitions, and open the next item early so a transcoded
      // stream is already flowing when the current track ends.
      native.setProperty('gapless-audio', 'yes');
      native.setProperty('prefetch-playlist', 'yes');
      // Keep the whole track in memory: lets seeking work inside
      // transcoded streams that have no HTTP Range support.
      native.setProperty('cache', 'yes');
      native.setProperty('demuxer-max-back-bytes', '${64 << 20}');
      native.setProperty('audio-display', 'no');
    }
    _subs.add(
      _player.stream.playlist.listen((p) {
        if (p.medias.isNotEmpty) _index.add(p.index);
      }),
    );
  }

  final _player = Player(
    configuration: const PlayerConfiguration(title: 'selfstream', bufferSize: 64 << 20),
  );
  final _index = StreamController<int>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];

  Media _media(EngineSource s) => Media(s.url, httpHeaders: s.headers);

  @override
  Stream<int> get index => _index.stream.distinct();
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<void> get completed => _player.stream.completed.where((c) => c);
  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Future<void> open(List<EngineSource> sources, {int index = 0, Duration start = Duration.zero, bool play = true}) {
    final medias = [
      for (var i = 0; i < sources.length; i++)
        i == index && start > Duration.zero
            ? Media(sources[i].url, httpHeaders: sources[i].headers, start: start)
            : _media(sources[i]),
    ];
    return _player.open(Playlist(medias, index: index), play: play);
  }

  @override
  Future<void> add(EngineSource source) => _player.add(_media(source));

  // mpv's playlist-move inserts *before* the target index.
  @override
  Future<void> move(int from, int to) => from == to ? Future.value() : _player.move(from, to > from ? to + 1 : to);

  @override
  Future<void> remove(int index) => _player.remove(index);
  @override
  Future<void> jump(int index) => _player.jump(index);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setRepeat(RepeatMode mode) => _player.setPlaylistMode(switch (mode) {
    RepeatMode.off => PlaylistMode.none,
    RepeatMode.all => PlaylistMode.loop,
    RepeatMode.one => PlaylistMode.single,
  });

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume * 100);

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _index.close();
    await _player.dispose();
  }
}
