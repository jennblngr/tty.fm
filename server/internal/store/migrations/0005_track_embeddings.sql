-- Similarity between tracks (phase 3): the mean Discogs EffNet embedding of
-- each analysed track, sent by the recommender with its analysis, in a
-- sqlite-vec table searched by cosine distance. The vec0 module is linked
-- into the server (store.init); vec0 tables know no foreign keys, so the
-- trigger drops a track's vector with its analysis (reset, or the track
-- deleted from the library). SaveAnalysis replaces it explicitly.

CREATE VIRTUAL TABLE track_embeddings USING vec0(
  track_id   INTEGER PRIMARY KEY,
  embedding  float[1280] distance_metric=cosine
);

CREATE TRIGGER track_analysis_embedding_delete AFTER DELETE ON track_analysis
BEGIN
  DELETE FROM track_embeddings WHERE track_id = OLD.track_id;
END;
