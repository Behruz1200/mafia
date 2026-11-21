# Wallet (stream 4: coins)

Coins are bought or won, and never leave the app: no cash-out, no sending
coins to other players (decided 2026-11-21). Nothing here can move coins
anywhere except into a match pot and back out to that match's winners.

| File | What |
| --- | --- |
| `postgres_wallet.dart` | `PostgresWallet`, the real `WalletSettlement`: balances, escrow, settlement, purchases, refunds, rewards |
| `purchases.dart` | Checks App Store purchases with Apple before crediting; refund notifications |
| `app_store.dart` | App Store Server API client (signed with our In-App Purchase key) |
| `wallet_config.dart` | Coin packs and settings from environment variables |
| `wallet_module.dart` | HTTP routes (`ApiRoutes.wallet`, `ledger`, `coinPacks`, `purchases`, `appStoreNotifications`) |
| `../../migrations/0003_wallet_ledger.sql` | Tables |

## How coins move

- **Match start**: the rooms code calls `holdStakes`. All or nothing: if
  anyone is short, nobody is charged and `InsufficientCoins` lists who.
- **Match end**: `settle(MatchResult)`. Pot = all stakes. House keeps
  `HOUSE_CUT_PERCENT` (default 10) plus any coins that don't split evenly;
  the rest is split equally between the winners. Forfeited players and
  anyone not in the escrow are never paid. A cancelled match returns
  every stake.
- **Purchase**: the app buys through StoreKit and sends the transaction id.
  The server asks Apple for that transaction and credits the pack only if
  Apple confirms our bundle id, the same product, a consumable, not
  refunded. One store transaction credits one account once.
- **Refund**: Apple's server notification is only a hint; we ask Apple
  again, and if it says refunded we take the coins back (the balance can go
  below zero, and then the player can't stake until they top up).
- Every change is a row in the append-only `ledger` (a trigger blocks
  UPDATE and DELETE), in the same transaction as the balance change, and
  unique per user, kind and match/transaction id, so retries never pay twice.

Using it from the rooms code:

```dart
final settlement = WalletServices.instance?.wallet ?? InMemoryWalletSettlement();
```

Region and age checks (`RegionPolicy.allowsStakes`) are the rooms code's job
before it calls `holdStakes`.

## Settings

| Variable | |
| --- | --- |
| `DATABASE_URL` | Without it the wallet routes answer 501 |
| `HOUSE_CUT_PERCENT` | 0 to 100, default 10 |
| `COIN_PACKS` | Optional, `coins_100:100:0,coins_500:500:50` (id:coins:bonus). Default in `wallet_config.dart` |
| `APPLE_BUNDLE_ID` | The app's bundle id |
| `APPLE_ISSUER_ID`, `APPLE_KEY_ID` | App Store Connect → Users and Access → Integrations → In-App Purchase |
| `APPLE_PRIVATE_KEY_PATH` | Path on the server to that key's `.p8` file (readable only by the service user) |
| `APPLE_SANDBOX` | `allow` (default, needed for TestFlight and App Review) or `deny` |

## Before coins can be sold

1. In App Store Connect create one **consumable** in-app purchase per pack,
   with the product ids above (`coins_100`, `coins_500`, `coins_1200`,
   `coins_3000`) and prices per country.
2. Create an In-App Purchase key and put its values in the server's
   environment (never in git or chat).
3. Set the App Store Server Notifications V2 URL (production and sandbox)
   to `https://<api host>/v1/hooks/app-store`.
4. Apply `0003_wallet_ledger.sql`.

## Tests

The database tests need a PostgreSQL role that may create databases:

```sh
TEST_DATABASE_URL='postgres://mafia_test:test@localhost:5432/mafia_test?sslmode=disable' dart test
```

Without `TEST_DATABASE_URL` they are skipped.
