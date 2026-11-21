# server

The Mafia game server: one Dart (shelf) process. In production it is a
native binary run by systemd on our server in Uzbekistan, next to
PostgreSQL and a self-hosted LiveKit (see deploy/README.md). Docker is only
for local development.

| Folder | Owner | What |
| --- | --- | --- |
| `lib/auth` | Stream 5 | Phone SMS and Apple sign-in, JWT, profiles |
| `lib/rooms`, `lib/realtime` | Stream 2 | Rooms, matches, engine, WebSocket |
| `lib/call` | Stream 3 | LiveKit tokens and mute control |
| `lib/wallet` | Stream 4 | Ledger, settlement, App Store purchases |
| `lib/src` | Foundation | App wiring, config, shared helpers |
| `migrations` | Each stream | SQL, see migrations/README.md |

Run locally: `docker compose -f deploy/local/docker-compose.yml --env-file
deploy/local/.env up --build` from the repo root, or `dart run
bin/server.dart` with the variables from `deploy/local/.env.example`.
