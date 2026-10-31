import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/network.dart';
import '../core/session.dart';
import '../core/settings.dart';
import '../data/library_repository.dart';
import '../data/models.dart';

/// Something the user chose to keep offline: an album, a playlist or the
/// favourite tracks. Its tracks are downloaded once even if shared.
class OfflineCollection {
  const OfflineCollection({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.coverIds = const [],
    this.trackIds = const [],
  });

  final String kind; // album | playlist | favorites
  final int id; // 0 for favorites
  final String title;
  final String subtitle;
  final List<int> coverIds;
  final List<int> trackIds;

  String get key => '$kind:$id';

  OfflineCollection withTracks(List<Track> tracks, {String? title, List<int>? coverIds}) => OfflineCollection(
    kind: kind,
    id: id,
    title: title ?? this.title,
    subtitle: subtitle,
    coverIds: coverIds ?? this.coverIds,
    trackIds: [for (final t in tracks) t.id],
  );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'cover_ids': coverIds,
    'track_ids': trackIds,
  };

  factory OfflineCollection.fromJson(Map<String, dynamic> j) => OfflineCollection(
    kind: j['kind'] as String,
    id: j['id'] as int,
    title: j['title'] as String? ?? '',
    subtitle: j['subtitle'] as String? ?? '',
    coverIds: (j['cover_ids'] as List? ?? const []).cast<int>(),
    trackIds: (j['track_ids'] as List? ?? const []).cast<int>(),
  );
}

class OfflineTrack {
  const OfflineTrack(this.track, this.file, this.size);
  final Track track;
  final String file; // name inside the offline directory
  final int size;

  Map<String, dynamic> toJson() => {'track': track.toJson(), 'file': file, 'size': size};

  factory OfflineTrack.fromJson(Map<String, dynamic> j) =>
      OfflineTrack(Track.fromJson(j['track'] as Map<String, dynamic>), j['file'] as String, j['size'] as int? ?? 0);
}

enum CollectionStatus { none, downloading, done }

class OfflineState {
  const OfflineState({
    this.collections = const {},
    this.tracks = const {},
    this.pending = const [],
    this.active,
    this.activeProgress = 0,
    this.waitingForWifi = false,
    this.error,
  });

  final Map<String, OfflineCollection> collections;
  final Map<int, OfflineTrack> tracks;

  /// Tracks still to download, in order.
  final List<Track> pending;
  final Track? active;
  final double activeProgress;
  final bool waitingForWifi;
  final String? error;

  int get totalBytes => tracks.values.fold(0, (s, t) => s + t.size);

  CollectionStatus status(String kind, int id) {
    final c = collections['$kind:$id'];
    if (c == null) return CollectionStatus.none;
    return c.trackIds.every(tracks.containsKey) ? CollectionStatus.done : CollectionStatus.downloading;
  }

  /// Downloaded / total tracks of a collection.
  (int, int) progress(String kind, int id) {
    final c = collections['$kind:$id'];
    if (c == null) return (0, 0);
    return (c.trackIds.where(tracks.containsKey).length, c.trackIds.length);
  }

  List<Track> tracksOf(OfflineCollection c) => [
    for (final id in c.trackIds)
      if (tracks[id] != null) tracks[id]!.track,
  ];

  OfflineState copyWith({
    Map<String, OfflineCollection>? collections,
    Map<int, OfflineTrack>? tracks,
    List<Track>? pending,
    Track? Function()? active,
    double? activeProgress,
    bool? waitingForWifi,
    String? Function()? error,
  }) => OfflineState(
    collections: collections ?? this.collections,
    tracks: tracks ?? this.tracks,
    pending: pending ?? this.pending,
    active: active != null ? active() : this.active,
    activeProgress: activeProgress ?? this.activeProgress,
    waitingForWifi: waitingForWifi ?? this.waitingForWifi,
    error: error != null ? error() : this.error,
  );
}

/// Downloads collections for offline playback and keeps them in sync with
/// the server (a track added to a downloaded playlist is downloaded, a
/// removed one deleted). Files live in the app support directory.
class DownloadManager extends Notifier<OfflineState> {
  Directory? _dir;
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  CancelToken? _cancel;
  bool _working = false;
  Timer? _saveTimer;
  Timer? _resyncTimer;

  @override
  OfflineState build() {
    ref.listen(routeProvider, (_, _) => _work());
    ref.listen(tokenProvider, (prev, next) {
      if (next.isEmpty && (prev ?? '').isNotEmpty) removeAll(); // logged out: ids belong to that server
    });
    ref.onDispose(() {
      _cancel?.cancel();
      _saveTimer?.cancel();
      _resyncTimer?.cancel();
    });
    _load();
    return const OfflineState();
  }

  File get _index => File('${_dir!.path}/index.json');

  Future<void> _load() async {
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/offline');
    await _dir!.create(recursive: true);
    var collections = <String, OfflineCollection>{};
    var tracks = <int, OfflineTrack>{};
    try {
      final j = jsonDecode(await _index.readAsString()) as Map<String, dynamic>;
      for (final c in j['collections'] as List? ?? const []) {
        final oc = OfflineCollection.fromJson(c as Map<String, dynamic>);
        collections[oc.key] = oc;
      }
      for (final t in j['tracks'] as List? ?? const []) {
        final ot = OfflineTrack.fromJson(t as Map<String, dynamic>);
        if (File('${_dir!.path}/${ot.file}').existsSync()) tracks[ot.track.id] = ot;
      }
    } catch (_) {}
    // Leftovers of interrupted downloads.
    for (final f in _dir!.listSync().whereType<File>().where((f) => f.path.endsWith('.part'))) {
      f.deleteSync();
    }
    state = state.copyWith(collections: collections, tracks: tracks);
    _enqueueMissing();
    resync();
  }

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () async {
      if (_dir == null) return;
      final tmp = File('${_index.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          'collections': [for (final c in state.collections.values) c.toJson()],
          'tracks': [for (final t in state.tracks.values) t.toJson()],
        }),
      );
      await tmp.rename(_index.path);
    });
  }

  /// Local file for a track, if downloaded.
  String? pathFor(int trackId) {
    final t = state.tracks[trackId];
    return t == null || _dir == null ? null : '${_dir!.path}/${t.file}';
  }

  /// Keeps [c] offline with [tracks] (adds or updates the collection).
  void add(OfflineCollection c, List<Track> tracks) {
    final col = c.withTracks(tracks);
    state = state.copyWith(collections: {...state.collections, col.key: col});
    _enqueue(tracks);
    _gc();
    _save();
  }

  void remove(String kind, int id) {
    final next = {...state.collections}..remove('$kind:$id');
    state = state.copyWith(collections: next);
    _gc();
    _save();
  }

  Future<void> removeAll() async {
    _cancel?.cancel();
    state = state.copyWith(collections: {}, pending: [], active: () => null);
    _gc();
    _save();
  }

  /// Re-reads every downloaded collection from the server (debounced).
  void resync() {
    _resyncTimer?.cancel();
    _resyncTimer = Timer(const Duration(seconds: 2), _resyncNow);
  }

  Future<void> _resyncNow() async {
    if (ref.read(tokenProvider).isEmpty) return;
    final repo = ref.read(libraryProvider);
    for (final c in [...state.collections.values]) {
      try {
        final List<Track> tracks;
        String? title;
        List<int>? covers;
        switch (c.kind) {
          case 'album':
            final (album, t) = await repo.album(c.id).last;
            tracks = t;
            title = album.title;
          case 'playlist':
            tracks = [for (final e in await repo.playlistTracks(c.id).last) e.track];
            covers = [for (final t in tracks.take(4)) ?t.coverId];
          case 'favorites':
            tracks = (await repo.favorites().last).$1;
          default:
            continue;
        }
        if (!state.collections.containsKey(c.key)) continue; // removed meanwhile
        final updated = c.withTracks(tracks, title: title, coverIds: covers);
        state = state.copyWith(collections: {...state.collections, c.key: updated});
        _enqueue(tracks);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) remove(c.kind, c.id); // deleted on the server
      } catch (_) {
        // offline: keep what we have
      }
    }
    _gc();
    _save();
  }

  void _enqueue(List<Track> tracks) {
    final queued = {for (final t in state.pending) t.id, ?state.active?.id};
    final add = [
      for (final t in tracks)
        if (!state.tracks.containsKey(t.id) && !queued.contains(t.id)) t,
    ];
    if (add.isEmpty) return;
    state = state.copyWith(pending: [...state.pending, ...add]);
    _work();
  }

  /// After a restart, re-queue tracks of collections not fully downloaded
  /// (the index only stores track ids for those: resync fetches them).
  void _enqueueMissing() {
    if (state.collections.values.any((c) => !c.trackIds.every(state.tracks.containsKey))) resync();
  }

  /// Deletes files no collection needs and drops unneeded queued tracks.
  void _gc() {
    final needed = {for (final c in state.collections.values) ...c.trackIds};
    final keep = <int, OfflineTrack>{};
    for (final e in state.tracks.entries) {
      if (needed.contains(e.key)) {
        keep[e.key] = e.value;
      } else {
        try {
          File('${_dir!.path}/${e.value.file}').deleteSync();
        } catch (_) {}
      }
    }
    final pending = [
      for (final t in state.pending)
        if (needed.contains(t.id)) t,
    ];
    if (state.active != null && !needed.contains(state.active!.id)) _cancel?.cancel();
    state = state.copyWith(tracks: keep, pending: pending);
  }

  bool get _networkAllowed {
    final s = ref.read(settingsProvider);
    return !(s.downloadWifiOnly && ref.read(routeProvider).link == LinkType.cellular);
  }

  Future<void> _work() async {
    if (_working || _dir == null) return;
    _working = true;
    try {
      while (state.pending.isNotEmpty && ref.read(tokenProvider).isNotEmpty) {
        if (!_networkAllowed) {
          state = state.copyWith(waitingForWifi: true);
          return; // resumed by the route listener
        }
        final t = state.pending.first;
        state = state.copyWith(
          pending: state.pending.sublist(1),
          active: () => t,
          activeProgress: 0,
          waitingForWifi: false,
        );
        try {
          final ot = await _download(t);
          if (ot != null) {
            state = state.copyWith(tracks: {...state.tracks, t.id: ot}, error: () => null);
            _gc(); // the collection may have been removed meanwhile
            _save();
          }
        } catch (e) {
          // Network trouble: put it back and retry later.
          state = state.copyWith(pending: [...state.pending, t], error: () => errorMessage(e));
          await Future<void>.delayed(const Duration(seconds: 20));
        }
      }
    } finally {
      state = state.copyWith(active: () => null, activeProgress: 0);
      _working = false;
    }
  }

  Future<OfflineTrack?> _download(Track t) async {
    final api = ref.read(apiProvider);
    final q = ref.read(settingsProvider).downloadQuality;
    final ext = q.format ?? t.format;
    final name = '${t.id}.$ext';
    final path = '${_dir!.path}/$name';
    final query = q.format == null ? '' : '?format=${q.format}&bitrate=${q.bitrate}';
    final cancel = _cancel = CancelToken();
    try {
      await _dio.download(
        api.url('/stream/${t.id}$query'),
        '$path.part',
        options: Options(headers: api.authHeaders),
        cancelToken: cancel,
        onReceiveProgress: (got, total) {
          if (total > 0) state = state.copyWith(activeProgress: got / total);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        try {
          File('$path.part').deleteSync();
        } catch (_) {}
        return null;
      }
      rethrow;
    }
    final f = await File('$path.part').rename(path);
    return OfflineTrack(t, name, await f.length());
  }
}

final downloadsProvider = NotifierProvider<DownloadManager, OfflineState>(DownloadManager.new);
