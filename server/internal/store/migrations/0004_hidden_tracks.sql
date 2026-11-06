-- Tracks the user does not want to hear: still listed (greyed out) in their
-- album and playlists, but left out when the client builds a queue.

CREATE TABLE hidden_tracks (
  track_id    INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL
);
