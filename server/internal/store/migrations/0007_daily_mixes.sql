-- Mixes of the day: computed each night from the listening
-- history (groups of similar tracks listened lately, completed with
-- neighbours seldom or never played), kept as they are for the whole day.
-- track_ids is a JSON array, in play order. Old days are pruned.

CREATE TABLE daily_mixes (
  day          TEXT    NOT NULL,             -- YYYY-MM-DD, server time zone
  position     INTEGER NOT NULL,             -- 1, 2… (mix_01, mix_02…)
  description  TEXT    NOT NULL,             -- "dance-pop · festif"
  track_ids    TEXT    NOT NULL,
  created_at   INTEGER NOT NULL,             -- unix seconds
  PRIMARY KEY (day, position)
);
