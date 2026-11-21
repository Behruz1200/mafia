-- Accounts (stream 5): players, SMS sign-in codes and refresh sessions.
-- Personal data lives only here, on our server in Uzbekistan.

CREATE TABLE IF NOT EXISTS users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164    text UNIQUE,                 -- null for Apple-only accounts
  apple_sub     text UNIQUE,                 -- Sign in with Apple user id
  display_name  text NOT NULL,
  avatar_url    text,
  country_code  char(2),                     -- from the phone number
  locale        text NOT NULL DEFAULT 'uz',
  birth_date    date,                        -- age gate; never sent to apps
  created_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz                  -- account deleted: data wiped
);

-- One pending code per phone. code_hash is an HMAC, never the code itself.
CREATE TABLE IF NOT EXISTS phone_codes (
  phone_e164       text PRIMARY KEY,
  code_hash        text NOT NULL,
  expires_at       timestamptz NOT NULL,
  attempts         int NOT NULL DEFAULT 0,
  last_sent_at     timestamptz NOT NULL,
  window_start     timestamptz NOT NULL,
  sends_in_window  int NOT NULL DEFAULT 1
);

-- Refresh tokens (hashed). Rotated on every refresh; family_id ties the
-- chain together so a reused old token revokes the whole chain.
CREATE TABLE IF NOT EXISTS sessions (
  id          uuid PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users (id),
  family_id   uuid NOT NULL,
  token_hash  text NOT NULL UNIQUE,
  expires_at  timestamptz NOT NULL,
  revoked_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions (user_id);
CREATE INDEX IF NOT EXISTS sessions_family_idx ON sessions (family_id);

INSERT INTO schema_migrations (name) VALUES ('0002_accounts_users')
  ON CONFLICT DO NOTHING;
