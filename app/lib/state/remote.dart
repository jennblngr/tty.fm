import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/live.dart';
import '../data/models.dart';
import '../offline/downloads.dart';
import '../playback/audio_engine.dart';
import '../playback/playback_controller.dart';
import 'library.dart';
import 'notifications.dart';
import 'playback.dart';
import 'search.dart';

/// What another device is playing, as last reported over the live hub.
class RemoteState {
  RemoteState({
    required this.track,
    required this.playing,
    required this.position,
    required this.duration,
    required this.volume,
    required this.shuffle,
    required this.repeat,
    required this.index,
    required this.queueLength,
    required this.queueOffset,
    required this.queue,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  final Track? track;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool shuffle;
  final RepeatMode repeat;
  final int index;
  final int queueLength;

  /// The queue is sent as a window around the current track: [queue][0] is
  /// at absolute index [queueOffset].
  final int queueOffset;
  final List<Track> queue;
  final DateTime receivedAt;

  /// Position extrapolated from the last report (measured on our clock, so
  /// devices need not agree on the time).
  Duration positionNow() {
    if (!playing) return position;
    final p = position + DateTime.now().difference(receivedAt);
    return duration > Duration.zero && p > duration ? duration : p;
  }

  factory RemoteState.fromJson(Map<String, dynamic> j) => RemoteState(
    track: j['track'] == null ? null : Track.fromJson(j['track'] as Map<String, dynamic>),
    playing: j['playing'] as bool? ?? false,
    position: Duration(milliseconds: j['position_ms'] as int? ?? 0),
    duration: Duration(milliseconds: j['duration_ms'] as int? ?? 0),
    volume: (j['volume'] as num? ?? 1).toDouble(),
    shuffle: j['shuffle'] as bool? ?? false,
    repeat: RepeatMode.values.asNameMap()[j['repeat']] ?? RepeatMode.off,
    index: j['index'] as int? ?? -1,
    queueLength: j['queue_length'] as int? ?? 0,
    queueOffset: j['queue_offset'] as int? ?? 0,
    queue: [for (final t in j['queue'] as List? ?? const []) Track.fromJson(t as Map<String, dynamic>)],
  );

  /// Snapshot of the local player in the same shape.
  static Map<String, dynamic> encode(PlaybackController c) {
    final s = c.state;
    final from = max(0, s.index - 10);
    final to = min(s.queue.length, max(s.index, 0) + 51);
    return {
      'track': s.current?.toJson(),
      'playing': s.playing,
      'position_ms': c.position.inMilliseconds,
      'duration_ms': s.duration.inMilliseconds,
      'volume': s.volume,
      'shuffle': s.shuffle,
      'repeat': s.repeat.name,
      'index': s.index,
      'queue_length': s.queue.length,
      'queue_offset': from,
      'queue': [for (final q in s.queue.sublist(from, to)) q.track.toJson()],
    };
  }
}

class RemoteDevice {
  const RemoteDevice({required this.id, required this.name, required this.platform, this.state});
  final int id;
  final String name;
  final String platform;
  final RemoteState? state;

  RemoteDevice withState(RemoteState? s) => RemoteDevice(id: id, name: name, platform: platform, state: s);

  factory RemoteDevice.fromJson(Map<String, dynamic> j) => RemoteDevice(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    platform: j['platform'] as String? ?? '',
    state: j['state'] is Map<String, dynamic> ? RemoteState.fromJson(j['state'] as Map<String, dynamic>) : null,
  );
}

/// The other online devices of this account, and our own device id.
class RemoteDevices {
  const RemoteDevices({this.selfId, this.devices = const {}, this.connected = false});
  final int? selfId;
  final Map<int, RemoteDevice> devices;
  final bool connected;

  /// A device playing something right now, if any (for the "playing on…" bar).
  RemoteDevice? get activeElsewhere =>
      devices.values.where((d) => d.state?.playing == true && d.state?.track != null).firstOrNull;
}

class RemoteDevicesNotifier extends Notifier<RemoteDevices> {
  @override
  RemoteDevices build() {
    final live = ref.watch(liveConnectionProvider);
    final subs = [
      live.messages.listen(_onMessage),
      live.connectedChanges.listen((on) {
        // Offline: other devices are unknown until the next hello.
        state = on
            ? RemoteDevices(selfId: state.selfId, devices: state.devices, connected: true)
            : const RemoteDevices();
      }),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    return RemoteDevices(connected: live.isConnected);
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['type']) {
      case 'hello':
        state = RemoteDevices(
          selfId: m['device_id'] as int?,
          connected: true,
          devices: {
            for (final d in m['devices'] as List? ?? const [])
              (d as Map<String, dynamic>)['id'] as int: RemoteDevice.fromJson(d),
          },
        );
      case 'presence':
        final d = RemoteDevice.fromJson(m['device'] as Map<String, dynamic>);
        final next = {...state.devices};
        if (m['online'] == true) {
          next[d.id] = d;
        } else {
          next.remove(d.id);
        }
        state = RemoteDevices(selfId: state.selfId, devices: next, connected: true);
      case 'state':
        final id = m['device_id'] as int;
        final d = state.devices[id];
        if (d == null || m['state'] is! Map<String, dynamic>) return;
        state = RemoteDevices(
          selfId: state.selfId,
          connected: true,
          devices: {...state.devices, id: d.withState(RemoteState.fromJson(m['state'] as Map<String, dynamic>))},
        );
    }
  }
}

final remoteDevicesProvider = NotifierProvider<RemoteDevicesNotifier, RemoteDevices>(RemoteDevicesNotifier.new);

/// Sends commands to other devices.
class RemoteControl {
  RemoteControl(this._live);
  final LiveConnection _live;

  bool send(int target, String action, [Map<String, dynamic>? args]) =>
      _live.send({'type': 'command', 'target': target, 'action': action, 'args': ?args});

  /// Moves playback from [from] to [to] (either may be this device: the
  /// source device sends its queue to the target, then pauses).
  bool transfer({required int from, required int to}) => send(from, 'transfer', {'to': to});
}

final remoteControlProvider = Provider<RemoteControl>((ref) => RemoteControl(ref.watch(liveConnectionProvider)));

/// Keeps this device in the live hub: publishes the local playback state,
/// executes commands from other devices and refreshes data when another
/// device (or a scan) changes it. Read once at startup.
final liveSyncProvider = Provider<void>((ref) {
  final live = ref.watch(liveConnectionProvider);
  final c = ref.watch(playbackControllerProvider);
  var hadConnection = false;

  void publish() => live.send({'type': 'state', 'state': RemoteState.encode(c)});

  void refresh(String what) {
    switch (what) {
      case 'library':
        ref.invalidate(homeProvider);
        ref.invalidate(artistsProvider);
        ref.invalidate(albumsProvider);
        ref.invalidate(tracksProvider);
        ref.invalidate(artistProvider);
        ref.invalidate(albumProvider);
        ref.invalidate(searchFacetsProvider);
        ref.invalidate(notificationsProvider); // generated from the additions
      case 'notifications':
        ref.invalidate(notificationsProvider);
      case 'playlists':
        ref.invalidate(playlistTreeProvider);
        ref.invalidate(playlistTracksProvider);
      case 'favorites':
        ref.invalidate(favoritesProvider);
    }
    ref.read(downloadsProvider.notifier).resync(); // downloaded playlists follow
  }

  Future<void> handle(String action, Map<String, dynamic> a) async {
    switch (action) {
      case 'play':
        await c.play();
      case 'pause':
        await c.pause();
      case 'toggle':
        await c.togglePlay();
      case 'next':
        await c.next();
      case 'previous':
        await c.previous();
      case 'seek':
        await c.seek(Duration(milliseconds: a['ms'] as int? ?? 0));
      case 'volume':
        await c.setVolume((a['value'] as num? ?? 1).toDouble());
      case 'jump':
        await c.jumpTo(a['index'] as int);
      case 'remove':
        await c.removeAt(a['index'] as int);
      case 'move':
        await c.move(a['from'] as int, a['to'] as int);
      case 'shuffle':
        await c.setShuffle(a['on'] as bool? ?? false);
      case 'repeat':
        await c.setRepeat(RepeatMode.values.asNameMap()[a['mode']] ?? RepeatMode.off);
      case 'load':
        await c.load(a, play: a['playing'] as bool? ?? true);
      case 'transfer':
        final to = a['to'] as int?;
        if (to == null || c.state.current == null) return;
        final snapshot = c.toJson()
          ..remove('volume') // each device keeps its own volume
          ..['playing'] = true;
        if (live.send({'type': 'command', 'target': to, 'action': 'load', 'args': snapshot})) await c.pause();
    }
  }

  // Publish on meaningful changes (debounced), on seeks, and every 10 s
  // while playing so others can correct their extrapolated position.
  String? lastKey;
  Timer? debounce;
  void schedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), publish);
  }

  var lastPos = Duration.zero;
  var lastPosAt = DateTime.now();
  final subs = <StreamSubscription<dynamic>>[
    live.messages.listen((m) {
      switch (m['type']) {
        case 'hello':
          if (hadConnection) {
            // Reconnected: we may have missed changes.
            for (final w in const ['library', 'playlists', 'favorites', 'notifications']) {
              refresh(w);
            }
          }
          hadConnection = true;
          publish();
        case 'changed':
          refresh(m['what'] as String? ?? '');
        case 'command':
          handle(m['action'] as String? ?? '', (m['args'] as Map<String, dynamic>?) ?? const {});
      }
    }),
    c.states.listen((s) {
      final key = '${s.current?.id}|${s.playing}|${s.index}|${s.queue.length}|${s.shuffle}|${s.repeat}|${s.volume}';
      if (key != lastKey) {
        lastKey = key;
        schedule();
      }
    }),
    c.positions.listen((p) {
      final now = DateTime.now();
      final expected = lastPos + (c.state.playing ? now.difference(lastPosAt) : Duration.zero);
      if ((p - expected).abs() > const Duration(seconds: 2)) schedule();
      lastPos = p;
      lastPosAt = now;
    }),
  ];
  final periodic = Timer.periodic(const Duration(seconds: 10), (_) {
    if (c.state.playing) publish();
  });
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    debounce?.cancel();
    periodic.cancel();
  });
});
