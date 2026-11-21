-- Foundation: bookkeeping for migrations. Streams add their own tables in
-- later files (see README.md).
CREATE TABLE IF NOT EXISTS schema_migrations (
  name        text PRIMARY KEY,
  applied_at  timestamptz NOT NULL DEFAULT now()
);

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()
