-- Audio analysis, computed by the recommender service from the
-- files and reported through the API. One row per analysed track; a row
-- whose file_mtime differs from the track's is stale and queued again.

CREATE TABLE track_analysis (
  track_id        INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
  file_mtime      INTEGER NOT NULL,          -- tracks.file_mtime at analysis time
  analyzer        TEXT    NOT NULL,          -- name/version of the analyser
  analyzed_at     INTEGER NOT NULL,          -- unix seconds
  error           TEXT,                      -- set when the file could not be analysed
  bpm             REAL,
  key             TEXT,                      -- tonic, sharps: C, C#, D... B
  scale           TEXT,                      -- major, minor
  camelot         TEXT,                      -- 1A..12B, derived from key + scale
  key_strength    REAL,                      -- 0..1
  loudness_lufs   REAL,                      -- integrated loudness (EBU R128)
  loudness_range  REAL,                      -- LU
  energy          REAL,                      -- 0..1
  danceability    REAL,                      -- 0..1
  acousticness    REAL,                      -- 0..1 (needs the ML models)
  mood            TEXT,                      -- idem
  genres          TEXT                       -- JSON [{"name","share"}], idem
);
CREATE INDEX track_analysis_bpm ON track_analysis(bpm) WHERE bpm IS NOT NULL;
