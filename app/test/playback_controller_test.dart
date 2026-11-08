import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ttyfm/data/models.dart';
import 'package:ttyfm/playback/audio_engine.dart';
import 'package:ttyfm/playback/playback_controller.dart';

/// In-memory engine that mimics mpv's playlist behaviour closely enough to
/// test the controller.
class FakeEngine implements AudioEngine {
  final urls = <String>[];
  int current = -1;
  bool isPlaying = false;
  Duration pos = Duration.zero;
  RepeatMode repeat = RepeatMode.off;
  final opens = <({int index, Duration start, bool play})>[];

  final _index = StreamController<int>.broadcast(sync: true);
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _completed = StreamController<void>.broadcast(sync: true);

  @override
  Stream<int> get index => _index.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<void> get completed => _completed.stream;
  @override
  Stream<String> get errors => const Stream.empty();

  void _setPlaying(bool p) {
    isPlaying = p;
    _playing.add(p);
  }

  /// Simulates playback progressing to [to] within the current track.
  void tick(Duration to) {
    pos = to;
    _position.add(to);
  }

  /// Simulates the current track ending naturally.
  void finishTrack() {
    if (current < urls.length - 1) {
      current++;
      pos = Duration.zero;
      _index.add(current);
      _position.add(Duration.zero);
    } else {
      _setPlaying(false);
      _completed.add(null);
    }
  }

  @override
  Future<void> open(
    List<EngineSource> sources, {
    int index = 0,
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    opens.add((index: index, start: start, play: play));
    urls
      ..clear()
      ..addAll(sources.map((s) => s.url));
    current = index;
    _index.add(index);
    pos = start;
    _setPlaying(play);
  }

  @override
  Future<void> add(EngineSource source) async => urls.add(source.url);
  @override
  Future<void> move(int from, int to) async => urls.insert(to, urls.removeAt(from));
  @override
  Future<void> remove(int index) async {
    urls.removeAt(index);
    if (index < current) current--; // like mpv: the playing entry keeps playing
  }

  @override
  Future<void> jump(int index) async {
    current = index;
    _index.add(index);
  }

  @override
  Future<void> play() async => _setPlaying(true);
  @override
  Future<void> pause() async => _setPlaying(false);
  @override
  Future<void> seek(Duration position) async => tick(position);
  @override
  Future<void> stop() async {
    urls.clear();
    current = -1;
    _setPlaying(false);
  }

  @override
  Future<void> setRepeat(RepeatMode mode) async => repeat = mode;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
}

Track t(int id, {int durationMs = 200000}) =>
    Track(id: id, title: 'T$id', artistId: 1, artist: 'A', albumId: 1, album: 'B', durationMs: durationMs);

void main() {
  late FakeEngine engine;
  late PlaybackController c;
  late List<PlayRecord> plays;

  setUp(() {
    engine = FakeEngine();
    plays = [];
    c = PlaybackController(engine, sourceFor: (t) => EngineSource('u${t.id}'), onPlay: plays.add);
  });

  List<int> ids() => [for (final q in c.state.queue) q.track.id];

  test('playTracks opens the engine at the chosen index', () async {
    await c.playTracks([t(1), t(2), t(3)], index: 1);
    expect(c.state.current!.id, 2);
    expect(engine.urls, ['u1', 'u2', 'u3']);
    expect(engine.current, 1);
    expect(c.state.playing, isTrue);
  });

  test('natural advance follows the engine and records a full play', () async {
    await c.playTracks([t(1), t(2)]);
    for (var s = 1; s <= 200; s++) {
      engine.tick(Duration(seconds: s));
    }
    engine.finishTrack();
    expect(c.state.index, 1);
    expect(plays, hasLength(1));
    expect(plays.single.trackId, 1);
    expect(plays.single.skipped, isFalse);
    expect(plays.single.listenedMs, closeTo(200000, 1000));
  });

  test('next() early counts as a skip, seeks do not count as listening', () async {
    await c.playTracks([t(1), t(2), t(3)]);
    engine.tick(const Duration(seconds: 1));
    engine.tick(const Duration(seconds: 2));
    await c.seek(const Duration(seconds: 150)); // jump ahead: not listened
    engine.tick(const Duration(seconds: 151));
    await c.next();
    expect(c.state.current!.id, 2);
    expect(plays.single.skipped, isTrue);
    expect(plays.single.listenedMs, 3000);
  });

  test('previous restarts the track after 3 s, else goes back', () async {
    await c.playTracks([t(1), t(2)], index: 1);
    engine.tick(const Duration(seconds: 10));
    await c.previous();
    expect(c.state.index, 1);
    expect(engine.pos, Duration.zero);
    await c.previous();
    expect(c.state.index, 0);
  });

  test('playNext and addToQueue keep engine and queue in sync', () async {
    await c.playTracks([t(1), t(2), t(3)]);
    await c.addToQueue([t(9)]);
    await c.playNext([t(7), t(8)]);
    expect(ids(), [1, 7, 8, 2, 3, 9]);
    expect(engine.urls, ['u1', 'u7', 'u8', 'u2', 'u3', 'u9']);
  });

  group('hidden tracks', () {
    setUp(() => c.isHidden = (t) => t.id == 2 || t.id == 4);

    test('are left out of the queue', () async {
      await c.playTracks([t(1), t(2), t(3), t(4), t(5)], index: 2);
      expect(ids(), [1, 3, 5]);
      expect(engine.urls, ['u1', 'u3', 'u5']);
      expect(c.state.current!.id, 3);
    });

    test('a hidden pick starts at the next track that is not', () async {
      await c.playTracks([t(1), t(2), t(3)], index: 1);
      expect(c.state.current!.id, 3);
      await c.playTracks([t(1), t(3), t(4)], index: 2);
      expect(c.state.current!.id, 1);
      await c.playTracks([t(2), t(4)]);
      expect(c.state.current!.id, 1); // nothing playable: unchanged
    });

    test('are not added by playNext or addToQueue', () async {
      await c.playTracks([t(1)]);
      await c.addToQueue([t(2), t(3)]);
      await c.playNext([t(4)]);
      expect(ids(), [1, 3]);
    });

    test('dropHidden takes them out of the queue', () async {
      c.isHidden = (_) => false;
      await c.playTracks([t(1), t(2), t(3), t(4), t(5)]);
      c.isHidden = (t) => t.id == 2 || t.id == 4;
      await c.dropHidden();
      expect(ids(), [1, 3, 5]);
      expect(engine.urls, ['u1', 'u3', 'u5']);
      expect(c.state.current!.id, 1);
    });

    test('hiding the current track skips to the next one', () async {
      c.isHidden = (_) => false;
      await c.playTracks([t(1), t(2), t(3), t(4)], index: 1);
      engine.tick(const Duration(seconds: 5));
      c.isHidden = (t) => t.id == 2 || t.id == 4;
      await c.dropHidden();
      expect(ids(), [1, 3]);
      expect(engine.urls, ['u1', 'u3']);
      expect(c.state.current!.id, 3);
      expect(engine.current, 1);
      expect(c.state.playing, isTrue);
      expect(plays.single.trackId, 2);
      expect(plays.single.skipped, isTrue);
    });

    test('hiding the last track goes back to the top, paused', () async {
      c.isHidden = (_) => false;
      await c.playTracks([t(1), t(3), t(2)], index: 2);
      c.isHidden = (t) => t.id == 2;
      await c.dropHidden();
      expect(ids(), [1, 3]);
      expect(c.state.current!.id, 1);
      expect(engine.current, 0);
      expect(c.state.playing, isFalse);
    });

    test('hiding the last track with repeat all plays on from the top', () async {
      c.isHidden = (_) => false;
      await c.playTracks([t(1), t(3), t(2)], index: 2);
      await c.setRepeat(RepeatMode.all);
      c.isHidden = (t) => t.id == 2;
      await c.dropHidden();
      expect(ids(), [1, 3]);
      expect(c.state.current!.id, 1);
      expect(c.state.playing, isTrue);
    });

    test('hiding the only track stops playback', () async {
      c.isHidden = (_) => false;
      await c.playTracks([t(2)]);
      c.isHidden = (t) => t.id == 2;
      await c.dropHidden();
      expect(c.state.queue, isEmpty);
      expect(c.state.playing, isFalse);
    });
  });

  test('move and remove keep the current track', () async {
    await c.playTracks([t(1), t(2), t(3), t(4)], index: 1);
    await c.move(3, 0);
    expect(ids(), [4, 1, 2, 3]);
    expect(c.state.current!.id, 2);
    expect(engine.urls, ['u4', 'u1', 'u2', 'u3']);
    await c.removeAt(0);
    expect(ids(), [1, 2, 3]);
    expect(c.state.current!.id, 2);
    expect(engine.urls, ['u1', 'u2', 'u3']);
  });

  test('shuffle keeps the current track and restores the order', () async {
    final tracks = [for (var i = 1; i <= 20; i++) t(i)];
    await c.playTracks(tracks, index: 4);
    engine.tick(const Duration(seconds: 30));
    await c.setShuffle(true);
    expect(c.state.current!.id, 5);
    expect(ids().sublist(0, 5), [1, 2, 3, 4, 5]); // history untouched
    expect(ids().toSet(), tracks.map((t) => t.id).toSet());
    expect(engine.opens.last.start, const Duration(seconds: 30)); // resumes in place
    await c.setShuffle(false);
    expect(ids(), [for (var i = 1; i <= 20; i++) i]);
    expect(c.state.current!.id, 5);
    expect(plays, isEmpty); // reordering is not a track change
  });

  test('playTracks with shuffle starts with the chosen track', () async {
    await c.playTracks([for (var i = 1; i <= 10; i++) t(i)], index: 6, shuffle: true);
    expect(c.state.index, 0);
    expect(c.state.current!.id, 7);
    expect(c.state.shuffle, isTrue);
  });

  test('end of queue stops; play restarts from the top', () async {
    await c.playTracks([t(1)]);
    for (var s = 1; s <= 199; s++) {
      engine.tick(Duration(seconds: s));
    }
    engine.finishTrack();
    expect(c.state.playing, isFalse);
    expect(plays.single.skipped, isFalse);
    await c.play();
    expect(c.state.index, 0);
    expect(engine.isPlaying, isTrue);
  });

  test('repeat one records each loop', () async {
    await c.playTracks([t(1, durationMs: 10000)]);
    await c.setRepeat(RepeatMode.one);
    for (var s = 1; s <= 9; s++) {
      engine.tick(Duration(seconds: s));
    }
    engine.tick(const Duration(milliseconds: 9900));
    engine.tick(const Duration(milliseconds: 100)); // engine looped
    expect(plays, hasLength(1));
    expect(engine.repeat, RepeatMode.one);
  });

  test('persistence round-trip restores queue, order and position', () async {
    await c.playTracks([t(1), t(2), t(3)], index: 2);
    engine.tick(const Duration(seconds: 42));
    final saved = c.toJson();

    final engine2 = FakeEngine();
    final c2 = PlaybackController(engine2, sourceFor: (t) => EngineSource('u${t.id}'));
    await c2.restore(saved);
    expect([for (final q in c2.state.queue) q.track.id], [1, 2, 3]);
    expect(c2.state.current!.id, 3);
    expect(engine2.opens.single.start, const Duration(seconds: 42));
    expect(engine2.opens.single.play, isFalse);
  });

  test('refreshSources rebuilds urls in place', () async {
    await c.playTracks([t(1), t(2)], index: 1);
    engine.tick(const Duration(seconds: 5));
    c.sourceFor = (t) => EngineSource('remote${t.id}');
    await c.refreshSources();
    expect(engine.urls, ['remote1', 'remote2']);
    expect(engine.opens.last.index, 1);
    expect(engine.opens.last.start, const Duration(seconds: 5));
  });

  group('radio', () {
    late List<({RadioSeed seed, List<int> recent, List<int> exclude})> calls;
    var nextId = 100;
    setUp(() {
      calls = [];
      nextId = 100;
      c.fetchRadio = (seed, {recent = const [], exclude = const []}) async {
        calls.add((seed: seed, recent: recent, exclude: exclude));
        return [for (var i = 0; i < 4; i++) t(nextId++)];
      };
    });
    Future<void> settle() => Future<void>.delayed(Duration.zero);
    List<QueueSource> sources() => [for (final q in c.state.queue) q.source];

    test('from the current track it replaces the rest of the queue', () async {
      await c.playTracks([t(1), t(2), t(3)]);
      await c.addToQueue([t(4)]);
      expect(c.state.hasUserUpcoming, isTrue);
      await c.startRadio(RadioSeed.track(t(1)), from: t(1));
      expect(ids(), [1, 100, 101, 102, 103]);
      expect(engine.urls, ['u1', 'u100', 'u101', 'u102', 'u103']);
      expect(sources().skip(1), everyElement(QueueSource.radio));
      expect(c.state.radio, RadioSeed.track(t(1)));
      expect(calls.single.recent, [1]);
      expect(calls.single.exclude, [1]);
      expect(c.state.hasUserUpcoming, isFalse);
    });

    test('from another track it plays it, then the radio', () async {
      await c.playTracks([t(1), t(2)]);
      await c.startRadio(RadioSeed.track(t(7)), from: t(7));
      expect(ids(), [7, 100, 101, 102, 103]);
      expect(c.state.current!.id, 7);
      expect(c.state.contextKind, 'radio');
    });

    test('an artist radio plays its first batch', () async {
      await c.startRadio(const RadioSeed('artist', 5, 'X'));
      expect(ids(), [100, 101, 102, 103]);
      expect(c.state.radio!.kind, 'artist');
      expect(calls.single.seed.id, 5);
    });

    test('the radio loads more when few tracks are left', () async {
      await c.startRadio(RadioSeed.track(t(1)), from: t(1));
      expect(calls, hasLength(1));
      engine.finishTrack(); // now at 100, three left: still enough
      await settle();
      expect(calls, hasLength(1));
      engine.finishTrack(); // at 101, two left
      await settle();
      expect(calls, hasLength(2));
      expect(calls.last.recent, [1, 100, 101]);
      expect(calls.last.exclude, [1, 100, 101, 102, 103]);
      expect(ids(), [1, 100, 101, 102, 103, 104, 105, 106, 107]);
    });

    test('tracks added by the user go before the radio', () async {
      await c.startRadio(RadioSeed.track(t(1)), from: t(1));
      await c.addToQueue([t(9)]);
      expect(ids(), [1, 9, 100, 101, 102, 103]);
      expect(engine.urls, ['u1', 'u9', 'u100', 'u101', 'u102', 'u103']);
      expect(c.state.queue[1].source, QueueSource.user);
    });

    test('a new list stops the radio', () async {
      await c.startRadio(RadioSeed.track(t(1)), from: t(1));
      await c.playTracks([t(1), t(2)]);
      expect(c.state.radio, isNull);
      expect(sources(), everyElement(QueueSource.context));
    });

    test('autoplay starts a radio at the last track, if on and repeat is off', () async {
      await c.playTracks([t(1), t(2)]);
      engine.finishTrack(); // last track, autoplay off
      await settle();
      expect(calls, isEmpty);

      var on = true;
      c.autoplay = () => on;
      await c.playTracks([t(1), t(2)]);
      engine.finishTrack();
      await settle();
      expect(calls.single.seed, RadioSeed.track(t(2)));
      expect(ids(), [1, 2, 100, 101, 102, 103]);
      expect(c.state.radio, RadioSeed.track(t(2)));

      calls.clear();
      await c.setRepeat(RepeatMode.all);
      await c.playTracks([t(1)]);
      await settle();
      expect(calls, isEmpty);
      on = false;
    });

    test('a batch arriving after the queue changed is dropped', () async {
      final pending = Completer<List<Track>>();
      c.fetchRadio = (seed, {recent = const [], exclude = const []}) => pending.future;
      c.autoplay = () => true;
      await c.playTracks([t(1)]); // last track: autoplay asks for a batch
      c.fetchRadio = null;
      await c.playTracks([t(5), t(6)]);
      pending.complete([t(100)]);
      await settle();
      expect(ids(), [5, 6]);
    });

    test('the queue sources and the radio survive a restore', () async {
      await c.startRadio(RadioSeed.track(t(1)), from: t(1));
      await c.addToQueue([t(9)]);
      final engine2 = FakeEngine();
      final c2 = PlaybackController(engine2, sourceFor: (t) => EngineSource('u${t.id}'));
      await c2.restore(c.toJson());
      expect(c2.state.radio, RadioSeed.track(t(1)));
      expect(
        [for (final q in c2.state.queue) q.source],
        [QueueSource.context, QueueSource.user, ...List.filled(4, QueueSource.radio)],
      );
    });
  });
}
