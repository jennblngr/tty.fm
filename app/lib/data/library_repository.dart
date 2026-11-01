import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/json_cache.dart';
import 'models.dart';

/// Access to the library. Read methods return streams that first emit the
/// cached copy (instant display), then the fresh server copy if it differs.
class LibraryRepository {
  LibraryRepository(this._api, this._cache);

  final ApiClient _api;
  final JsonCache _cache;

  Stream<T> _cached<T>(String key, Future<Object?> Function() fetch, T Function(dynamic) parse) async* {
    final cached = await _cache.read(key);
    if (cached != null) yield parse(cached);
    try {
      final fresh = await fetch();
      if (await _cache.write(key, fresh) || cached == null) yield parse(fresh);
    } catch (e) {
      if (cached == null) rethrow; // offline with a warm cache: keep showing it
    }
  }

  /// Fetches every page of a paginated list (the whole library is small
  /// enough: ~5,000 tracks) so lists scroll and filter without waiting.
  Future<List<dynamic>> _all(String path, [Map<String, dynamic> query = const {}]) async {
    final out = <dynamic>[];
    String? cursor;
    do {
      final page = await _api.get(path, query: {...query, 'limit': 500, 'cursor': ?cursor}) as Map<String, dynamic>;
      out.addAll(page['items'] as List);
      cursor = page['next'] as String?;
    } while (cursor != null);
    return out;
  }

  static List<T> _list<T>(dynamic j, T Function(Map<String, dynamic>) f) => [
    for (final e in j as List) f(e as Map<String, dynamic>),
  ];

  Stream<HomeData> home() =>
      _cached('home', () => _api.get('/home'), (j) => HomeData.fromJson(j as Map<String, dynamic>));

  Stream<List<Artist>> artists() =>
      _cached('artists', () => _all('/artists', {'album_artists': '1'}), (j) => _list(j, Artist.fromJson));

  Stream<List<Album>> albums(String sort) =>
      _cached('albums:$sort', () => _all('/albums', {'sort': sort}), (j) => _list(j, Album.fromJson));

  Stream<List<Track>> tracks() =>
      _cached('tracks', () => _all('/tracks', {'sort': 'name'}), (j) => _list(j, Track.fromJson));

  Stream<(Artist, List<Album>)> artist(int id) => _cached('artist:$id', () => _api.get('/artists/$id'), (j) {
    final m = j as Map<String, dynamic>;
    return (Artist.fromJson(m['artist'] as Map<String, dynamic>), _list(m['albums'], Album.fromJson));
  });

  Stream<(Album, List<Track>)> album(int id) => _cached('album:$id', () => _api.get('/albums/$id'), (j) {
    final m = j as Map<String, dynamic>;
    return (Album.fromJson(m['album'] as Map<String, dynamic>), _list(m['tracks'], Track.fromJson));
  });

  /// Search goes straight to the server (FTS answers in milliseconds);
  /// [cancel] aborts the previous keystroke's request.
  /// Text search, optionally narrowed by [filter]. Filter-only searches list
  /// what matches (up to [limit]).
  Future<SearchResult> search(
    String q, {
    SearchFilter filter = const SearchFilter(),
    int limit = 20,
    CancelToken? cancel,
  }) async => SearchResult.fromJson(
    await _api.get('/search', query: {'q': q, 'limit': limit, ...filter.toQuery()}, cancel: cancel),
  );

  /// Listening stats over the last [days] days (0: all time).
  Stream<ListeningStats> stats(int days) => _cached(
    'stats:$days',
    () => _api.get('/stats', query: {'days': days}),
    (j) => ListeningStats.fromJson(j as Map<String, dynamic>),
  );

  Stream<SearchFacets> searchFacets() => _cached(
    'search:facets',
    () => _api.get('/search/facets'),
    (j) => SearchFacets.fromJson(j as Map<String, dynamic>),
  );

  /// Lyrics of a track, or null when it has none. Cached for offline use.
  Future<Lyrics?> lyrics(int trackId) async {
    final key = 'lyrics:$trackId';
    try {
      final j = await _api.get('/tracks/$trackId/lyrics');
      await _cache.write(key, j);
      return Lyrics.fromJson(j as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        await _cache.write(key, null);
        return null;
      }
      final cached = await _cache.read(key);
      if (cached is Map<String, dynamic>) return Lyrics.fromJson(cached);
      if (await _cache.readRaw(key) == 'null') return null; // known to have none
      rethrow;
    }
  }

  // --- playlists -----------------------------------------------------------

  Stream<PlaylistTree> playlistTree() => _cached(
    'playlists:tree',
    () => _api.get('/playlists/tree'),
    (j) => PlaylistTree.fromJson(j as Map<String, dynamic>),
  );

  Stream<List<PlaylistEntry>> playlistTracks(int id) => _cached(
    'playlist:$id:tracks',
    () => _api.get('/playlists/$id/tracks'),
    (j) => _list((j as Map)['items'], PlaylistEntry.fromJson),
  );

  Future<int> createFolder(String name, int? parentId) async =>
      (await _api.post('/folders', {'name': name, 'parent_id': parentId}))['id'] as int;

  Future<Playlist> createPlaylist(String name, int? folderId, [List<int> trackIds = const []]) async =>
      Playlist.fromJson(await _api.post('/playlists', {'name': name, 'folder_id': folderId, 'track_ids': trackIds}));

  Future<void> renameFolder(int id, String name) => _api.patch('/folders/$id', {'name': name});
  Future<void> moveFolder(int id, int? parentId, {int? position}) =>
      _api.patch('/folders/$id', {'parent_id': parentId, 'position': ?position});
  Future<void> deleteFolder(int id) => _api.delete('/folders/$id');

  Future<void> renamePlaylist(int id, String name) => _api.patch('/playlists/$id', {'name': name});
  Future<void> movePlaylist(int id, int? folderId, {int? position}) =>
      _api.patch('/playlists/$id', {'folder_id': folderId, 'position': ?position});
  Future<void> deletePlaylist(int id) => _api.delete('/playlists/$id');

  Future<void> addToPlaylist(int id, List<int> trackIds) => _api.post('/playlists/$id/tracks', {'track_ids': trackIds});
  Future<void> moveEntry(int id, int entryId, int to) =>
      _api.patch('/playlists/$id/tracks', {'entry_id': entryId, 'to_position': to});
  Future<void> removeEntry(int id, int entryId) => _api.delete('/playlists/$id/tracks/$entryId');

  // --- favourites, plays, admin ---------------------------------------------

  Future<Map<String, Set<int>>> favoriteIds() async {
    final j = await _api.get('/favorites') as Map<String, dynamic>;
    return {for (final e in j.entries) e.key: (e.value as List).cast<int>().toSet()};
  }

  /// Favourite tracks and albums, most recently added first.
  Stream<(List<Track>, List<Album>)> favorites() =>
      _cached('favorites', () => _api.get('/favorites', query: {'full': '1'}), (j) {
        final m = j as Map<String, dynamic>;
        return (_list(m['tracks'], Track.fromJson), _list(m['albums'], Album.fromJson));
      });

  Future<void> setFavorite(String kind, int id, bool on) =>
      on ? _api.put('/favorites/$kind/$id') : _api.delete('/favorites/$kind/$id');

  Future<void> reportPlays(List<PlayRecord> plays) => _api.post('/plays', {
    'plays': [for (final p in plays) p.toJson()],
  });

  Future<void> startScan({bool full = false}) => _api.post('/admin/scan${full ? '?full=1' : ''}');

  Future<Map<String, dynamic>> me() async => await _api.get('/me') as Map<String, dynamic>;

  Future<void> logout() => _api.post('/auth/logout');
}

final libraryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(apiProvider), ref.watch(jsonCacheProvider)),
);
