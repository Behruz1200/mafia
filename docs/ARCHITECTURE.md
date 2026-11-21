# Architecture

Full plan: https://claude.ai/artifact/PjXkehkN4SfEzv3pRuWJHi

```
 iPhone / Android app (Flutter)
   │  HTTPS (REST)  +  WebSocket (live game state)      LiveKit (video)
   ▼                                                    ▼
 ┌───────────────── our server in Uzbekistan (Docker) ─────────────────┐
 │  Dart game server  ── runs mafia_engine, wallet, auth               │
 │  PostgreSQL        ── profiles, rooms, append-only coin ledger      │
 │  LiveKit           ── video rooms; server mutes players at night    │
 └─────────────────────────────────────────────────────────────────────┘
   App Store (coin purchases, verified by the server)
   Firebase (push notifications and crash reports only, no player data)
```

- The app talks to the server through the interfaces in
  `packages/contracts/lib/src/ports`. Until a stream lands, the app uses the
  fakes in `package:contracts/testing.dart` (`USE_FAKES=true`, the default).
- Live game state goes over one WebSocket (`ClientMessage` / `ServerMessage`).
- Sign-in is our own: phone number with an SMS code from a local provider,
  and Sign in with Apple. The server issues JWTs.
- Coins: Apple in-app purchase first, Google Play later. Every coin movement
  is a row in an append-only ledger; settlement runs once per match.
- Countries and where stakes are allowed come from server config
  (`LAUNCH_COUNTRIES`, `STAKE_COUNTRIES`); today that is `UZ`.
- Languages: Uzbek (default), Russian, English.
