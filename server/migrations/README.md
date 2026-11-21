# Database migrations

Plain SQL files, applied in name order: `NNNN_<stream>_<what>.sql`, e.g.
`0002_accounts_users.sql`, `0003_wallet_ledger.sql`.

- Never edit a migration after it is merged; add a new one.
- Pick the next free number when you open your PR. If two PRs collide,
  the later one renumbers.
- Each stream creates only its own tables (accounts: users, sessions;
  wallet: wallets, ledger, purchases; rooms: rooms, matches).
- The ledger table is append-only: no UPDATE or DELETE grants for the app
  role.
