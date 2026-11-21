# Who owns which folder

Each stream works only in its own folders and talks to the others through
`packages/contracts`. A PR that touches another stream's folder needs that
stream's agreement.

| # | Stream | Owns |
| --- | --- | --- |
| 0 | Foundation | repo root, `packages/contracts`, `app/lib/core`, `app/lib/app.dart`, `server/lib/src`, `deploy/`, `.github/` |
| 1 | Game engine | `packages/mafia_engine` |
| 2 | Rooms and server | `server/lib/rooms`, `server/lib/realtime`, the app's real `RoomRepository` |
| 3 | Video | `app/lib/features/call`, `server/lib/call`, `deploy/*/livekit.yaml` |
| 4 | Coins | `app/lib/features/shop`, `server/lib/wallet`, the app's real `WalletRepository` |
| 5 | Accounts and safety | `app/lib/features/auth`, `app/lib/features/profile`, `server/lib/auth` |
| 6 | Game UI | `app/lib/features/lobby`, `app/lib/features/game` |

Shared files that everyone may add to, in small separate lines:

- `app/lib/l10n/app_*.arb`: add your strings to all three files (uz, ru, en).
  Prefix keys with your feature, e.g. `shopBuyButton`.
- `app/pubspec.yaml`, `server/pubspec.yaml`: add your own dependencies only.
- `server/migrations/`: new numbered files only (see its README).
- `app/lib/core/providers.dart`: swap your own provider from fake to real.

Real implementations of app repositories go inside the owning feature, e.g.
`app/lib/features/shop/data/http_wallet_repository.dart`.
