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
    this.bpm,
    this.camelot,
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

  /// From the audio analysis, once the track is analysed.
  final double? bpm;
  final String? camelot;

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
    bpm: (j['bpm'] as num?)?.toDouble(),
    camelot: j['camelot'] as String?,
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
    'bpm': ?bpm,
    'camelot': ?camelot,
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

/// A "recently played" shortcut: what plays were started from. Exactly one
/// of [album], [artist] and [playlist] is set.
class RecentItem {
  const RecentItem.album(Album this.album) : artist = null, playlist = null;
  const RecentItem.artist(Artist this.artist) : album = null, playlist = null;
  const RecentItem.playlist(Playlist this.playlist) : album = null, artist = null;

  final Album? album;
  final Artist? artist;
  final Playlist? playlist;

  /// Null for a kind this version does not know.
  static RecentItem? fromJson(Map<String, dynamic> j) => switch (j['kind']) {
    'album' => RecentItem.album(Album.fromJson(j['album'] as Map<String, dynamic>)),
    'artist' => RecentItem.artist(Artist.fromJson(j['artist'] as Map<String, dynamic>)),
    'playlist' => RecentItem.playlist(Playlist.fromJson(j['playlist'] as Map<String, dynamic>)),
    _ => null,
  };
}

/// A "recently added" row: the [tracks] of [album] added in one go.
class RecentAddition {
  const RecentAddition({required this.album, required this.tracks, this.addedAt});

  final Album album;
  final int tracks;
  final DateTime? addedAt;

  /// The whole album came in, not a few tracks of it.
  bool get wholeAlbum => tracks >= album.trackCount;

  factory RecentAddition.fromJson(Map<String, dynamic> j) => RecentAddition(
    album: Album.fromJson(j['album'] as Map<String, dynamic>),
    tracks: j['tracks'] as int,
    addedAt: DateTime.fromMillisecondsSinceEpoch((j['added_at'] as int) * 1000),
  );

  /// Servers before batches send whole albums.
  factory RecentAddition.ofAlbum(Album a) => RecentAddition(album: a, tracks: a.trackCount, addedAt: a.createdAt);
}

class HomeData {
  const HomeData({
    this.recentlyAdded = const [],
    this.recentlyPlayed = const [],
    this.moments = const Moments(),
    this.mixes = const [],
    this.newReleases = const [],
    this.discoveries = const [],
    this.artistRadios = const [],
  });

  final List<RecentAddition> recentlyAdded;
  final List<RecentItem> recentlyPlayed;
  final Moments moments;

  /// "tes mix du jour", without their tracks (GET /mixes/{n}).
  final List<DailyMix> mixes;

  /// Recent and upcoming releases of the library's artists (MusicBrainz).
  final List<NewRelease> newReleases;

  /// Artists similar to the liked ones that the library lacks (ListenBrainz).
  final List<Discovery> discoveries;

  /// "◉ radios d'artistes": the liked artists, then the most listened.
  final List<ArtistRadio> artistRadios;

  factory HomeData.fromJson(Map<String, dynamic> j) => HomeData(
    recentlyAdded: j['recent_additions'] is List
        ? [for (final a in j['recent_additions'] as List) RecentAddition.fromJson(a as Map<String, dynamic>)]
        // Servers before batches, and cached responses from them.
        : [
            for (final a in j['recently_added'] as List? ?? const [])
              RecentAddition.ofAlbum(Album.fromJson(a as Map<String, dynamic>)),
          ],
    recentlyPlayed: j['recently_played'] is List
        ? [for (final i in j['recently_played'] as List) ?RecentItem.fromJson(i as Map<String, dynamic>)]
        // Servers before the mixed list, and cached responses from them.
        : [
            for (final a in j['recently_played_albums'] as List? ?? const [])
              RecentItem.album(Album.fromJson(a as Map<String, dynamic>)),
          ],
    moments: j['moments'] is Map ? Moments.fromJson(j['moments'] as Map<String, dynamic>) : const Moments(),
    mixes: [for (final m in j['mixes'] as List? ?? const []) DailyMix.fromJson(m as Map<String, dynamic>)],
    newReleases: [
      for (final r in j['new_releases'] as List? ?? const []) NewRelease.fromJson(r as Map<String, dynamic>),
    ],
    discoveries: [for (final d in j['discoveries'] as List? ?? const []) Discovery.fromJson(d as Map<String, dynamic>)],
    artistRadios: [
      for (final a in j['artist_radios'] as List? ?? const []) ArtistRadio.fromJson(a as Map<String, dynamic>),
    ],
  );
}

/// An artist whose radio the home screen offers (GET /home).
class ArtistRadio {
  const ArtistRadio({required this.id, required this.name, this.coverId, this.liked = false});

  final int id;
  final String name;
  final int? coverId;
  final bool liked;

  factory ArtistRadio.fromJson(Map<String, dynamic> j) => ArtistRadio(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    coverId: j['cover_id'] as int?,
    liked: j['liked'] as bool? ?? false,
  );

  RadioSeed get seed => RadioSeed('artist', id, name);
}

/// A recent or upcoming release of an artist of the library, from
/// MusicBrainz; [albumId] is set when the library has it.
class NewRelease {
  const NewRelease({
    required this.artistId,
    required this.artist,
    required this.title,
    required this.kind,
    required this.released,
    this.upcoming = false,
    this.albumId,
    this.mbid = '',
  });

  final int artistId;
  final String artist;
  final String title;
  final String kind; // album, ep, single
  final String released; // YYYY-MM-DD or YYYY-MM
  final bool upcoming;
  final int? albumId;
  final String mbid; // MusicBrainz release group

  factory NewRelease.fromJson(Map<String, dynamic> j) => NewRelease(
    artistId: j['artist_id'] as int,
    artist: j['artist'] as String? ?? '',
    title: j['title'] as String? ?? '',
    kind: j['kind'] as String? ?? 'album',
    released: j['released'] as String? ?? '',
    upcoming: j['upcoming'] as bool? ?? false,
    albumId: j['album_id'] as int?,
    mbid: j['mbid'] as String? ?? '',
  );

  /// The release date, a month-only date as its first day.
  DateTime? get date {
    final p = released.split('-').map(int.tryParse).toList();
    if (p.length < 2 || p.contains(null)) return null;
    return DateTime(p[0]!, p[1]!, p.length > 2 ? p[2]! : 1);
  }
}

/// A mix of the day: listened tracks of one sound and seldom played
/// neighbours, computed each night by the server.
class DailyMix {
  const DailyMix({
    required this.position,
    required this.name,
    this.description = '',
    this.artists = const [],
    this.coverIds = const [],
    this.trackCount = 0,
    this.durationMs = 0,
  });

  final int position; // 1, 2…
  final String name; // mix_01
  final String description; // "dance-pop · festif"
  final List<String> artists;
  final List<int> coverIds;
  final int trackCount;
  final int durationMs;

  factory DailyMix.fromJson(Map<String, dynamic> j) => DailyMix(
    position: j['position'] as int,
    name: j['name'] as String? ?? 'mix_${(j['position'] as int).toString().padLeft(2, '0')}',
    description: j['description'] as String? ?? '',
    artists: (j['artists'] as List? ?? const []).cast<String>(),
    coverIds: (j['cover_ids'] as List? ?? const []).cast<int>(),
    trackCount: j['track_count'] as int? ?? 0,
    durationMs: j['duration_ms'] as int? ?? 0,
  );

  /// "dance-pop · calme · sia, tove lo…" under the tile.
  String get caption {
    final who = artists.map((a) => a.toLowerCase()).join(', ');
    return [if (description.isNotEmpty) description, if (who.isNotEmpty) '$who…'].join(' · ');
  }
}

/// Facts from the listening history for the message of the day.
class Moments {
  const Moments({this.streakDays = 0, this.streakRecord = 0, this.anniversary, this.eveningGenre});

  final int streakDays; // consecutive days with a play, up to today or yesterday
  final int streakRecord; // longest streak before the current one
  final ({int artistId, String artist, int years})? anniversary; // top 10 artist first heard on this day
  final String? eveningGenre; // most played after 18h over 30 days

  factory Moments.fromJson(Map<String, dynamic> j) {
    final s = j['streak'] as Map<String, dynamic>? ?? const {};
    final a = j['anniversary'] as Map<String, dynamic>?;
    return Moments(
      streakDays: s['days'] as int? ?? 0,
      streakRecord: s['record'] as int? ?? 0,
      anniversary: a == null
          ? null
          : (
              artistId: a['artist_id'] as int? ?? 0,
              artist: a['artist'] as String? ?? '',
              years: a['years'] as int? ?? 1,
            ),
      eveningGenre: j['evening_genre'] as String?,
    );
  }
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
  const SearchFilter({this.genre, this.yearMin, this.yearMax, this.format, this.bpmMin, this.bpmMax, this.camelot});

  final String? genre;
  final int? yearMin;
  final int? yearMax;
  final String? format;

  /// Tempo range (both ends included) and Camelot key ("8A"); they keep
  /// analysed tracks only.
  final double? bpmMin;
  final double? bpmMax;
  final String? camelot;

  bool get isActive =>
      genre != null ||
      yearMin != null ||
      yearMax != null ||
      format != null ||
      bpmMin != null ||
      bpmMax != null ||
      camelot != null;

  SearchFilter copyWith({
    String? Function()? genre,
    int? Function()? yearMin,
    int? Function()? yearMax,
    String? Function()? format,
    double? Function()? bpmMin,
    double? Function()? bpmMax,
    String? Function()? camelot,
  }) => SearchFilter(
    genre: genre != null ? genre() : this.genre,
    yearMin: yearMin != null ? yearMin() : this.yearMin,
    yearMax: yearMax != null ? yearMax() : this.yearMax,
    format: format != null ? format() : this.format,
    bpmMin: bpmMin != null ? bpmMin() : this.bpmMin,
    bpmMax: bpmMax != null ? bpmMax() : this.bpmMax,
    camelot: camelot != null ? camelot() : this.camelot,
  );

  /// This filter with what [other] sets on top (a prefix typed in the
  /// search field wins over the chip of the same kind).
  SearchFilter merge(SearchFilter other) => SearchFilter(
    genre: other.genre ?? genre,
    yearMin: other.yearMin ?? yearMin,
    yearMax: other.yearMax ?? yearMax,
    format: other.format ?? format,
    bpmMin: other.bpmMin != null || other.bpmMax != null ? other.bpmMin : bpmMin,
    bpmMax: other.bpmMin != null || other.bpmMax != null ? other.bpmMax : bpmMax,
    camelot: other.camelot ?? camelot,
  );

  Map<String, dynamic> toQuery() => {
    'genre': ?genre,
    'year_min': ?yearMin,
    'year_max': ?yearMax,
    'format': ?format,
    'bpm_min': ?bpmMin,
    'bpm_max': ?bpmMax,
    'camelot': ?camelot,
  };
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
    this.tempo = const Tempo(),
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
  final Tempo tempo;

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
    tempo: j['tempo'] is Map<String, dynamic> ? Tempo.fromJson(j['tempo'] as Map<String, dynamic>) : const Tempo(),
  );
}

/// Audio analysis of a track, computed by the recommender service
/// from the file. Values it could not compute are null; genre shares, mood
/// and acousticness need its ML models.
class TrackAnalysis {
  const TrackAnalysis({
    this.error,
    this.bpm,
    this.key,
    this.scale,
    this.camelot,
    this.loudnessLufs,
    this.energy,
    this.danceability,
    this.acousticness,
    this.mood,
    this.genres = const [],
    this.stale = false,
    this.keyStrength,
    this.loudnessRange,
    this.analyzer,
    this.analyzedAt,
  });

  final String? error;
  final double? bpm;
  final String? key; // C, C#... B
  final String? scale; // major, minor
  final String? camelot; // 8A
  final double? loudnessLufs;
  final double? energy; // 0..1
  final double? danceability; // 0..1
  final double? acousticness; // 0..1
  final String? mood;
  final List<(String, double)> genres; // name, share 0..1
  final bool stale; // the file changed since: queued again

  /// Shown under "[détails]": how sure the key is (0..1), the loudness
  /// range in LU, and which analyser ran when.
  final double? keyStrength;
  final double? loudnessRange;
  final String? analyzer;
  final DateTime? analyzedAt;

  static double? _d(Object? v) => (v as num?)?.toDouble();

  factory TrackAnalysis.fromJson(Map<String, dynamic> j) => TrackAnalysis(
    error: j['error'] as String?,
    bpm: _d(j['bpm']),
    key: j['key'] as String?,
    scale: j['scale'] as String?,
    camelot: j['camelot'] as String?,
    loudnessLufs: _d(j['loudness_lufs']),
    energy: _d(j['energy']),
    danceability: _d(j['danceability']),
    acousticness: _d(j['acousticness']),
    mood: j['mood'] as String?,
    genres: [
      for (final g in j['genres'] as List? ?? const [])
        ((g as Map)['name'] as String? ?? '', (g['share'] as num?)?.toDouble() ?? 0),
    ],
    stale: j['stale'] as bool? ?? false,
    keyStrength: _d(j['key_strength']),
    loudnessRange: _d(j['loudness_range']),
    analyzer: j['analyzer'] as String?,
    analyzedAt: j['analyzed_at'] is int ? DateTime.fromMillisecondsSinceEpoch((j['analyzed_at'] as int) * 1000) : null,
  );

  /// "la mineur".
  String? get keyName {
    final tonic = _frenchTonics[key];
    if (tonic == null) return null;
    return switch (scale) {
      'major' => '$tonic majeur',
      'minor' => '$tonic mineur',
      _ => tonic,
    };
  }

  static const _frenchTonics = {
    'C': 'do',
    'C#': 'do♯',
    'D': 'ré',
    'D#': 'mi♭',
    'E': 'mi',
    'F': 'fa',
    'F#': 'fa♯',
    'G': 'sol',
    'G#': 'la♭',
    'A': 'la',
    'A#': 'si♭',
    'B': 'si',
  };
}

/// GET /tracks/{id}/analysis: the analysis and the tracks that chain well
/// after it (compatible key, tempo within 6 %).
class AnalysisResult {
  const AnalysisResult(this.analysis, this.compatible);
  final TrackAnalysis analysis;
  final List<Track> compatible;

  factory AnalysisResult.fromJson(Map<String, dynamic> j) => AnalysisResult(
    TrackAnalysis.fromJson(j['analysis'] as Map<String, dynamic>),
    [for (final t in j['compatible'] as List? ?? const []) Track.fromJson(t as Map<String, dynamic>)],
  );
}

/// What a radio started from: a track or an artist (GET /radio). [name] is
/// the track title or the artist name, for "// ensuite : radio « … »".
class RadioSeed {
  const RadioSeed(this.kind, this.id, this.name);
  RadioSeed.track(Track t) : this('track', t.id, t.title);

  final String kind; // "track" or "artist"
  final int id;
  final String name;

  factory RadioSeed.fromJson(Map<String, dynamic> j) =>
      RadioSeed(j['kind'] as String, j['id'] as int, j['name'] as String? ?? '');
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'name': name};

  @override
  bool operator ==(Object other) => other is RadioSeed && other.kind == kind && other.id == id;
  @override
  int get hashCode => Object.hash(kind, id);
}

/// How fast the listening was (stats "∿ tempo"), over the analysed tracks
/// only, weighted by listening time.
class Tempo {
  const Tempo({
    this.analyzedMs = 0,
    this.bandMs = const [0, 0, 0, 0, 0],
    this.avgBpm,
    this.prevAvgBpm,
    this.morningBpm,
    this.eveningBpm,
    this.fastest,
    this.slowest,
  });

  /// Labels of [bandMs], as the server cuts them.
  static const bands = ['< 80', '80–100', '100–120', '120–140', '> 140'];

  final int analyzedMs;
  final List<int> bandMs;
  final double? avgBpm;
  final double? prevAvgBpm;
  final double? morningBpm; // 5 h – 12 h
  final double? eveningBpm; // 18 h – 24 h
  final Track? fastest;
  final Track? slowest;

  static double? _d(Object? v) => (v as num?)?.toDouble();
  static Track? _t(Object? v) => v is Map<String, dynamic> ? Track.fromJson(v) : null;

  factory Tempo.fromJson(Map<String, dynamic> j) => Tempo(
    analyzedMs: j['analyzed_ms'] as int? ?? 0,
    bandMs: (j['band_ms'] as List? ?? const [0, 0, 0, 0, 0]).cast<int>(),
    avgBpm: _d(j['avg_bpm']),
    prevAvgBpm: _d(j['prev_avg_bpm']),
    morningBpm: _d(j['morning_bpm']),
    eveningBpm: _d(j['evening_bpm']),
    fastest: _t(j['fastest']),
    slowest: _t(j['slowest']),
  );
}

/// State of the audio analysis of the library (GET /analysis).
class AnalysisStatus {
  const AnalysisStatus({this.enabled = true, this.total = 0, this.analyzed = 0, this.failed = 0, this.pending = 0});

  /// "analyse audio": off, the recommender gets nothing to analyse.
  final bool enabled;
  final int total;
  final int analyzed;
  final int failed;
  final int pending;

  factory AnalysisStatus.fromJson(Map<String, dynamic> j) => AnalysisStatus(
    enabled: j['enabled'] as bool? ?? true,
    total: j['total'] as int? ?? 0,
    analyzed: j['analyzed'] as int? ?? 0,
    failed: j['failed'] as int? ?? 0,
    pending: j['pending'] as int? ?? 0,
  );
}

/// An artist of "● artistes suivis" (a liked artist), with its fresh
/// release (the "•") if any.
class FollowedArtist {
  const FollowedArtist({required this.id, required this.name, this.coverId, this.newRelease});

  final int id;
  final String name;
  final int? coverId;
  final NewRelease? newRelease;

  factory FollowedArtist.fromJson(Map<String, dynamic> j) => FollowedArtist(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    coverId: j['cover_id'] as int?,
    newRelease: j['new_release'] is Map<String, dynamic>
        ? NewRelease.fromJson(j['new_release'] as Map<String, dynamic>)
        : null,
  );
}

/// An artist to discover: similar to liked ones ([because], closest first),
/// not in the library, so it cannot be played here.
class Discovery {
  const Discovery({required this.mbid, required this.name, this.comment = '', this.because = const []});

  final String mbid;
  final String name;
  final String comment; // MusicBrainz disambiguation: "Barbadian R&B/pop singer"
  final List<String> because;

  factory Discovery.fromJson(Map<String, dynamic> j) => Discovery(
    mbid: j['mbid'] as String? ?? '',
    name: j['name'] as String? ?? '',
    comment: j['comment'] as String? ?? '',
    because: (j['because'] as List? ?? const []).cast<String>(),
  );

  /// "proche de sia, adele · barbadian r&b/pop singer".
  String get caption {
    final near = because.take(2).map((b) => b.toLowerCase()).join(', ');
    return [if (near.isNotEmpty) 'proche de $near', if (comment.isNotEmpty) comment.toLowerCase()].join(' · ');
  }
}
