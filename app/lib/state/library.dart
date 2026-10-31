import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session.dart';
import '../data/library_repository.dart';
import '../data/models.dart';

// Read-side providers. Each one streams the cached copy first, then the
// server's. Watching tokenProvider refreshes everything after a re-login.

LibraryRepository _repo(Ref ref) {
  ref.watch(tokenProvider);
  return ref.watch(libraryProvider);
}

final homeProvider = StreamProvider<HomeData>((ref) => _repo(ref).home());

final artistsProvider = StreamProvider<List<Artist>>((ref) => _repo(ref).artists());

final albumsProvider = StreamProvider.family<List<Album>, String>((ref, sort) => _repo(ref).albums(sort));

final tracksProvider = StreamProvider<List<Track>>((ref) => _repo(ref).tracks());

final artistProvider = StreamProvider.autoDispose.family<(Artist, List<Album>), int>(
  (ref, id) => _repo(ref).artist(id),
);

final albumProvider = StreamProvider.autoDispose.family<(Album, List<Track>), int>((ref, id) => _repo(ref).album(id));

final playlistTreeProvider = StreamProvider<PlaylistTree>((ref) => _repo(ref).playlistTree());

final playlistTracksProvider = StreamProvider.autoDispose.family<List<PlaylistEntry>, int>(
  (ref, id) => _repo(ref).playlistTracks(id),
);

/// Favourite ids by kind ("tracks", "albums", "artists"), toggled
/// optimistically.
class FavoritesNotifier extends AsyncNotifier<Map<String, Set<int>>> {
  @override
  Future<Map<String, Set<int>>> build() => _repo(ref).favoriteIds();

  bool contains(String kind, int id) => state.value?[kind]?.contains(id) ?? false;

  Future<void> toggle(String kind, int id) async {
    final cur = state.value ?? {};
    final on = !(cur[kind]?.contains(id) ?? false);
    final next = {
      for (final e in cur.entries) e.key: {...e.value},
    };
    final set = next.putIfAbsent(kind, () => <int>{});
    on ? set.add(id) : set.remove(id);
    state = AsyncData(next);
    try {
      await ref.read(libraryProvider).setFavorite(kind, id, on);
    } catch (_) {
      state = AsyncData(cur); // revert
      rethrow;
    }
  }
}

final favoritesProvider = AsyncNotifierProvider<FavoritesNotifier, Map<String, Set<int>>>(FavoritesNotifier.new);

/// Playlist mutations. Each one refreshes the affected providers so every
/// screen showing the tree or the playlist updates.
class PlaylistActions {
  PlaylistActions(this._ref);
  final Ref _ref;

  LibraryRepository get _r => _ref.read(libraryProvider);

  void _refresh([int? playlistId]) {
    _ref.invalidate(playlistTreeProvider);
    if (playlistId != null) _ref.invalidate(playlistTracksProvider(playlistId));
  }

  Future<int> createFolder(String name, int? parentId) async {
    final id = await _r.createFolder(name, parentId);
    _refresh();
    return id;
  }

  Future<Playlist> createPlaylist(String name, int? folderId, [List<int> trackIds = const []]) async {
    final p = await _r.createPlaylist(name, folderId, trackIds);
    _refresh();
    return p;
  }

  Future<void> renameFolder(int id, String name) async {
    await _r.renameFolder(id, name);
    _refresh();
  }

  Future<void> moveFolder(int id, int? parentId) async {
    await _r.moveFolder(id, parentId);
    _refresh();
  }

  Future<void> deleteFolder(int id) async {
    await _r.deleteFolder(id);
    _refresh();
  }

  Future<void> renamePlaylist(int id, String name) async {
    await _r.renamePlaylist(id, name);
    _refresh(id);
  }

  Future<void> movePlaylist(int id, int? folderId) async {
    await _r.movePlaylist(id, folderId);
    _refresh();
  }

  Future<void> deletePlaylist(int id) async {
    await _r.deletePlaylist(id);
    _refresh();
  }

  Future<void> addTracks(int id, List<int> trackIds) async {
    await _r.addToPlaylist(id, trackIds);
    _refresh(id);
  }

  Future<void> moveEntry(int id, int entryId, int to) async {
    await _r.moveEntry(id, entryId, to);
    _refresh(id);
  }

  Future<void> removeEntry(int id, int entryId) async {
    await _r.removeEntry(id, entryId);
    _refresh(id);
  }
}

final playlistActionsProvider = Provider<PlaylistActions>(PlaylistActions.new);

/// Full favourite lists, refetched whenever a favourite is toggled.
final favoriteListsProvider = StreamProvider.autoDispose<(List<Track>, List<Album>)>((ref) {
  ref.watch(favoritesProvider);
  return _repo(ref).favorites();
});
