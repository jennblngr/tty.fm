-- Notifications (bell of the home header) ---------------------------------

CREATE TABLE notifications (
  id          INTEGER PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind        TEXT    NOT NULL,              -- "added"...
  since       INTEGER NOT NULL,              -- first event covered, unix seconds
  created_at  INTEGER NOT NULL,              -- last event covered, unix seconds
  read_at     INTEGER,
  data        TEXT    NOT NULL               -- JSON, depends on kind
);
CREATE INDEX notifications_user ON notifications(user_id, created_at DESC);

-- Kinds turned off in the settings (on by default).
CREATE TABLE notification_settings (
  user_id  INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind     TEXT    NOT NULL,
  enabled  INTEGER NOT NULL,
  PRIMARY KEY (user_id, kind)
);
