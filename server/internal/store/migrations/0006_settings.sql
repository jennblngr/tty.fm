-- Server-wide settings set from the app (Réglages), as text values. The
-- first one: "analysis_enabled", whether the recommender gets tracks to
-- analyse ("analyse audio [off] [on]"; on when absent).

CREATE TABLE settings (
  key    TEXT PRIMARY KEY,
  value  TEXT NOT NULL
);
