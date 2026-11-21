# Developing

Needs Flutter 3.50 (stable), which includes Dart 3.14. Docker for the server.

```sh
flutter pub get                 # once, at the repo root (pub workspace)

# App, with fake services (no server needed)
cd app && flutter run

# App against a real server
flutter run --dart-define=USE_FAKES=false --dart-define=API_BASE_URL=https://api.example.uz

# Server stack: game server + PostgreSQL + LiveKit
cp deploy/.env.example deploy/.env    # fill in values
docker compose -f deploy/docker-compose.yml --env-file deploy/.env up --build

# Tests
(cd packages/contracts && dart test)
(cd packages/mafia_engine && dart test)
(cd server && dart test)
(cd app && flutter test)
```

Translations live in `app/lib/l10n/app_{uz,ru,en}.arb` and are generated on
`flutter pub get` / `flutter run` (or `flutter gen-l10n`).

## Before the first store build

- Change the bundle id `com.mafiaapp.mafia_app` to the real one.
- Create the Apple developer account and the coin products in App Store
  Connect, with ids matching `CoinPack.productId`.
- Deploys to the Uzbek server will run from GitHub Actions over SSH with a
  deploy key stored as a GitHub secret. Never paste passwords or keys in chat.
