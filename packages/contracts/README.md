# contracts

Shared models and interfaces between every part of the Mafia app. Pure Dart:
no Flutter, Firebase or database imports, so the app, the engine and the
server can all depend on it.

| Folder | What is in it |
| --- | --- |
| `lib/src/models` | Room, Player, game state, actions, match result, wallet, profile, call grant |
| `lib/src/api` | HTTP routes and request bodies, realtime socket messages |
| `lib/src/ports` | Interfaces each stream implements (`GameEngine`, repositories, `WalletSettlement`) |
| `lib/src/policy` | Region and language rules, driven by config |
| `lib/testing.dart` | Fakes and fixtures, so streams can work without each other |

Changing anything here follows [docs/CONTRACTS.md](../../docs/CONTRACTS.md).
