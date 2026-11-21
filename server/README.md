# server

The Mafia game server: one Dart (shelf) process, run in Docker on our own
server in Uzbekistan next to PostgreSQL and a self-hosted LiveKit.

| Folder | Owner | What |
| --- | --- | --- |
| `lib/auth` | Stream 5 | Phone SMS and Apple sign-in, JWT, profiles |
| `lib/rooms`, `lib/realtime` | Stream 2 | Rooms, matches, engine, WebSocket |
| `lib/call` | Stream 3 | LiveKit tokens and mute control |
| `lib/wallet` | Stream 4 | Ledger, settlement, App Store purchases |
| `lib/src` | Foundation | App wiring, config, shared helpers |
| `migrations` | Each stream | SQL, see migrations/README.md |

Run locally: `docker compose -f deploy/docker-compose.yml up` from the repo
root, or `dart run bin/server.dart` with the variables from
`deploy/.env.example`.
