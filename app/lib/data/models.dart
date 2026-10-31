// Plain data classes mirroring the server's JSON. Kept free of Flutter
// imports so they can be shared with tests and, later, other front-ends.

class Artist {
  const Artist({required this.id, required this.name, this.albumCount = 0, this.coverId});

  final int id;
  final String name;
  final int albumCount;
  final int? coverId;

  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
        id: j['id'] as int,
        name: j['name'] as String,
        albumCount: j['album_count'] as int? ?? 0,
        coverId: j['cover_id'] as int?,
      );
}

class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artist,
    this.year,
    this.genre,
    this.coverId,
    this.trackCount = 0,
    this.durationMs = 0,
  });

  final int id;
  final String title;
  final int artistId;
  final String artist;
  final int? year;
  final String? genre;
  final int? coverId;
  final int trackCount;
  final int durationMs;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: j['id'] as int,
        title: j['title'] as String,
        artistId: j['artist_id'] as int,
        artist: j['artist'] as String,
        year: j['year'] as int?,
        genre: j['genre'] as String?,
        coverId: j['cover_id'] as int?,
        trackCount: j['track_count'] as int? ?? 0,
        durationMs: j['duration_ms'] as int? ?? 0,
      );
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artist,
    required this.albumId,
    required this.album,
    this.albumArtist = '',
    this.trackNo,
    this.discNo,
    this.year,
    required this.durationMs,
    this.format = '',
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    this.coverId,
  });

  final int id;
  final String title;
  final int artistId;
  final String artist;
  final int albumId;
  final String album;
  final String albumArtist;
  final int? trackNo;
  final int? discNo;
  final int? year;
  final int durationMs;
  final String format;
  final int? bitrate;
  final int? sampleRate;
  final int? bitDepth;
  final int? coverId;

  Duration get duration => Duration(milliseconds: durationMs);

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as int,
        title: j['title'] as String,
        artistId: j['artist_id'] as int,
        artist: j['artist'] as String,
        albumId: j['album_id'] as int,
        album: j['album'] as String,
        albumArtist: j['album_artist'] as String? ?? '',
        trackNo: j['track_no'] as int?,
        discNo: j['disc_no'] as int?,
        year: j['year'] as int?,
        durationMs: j['duration_ms'] as int,
        format: j['format'] as String? ?? '',
        bitrate: j['bitrate'] as int?,
        sampleRate: j['sample_rate'] as int?,
        bitDepth: j['bit_depth'] as int?,
        coverId: j['cover_id'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist_id': artistId,
        'artist': artist,
        'album_id': albumId,
        'album': album,
        'album_artist': albumArtist,
        'track_no': trackNo,
        'disc_no': discNo,
        'year': year,
        'duration_ms': durationMs,
        'format': format,
        'bitrate': bitrate,
        'sample_rate': sampleRate,
        'bit_depth': bitDepth,
        'cover_id': coverId,
      };
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.folderId,
    this.position = 0,
    this.trackCount = 0,
    this.durationMs = 0,
    this.coverIds = const [],
  });

  final int id;
  final String name;
  final int? folderId;
  final int position;
  final int trackCount;
  final int durationMs;
  final List<int> coverIds;

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as int,
        name: j['name'] as String,
        folderId: j['folder_id'] as int?,
        position: j['position'] as int? ?? 0,
        trackCount: j['track_count'] as int? ?? 0,
        durationMs: j['duration_ms'] as int? ?? 0,
        coverIds: (j['cover_ids'] as List? ?? const []).cast<int>(),
      );
}

class Folder {
  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.folders = const [],
    this.playlists = const [],
  });

  final int id;
  final String name;
  final int? parentId;
  final List<Folder> folders;
  final List<Playlist> playlists;

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as int,
        name: j['name'] as String,
        parentId: j['parent_id'] as int?,
        folders: [for (final f in j['folders'] as List? ?? const []) Folder.fromJson(f as Map<String, dynamic>)],
        playlists: [
          for (final p in j['playlists'] as List? ?? const []) Playlist.fromJson(p as Map<String, dynamic>)
        ],
      );
}

/// Root of the playlist hierarchy, with lookup helpers.
class PlaylistTree {
  const PlaylistTree({this.folders = const [], this.playlists = const []});

  final List<Folder> folders;
  final List<Playlist> playlists;

  factory PlaylistTree.fromJson(Map<String, dynamic> j) {
    final root = Folder.fromJson({'id': 0, 'name': '', ...j});
    return PlaylistTree(folders: root.folders, playlists: root.playlists);
  }

  /// The folder with [id], or null (null id = root, returned as null too).
  Folder? folder(int? id) {
    if (id == null) return null;
    Folder? walk(List<Folder> fs) {
      for (final f in fs) {
        if (f.id == id) return f;
        final r = walk(f.folders);
        if (r != null) return r;
      }
      return null;
    }

    return walk(folders);
  }

  /// Every folder, depth-first, with its depth (for move pickers).
  List<(Folder, int)> flatten() {
    final out = <(Folder, int)>[];
    void walk(List<Folder> fs, int depth) {
      for (final f in fs) {
        out.add((f, depth));
        walk(f.folders, depth + 1);
      }
    }

    walk(folders, 0);
    return out;
  }

  /// Ids of [id] and all its descendants (a folder cannot move into these).
  Set<int> subtree(int id) {
    final f = folder(id);
    if (f == null) return {};
    final out = <int>{};
    void walk(Folder f) {
      out.add(f.id);
      f.folders.forEach(walk);
    }

    walk(f);
    return out;
  }

  List<Playlist> get allPlaylists {
    final out = [...playlists];
    for (final (f, _) in flatten()) {
      out.addAll(f.playlists);
    }
    return out;
  }
}

class PlaylistEntry {
  const PlaylistEntry({required this.entryId, required this.position, required this.track});

  final int entryId;
  final int position;
  final Track track;

  factory PlaylistEntry.fromJson(Map<String, dynamic> j) => PlaylistEntry(
        entryId: j['entry_id'] as int,
        position: j['position'] as int,
        track: Track.fromJson(j['track'] as Map<String, dynamic>),
      );
}

class SearchResult {
  const SearchResult({this.artists = const [], this.albums = const [], this.tracks = const []});

  final List<Artist> artists;
  final List<Album> albums;
  final List<Track> tracks;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && tracks.isEmpty;

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        artists: [for (final a in j['artists'] as List) Artist.fromJson(a as Map<String, dynamic>)],
        albums: [for (final a in j['albums'] as List) Album.fromJson(a as Map<String, dynamic>)],
        tracks: [for (final t in j['tracks'] as List) Track.fromJson(t as Map<String, dynamic>)],
      );
}

class HomeData {
  const HomeData({this.recentlyAdded = const [], this.recentlyPlayed = const [], this.recentTracks = const []});

  final List<Album> recentlyAdded;
  final List<Album> recentlyPlayed;
  final List<Track> recentTracks;

  factory HomeData.fromJson(Map<String, dynamic> j) => HomeData(
        recentlyAdded: [for (final a in j['recently_added'] as List) Album.fromJson(a as Map<String, dynamic>)],
        recentlyPlayed: [
          for (final a in j['recently_played_albums'] as List) Album.fromJson(a as Map<String, dynamic>)
        ],
        recentTracks: [
          for (final t in j['recently_played_tracks'] as List) Track.fromJson(t as Map<String, dynamic>)
        ],
      );
}

/// One listening session of a track, reported to the server.
class PlayRecord {
  const PlayRecord({
    required this.trackId,
    required this.startedAt,
    required this.listenedMs,
    required this.skipped,
    this.contextKind,
    this.contextId,
  });

  final int trackId;
  final DateTime startedAt;
  final int listenedMs;
  final bool skipped;
  final String? contextKind;
  final int? contextId;

  Map<String, dynamic> toJson() => {
        'track_id': trackId,
        'started_at': startedAt.millisecondsSinceEpoch,
        'listened_ms': listenedMs,
        'skipped': skipped,
        if (contextKind != null) 'context_kind': contextKind,
        if (contextId != null) 'context_id': contextId,
      };

  factory PlayRecord.fromJson(Map<String, dynamic> j) => PlayRecord(
        trackId: j['track_id'] as int,
        startedAt: DateTime.fromMillisecondsSinceEpoch(j['started_at'] as int),
        listenedMs: j['listened_ms'] as int,
        skipped: j['skipped'] as bool,
        contextKind: j['context_kind'] as String?,
        contextId: j['context_id'] as int?,
      );
}
