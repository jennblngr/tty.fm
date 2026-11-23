-- Discovery: artists similar to the liked ones, from ListenBrainz,
-- fetched by the recommender at most once a week per liked artist. They
-- need not be in the library: the home screen shows those it lacks.

CREATE TABLE similar_lookups (
  artist_id   INTEGER PRIMARY KEY REFERENCES artists(id) ON DELETE CASCADE,
  checked_at  INTEGER NOT NULL               -- unix seconds
);

CREATE TABLE similar_artists (
  artist_id   INTEGER NOT NULL REFERENCES artists(id) ON DELETE CASCADE, -- the liked artist
  mbid        TEXT    NOT NULL,              -- MusicBrainz id of the similar one
  name        TEXT    NOT NULL,
  comment     TEXT    NOT NULL DEFAULT '',   -- MusicBrainz disambiguation
  score       REAL    NOT NULL,              -- ListenBrainz score, higher is closer
  PRIMARY KEY (artist_id, mbid)
);
