-- New releases (phase 3): the recommender looks each album artist up on
-- MusicBrainz (at most once a week) and sends its release groups; the
-- server compares them with the library. artist_lookups.mbid is null when
-- MusicBrainz knows no such artist.

CREATE TABLE artist_lookups (
  artist_id   INTEGER PRIMARY KEY REFERENCES artists(id) ON DELETE CASCADE,
  mbid        TEXT,
  checked_at  INTEGER NOT NULL               -- unix seconds
);

CREATE TABLE artist_releases (
  artist_id   INTEGER NOT NULL REFERENCES artists(id) ON DELETE CASCADE,
  mbid        TEXT    NOT NULL,              -- MusicBrainz release group
  title       TEXT    NOT NULL,
  kind        TEXT    NOT NULL,              -- album, ep, single
  released    TEXT    NOT NULL,              -- YYYY-MM-DD, YYYY-MM or YYYY
  PRIMARY KEY (artist_id, mbid)
);
CREATE INDEX artist_releases_released ON artist_releases(released);
