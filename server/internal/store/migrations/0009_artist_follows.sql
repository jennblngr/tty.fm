-- Followed artists (biblio "● artistes suivis"): the most listened ones
-- are followed on their own; this table holds the user's choices on top:
-- followed = 1 follows an artist by hand, 0 stops following one (an
-- automatic one included).

CREATE TABLE artist_follows (
  artist_id   INTEGER PRIMARY KEY REFERENCES artists(id) ON DELETE CASCADE,
  followed    INTEGER NOT NULL,
  created_at  INTEGER NOT NULL
);
