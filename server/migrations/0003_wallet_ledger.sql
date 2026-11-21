-- Stream 4 (coins): wallets, the append-only coin ledger, match escrow and
-- store purchases.
--
-- Coin model (decided 2026-11-21): coins are bought or won, never cashed out
-- and never sent between players. There is no table, column or ledger kind
-- for withdrawals or transfers, on purpose.
--
-- User ids are the accounts stream's ids, stored as text with no foreign key,
-- so the ledger never blocks an account deletion and keeps its history.

-- One row per player (plus the '_house' account). A cached balance that is
-- always changed in the same transaction as the ledger rows that explain it.
CREATE TABLE IF NOT EXISTS wallets (
  user_id     text PRIMARY KEY,
  available   bigint NOT NULL DEFAULT 0,  -- can go negative only after a refund clawback
  in_escrow   bigint NOT NULL DEFAULT 0 CHECK (in_escrow >= 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Every coin movement. Rows are never updated or deleted (trigger below).
CREATE TABLE IF NOT EXISTS ledger (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        text NOT NULL,
  kind           text NOT NULL CHECK (kind IN (
                   'purchase', 'refundClawback', 'reward', 'stakeHold',
                   'stakeReturn', 'matchPayout', 'houseFee', 'adjustment')),
  delta          bigint NOT NULL,
  balance_after  bigint NOT NULL,
  reference      text,
  note           text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CHECK (kind <> 'adjustment' OR note IS NOT NULL)
);

-- Makes every movement safe to retry: one row per user, kind and reference.
CREATE UNIQUE INDEX IF NOT EXISTS ledger_idempotency
  ON ledger (user_id, kind, reference) WHERE reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ledger_user_time ON ledger (user_id, created_at DESC);

CREATE OR REPLACE FUNCTION ledger_is_append_only() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'ledger is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ledger_no_update ON ledger;
CREATE TRIGGER ledger_no_update BEFORE UPDATE OR DELETE ON ledger
  FOR EACH ROW EXECUTE FUNCTION ledger_is_append_only();

-- Stakes locked for a match, one row per player.
CREATE TABLE IF NOT EXISTS match_escrow (
  match_id   text NOT NULL,
  user_id    text NOT NULL,
  stake      bigint NOT NULL CHECK (stake > 0),
  held_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, user_id)
);

-- A match is settled at most once.
CREATE TABLE IF NOT EXISTS match_settlements (
  match_id    text PRIMARY KEY,
  outcome     text NOT NULL CHECK (outcome IN ('paid', 'returned', 'empty')),
  pot         bigint NOT NULL,
  house_fee   bigint NOT NULL,
  settled_at  timestamptz NOT NULL DEFAULT now()
);

-- Store purchases we credited. A store transaction credits coins once.
CREATE TABLE IF NOT EXISTS purchases (
  store                    text NOT NULL CHECK (store IN ('appStore', 'playStore')),
  transaction_id           text NOT NULL,
  original_transaction_id  text,
  user_id                  text NOT NULL,
  product_id               text NOT NULL,
  coins                    bigint NOT NULL,
  environment              text,
  purchased_at             timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  refunded_at              timestamptz,
  PRIMARY KEY (store, transaction_id)
);
CREATE INDEX IF NOT EXISTS purchases_user ON purchases (user_id, created_at DESC);
