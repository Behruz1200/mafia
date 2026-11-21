# Mafia

The Mafia card game for iOS and Android, with live video at the table and
coins that winners take from losers.

| Folder | What |
| --- | --- |
| `app/` | Flutter app (Riverpod, go_router, Uzbek/Russian/English) |
| `packages/contracts/` | Shared models and interfaces every part codes against |
| `packages/mafia_engine/` | The game rules, pure Dart |
| `server/` | Dart game server: auth, rooms, realtime, video tokens, wallet |
| `deploy/` | Production setup for our server in Uzbekistan (systemd, no Docker), and Docker Compose for local development |
| `firebase/` | Push notifications and crash reports only |
| `docs/` | [Architecture](docs/ARCHITECTURE.md), [ownership](docs/OWNERSHIP.md), [contracts](docs/CONTRACTS.md), [developing](docs/DEVELOPING.md) |
