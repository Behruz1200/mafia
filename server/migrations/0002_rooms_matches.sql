-- Stream 2 (rooms): one row per match, so a crash never leaves coins stuck
-- in escrow (the server settles every row with settled_at IS NULL when it
-- starts), and every action, so a disputed match can be replayed through
-- the engine from its seed.
--
-- Rooms and lobbies themselves are short-lived and kept in memory only.

CREATE TABLE IF NOT EXISTS rooms_matches (
  match_id    text PRIMARY KEY,
  room_id     text NOT NULL,
  stake       integer NOT NULL CHECK (stake >= 0),
  players     text[] NOT NULL,
  seed        bigint NOT NULL,
  started_at  timestamptz NOT NULL,
  ended_at    timestamptz,
  result      jsonb,          -- MatchResult; null until the match ends
  settled_at  timestamptz     -- coins paid out or returned
);

CREATE INDEX IF NOT EXISTS rooms_matches_unsettled
  ON rooms_matches (started_at) WHERE settled_at IS NULL;

CREATE TABLE IF NOT EXISTS rooms_match_actions (
  match_id  text NOT NULL REFERENCES rooms_matches (match_id),
  seq       integer NOT NULL,
  action    jsonb NOT NULL,   -- GameAction.toJson()
  at        timestamptz NOT NULL,
  PRIMARY KEY (match_id, seq)
);
