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
    this.createdAt,
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

  /// When the album entered the library.
  final DateTime? createdAt;

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
    createdAt: j['created_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['created_at'] as int) * 1000),
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
    this.genre,
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
  final String? genre;
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
    genre: j['genre'] as String?,
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
    'genre': genre,
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
    playlists: [for (final p in j['playlists'] as List? ?? const []) Playlist.fromJson(p as Map<String, dynamic>)],
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
  const HomeData({this.recentlyAdded = const [], this.recentlyPlayed = const []});

  final List<Album> recentlyAdded;
  final List<Album> recentlyPlayed;

  factory HomeData.fromJson(Map<String, dynamic> j) => HomeData(
    recentlyAdded: [for (final a in j['recently_added'] as List) Album.fromJson(a as Map<String, dynamic>)],
    recentlyPlayed: [for (final a in j['recently_played_albums'] as List) Album.fromJson(a as Map<String, dynamic>)],
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

/// Search filters; null fields mean "any".
class SearchFilter {
  const SearchFilter({this.genre, this.yearMin, this.yearMax, this.format});

  final String? genre;
  final int? yearMin;
  final int? yearMax;
  final String? format;

  bool get isActive => genre != null || yearMin != null || yearMax != null || format != null;

  SearchFilter copyWith({
    String? Function()? genre,
    int? Function()? yearMin,
    int? Function()? yearMax,
    String? Function()? format,
  }) => SearchFilter(
    genre: genre != null ? genre() : this.genre,
    yearMin: yearMin != null ? yearMin() : this.yearMin,
    yearMax: yearMax != null ? yearMax() : this.yearMax,
    format: format != null ? format() : this.format,
  );

  Map<String, dynamic> toQuery() => {'genre': ?genre, 'year_min': ?yearMin, 'year_max': ?yearMax, 'format': ?format};
}

class Facet {
  const Facet(this.name, this.count);
  final String name;
  final int count;
}

/// Values available for each search filter.
class SearchFacets {
  const SearchFacets({this.genres = const [], this.formats = const [], this.yearMin, this.yearMax});

  final List<Facet> genres;
  final List<Facet> formats;
  final int? yearMin;
  final int? yearMax;

  static List<Facet> _facets(dynamic j) => [
    for (final f in j as List? ?? const []) Facet((f as Map)['name'] as String, f['count'] as int),
  ];

  factory SearchFacets.fromJson(Map<String, dynamic> j) => SearchFacets(
    genres: _facets(j['genres']),
    formats: _facets(j['formats']),
    yearMin: j['year_min'] as int?,
    yearMax: j['year_max'] as int?,
  );
}

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({required this.synced, required this.lines});
  final bool synced;
  final List<LyricLine> lines;

  factory Lyrics.fromJson(Map<String, dynamic> j) => Lyrics(
    synced: j['synced'] as bool? ?? false,
    lines: [
      for (final l in j['lines'] as List? ?? const [])
        LyricLine(Duration(milliseconds: (l as Map)['ms'] as int? ?? 0), l['text'] as String? ?? ''),
    ],
  );

  /// Index of the line being sung at [pos] (-1 before the first one).
  int lineAt(Duration pos) {
    var i = -1;
    for (var k = 0; k < lines.length && lines[k].time <= pos; k++) {
      i = k;
    }
    return i;
  }
}

class NamedTotal {
  const NamedTotal(this.id, this.name, this.ms);
  final int? id;
  final String name;
  final int ms;

  factory NamedTotal.fromJson(Map<String, dynamic> j) =>
      NamedTotal(j['id'] as int?, j['name'] as String? ?? '', j['ms'] as int? ?? 0);
}

/// Listening history summary over a period (days 0 = all time).
class ListeningStats {
  const ListeningStats({
    required this.days,
    required this.totalMs,
    this.prevTotalMs,
    required this.plays,
    required this.distinctTracks,
    required this.weekdayAvgMin,
    required this.hourMs,
    this.favoriteHour,
    required this.topArtists,
    required this.topGenres,
    required this.topTracks,
    this.discovery,
  });

  final int days;
  final int totalMs;
  final int? prevTotalMs;
  final int plays;
  final int distinctTracks;
  final List<int> weekdayAvgMin; // Monday first
  final List<int> hourMs;
  final int? favoriteHour;
  final List<NamedTotal> topArtists;
  final List<NamedTotal> topGenres;
  final List<(Track, int)> topTracks;
  final NamedTotal? discovery;

  factory ListeningStats.fromJson(Map<String, dynamic> j) => ListeningStats(
    days: j['days'] as int? ?? 0,
    totalMs: j['total_ms'] as int? ?? 0,
    prevTotalMs: j['prev_total_ms'] as int?,
    plays: j['plays'] as int? ?? 0,
    distinctTracks: j['distinct_tracks'] as int? ?? 0,
    weekdayAvgMin: (j['weekday_avg_min'] as List? ?? List.filled(7, 0)).cast<int>(),
    hourMs: (j['hour_ms'] as List? ?? List.filled(24, 0)).cast<int>(),
    favoriteHour: j['favorite_hour'] as int?,
    topArtists: [for (final a in j['top_artists'] as List? ?? const []) NamedTotal.fromJson(a as Map<String, dynamic>)],
    topGenres: [for (final a in j['top_genres'] as List? ?? const []) NamedTotal.fromJson(a as Map<String, dynamic>)],
    topTracks: [
      for (final t in j['top_tracks'] as List? ?? const [])
        (Track.fromJson((t as Map)['track'] as Map<String, dynamic>), t['count'] as int),
    ],
    discovery: j['discovery'] == null ? null : NamedTotal.fromJson(j['discovery'] as Map<String, dynamic>),
  );
}
