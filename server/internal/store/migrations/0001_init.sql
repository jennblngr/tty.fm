-- Library ------------------------------------------------------------------

CREATE TABLE artists (
  id          INTEGER PRIMARY KEY,
  name        TEXT    NOT NULL,
  sort_name   TEXT    NOT NULL,
  match_key   TEXT    NOT NULL UNIQUE,       -- normalised name (case, accents)
  mbid        TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX artists_sort ON artists(sort_name COLLATE NOCASE, id);

CREATE TABLE covers (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,  -- never reused: clients cache by id
  hash    TEXT    NOT NULL UNIQUE,           -- sha1 of the source image
  source  TEXT    NOT NULL                   -- 'embedded' | 'file'
);

CREATE TABLE albums (
  id               INTEGER PRIMARY KEY,
  title            TEXT    NOT NULL,
  sort_title       TEXT    NOT NULL,
  match_key        TEXT    NOT NULL,
  album_artist_id  INTEGER NOT NULL REFERENCES artists(id),
  year             INTEGER,
  genre            TEXT,
  cover_id         INTEGER REFERENCES covers(id),
  mbid             TEXT,
  track_count      INTEGER NOT NULL DEFAULT 0,
  duration_ms      INTEGER NOT NULL DEFAULT 0,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL,
  UNIQUE (album_artist_id, match_key)
);
CREATE INDEX albums_sort   ON albums(sort_title COLLATE NOCASE, id);
CREATE INDEX albums_added  ON albums(created_at DESC, id DESC);
CREATE INDEX albums_artist ON albums(album_artist_id, year);

CREATE TABLE tracks (
  id             INTEGER PRIMARY KEY,
  path           TEXT    NOT NULL UNIQUE,    -- relative to the music root
  file_size      INTEGER NOT NULL,
  file_mtime     INTEGER NOT NULL,           -- unix nanoseconds
  album_id       INTEGER NOT NULL REFERENCES albums(id),
  artist_id      INTEGER NOT NULL REFERENCES artists(id),
  title          TEXT    NOT NULL,
  track_no       INTEGER,
  disc_no        INTEGER,
  year           INTEGER,
  genre          TEXT,
  duration_ms    INTEGER NOT NULL,
  format         TEXT    NOT NULL,
  codec          TEXT,
  bitrate        INTEGER,                    -- kbit/s
  sample_rate    INTEGER,
  bit_depth      INTEGER,
  channels       INTEGER,
  rg_track_gain  REAL,
  rg_track_peak  REAL,
  rg_album_gain  REAL,
  rg_album_peak  REAL,
  cover_id       INTEGER REFERENCES covers(id),
  mbid           TEXT,
  missing_since  INTEGER,                    -- soft delete
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX tracks_album   ON tracks(album_id, disc_no, track_no);
CREATE INDEX tracks_artist  ON tracks(artist_id);
CREATE INDEX tracks_added   ON tracks(created_at DESC, id DESC);
CREATE INDEX tracks_title   ON tracks(title COLLATE NOCASE, id);
CREATE INDEX tracks_missing ON tracks(missing_since) WHERE missing_since IS NOT NULL;

-- One FTS index for artists, albums and tracks; maintained by the store.
CREATE VIRTUAL TABLE search_fts USING fts5(
  kind UNINDEXED,
  ref_id UNINDEXED,
  title,
  artist,
  album,
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '1 2 3'
);

-- Playlists ----------------------------------------------------------------

CREATE TABLE playlist_folders (
  id          INTEGER PRIMARY KEY,
  name        TEXT    NOT NULL,
  parent_id   INTEGER REFERENCES playlist_folders(id) ON DELETE CASCADE,
  position    INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX folders_parent ON playlist_folders(parent_id, position);

CREATE TABLE playlists (
  id          INTEGER PRIMARY KEY,
  name        TEXT    NOT NULL,
  folder_id   INTEGER REFERENCES playlist_folders(id) ON DELETE CASCADE,
  position    INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX playlists_folder ON playlists(folder_id, position);

CREATE TABLE playlist_tracks (
  id           INTEGER PRIMARY KEY,
  playlist_id  INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  track_id     INTEGER NOT NULL REFERENCES tracks(id)    ON DELETE CASCADE,
  position     INTEGER NOT NULL,
  added_at     INTEGER NOT NULL
);
CREATE INDEX playlist_tracks_order ON playlist_tracks(playlist_id, position);
CREATE INDEX playlist_tracks_track ON playlist_tracks(track_id);

-- Users, devices, history --------------------------------------------------

CREATE TABLE users (
  id             INTEGER PRIMARY KEY,
  username       TEXT    NOT NULL UNIQUE,
  password_hash  TEXT    NOT NULL,
  created_at     INTEGER NOT NULL
);

CREATE TABLE devices (
  id            INTEGER PRIMARY KEY,
  user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name          TEXT    NOT NULL,
  platform      TEXT    NOT NULL,
  token_hash    TEXT    NOT NULL UNIQUE,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
);

CREATE TABLE plays (
  id            INTEGER PRIMARY KEY,
  track_id      INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  device_id     INTEGER REFERENCES devices(id) ON DELETE SET NULL,
  started_at    INTEGER NOT NULL,            -- unix milliseconds
  listened_ms   INTEGER NOT NULL,
  skipped       INTEGER NOT NULL,
  context_kind  TEXT,
  context_id    INTEGER
);
CREATE INDEX plays_track ON plays(track_id, started_at);
CREATE INDEX plays_time  ON plays(started_at DESC);

CREATE TABLE favorite_tracks (
  track_id    INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL
);
CREATE TABLE favorite_albums (
  album_id    INTEGER PRIMARY KEY REFERENCES albums(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL
);
CREATE TABLE favorite_artists (
  artist_id   INTEGER PRIMARY KEY REFERENCES artists(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL
);

-- Misc key/value state (last scan time...) ---------------------------------

CREATE TABLE meta (
  key    TEXT PRIMARY KEY,
  value  TEXT NOT NULL
);
