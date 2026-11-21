# Rooms and the game server (stream 2)

`RoomService` owns every room and live match in this process.
`RoomsModule` puts it on HTTP (`ApiRoutes.rooms`, `joinRoom`, `quickMatch`,
`room`, `leaveRoom`) and on the realtime socket (`lib/realtime`).

## How a match runs

1. A host creates a room (private by default) and shares the 5-letter code,
   or players use quick match, which fills the fullest public room or opens
   a new one.
2. The host sends `startMatch` on the socket. Public rooms start on their
   own 20 seconds after reaching `minPlayers`, or at once when full.
3. Start: the match is recorded (`rooms_matches`), then the wallet holds
   every player's stake, all or nothing. If anyone is short, nobody is
   charged; in a public room those players are moved out.
4. The engine deals. Each player gets the public state, and their own
   private state on their own sockets only.
5. Player actions come in on the socket. The server replaces `actorId` with
   the signed-in user, refuses `phaseTimeout` and `playerLeft` from apps,
   and feeds the rest to the engine. Rejections go back to that socket only.
6. The server runs the phase clock from `phaseEndsAt` and sends
   `phaseTimeout` itself.
7. When the engine returns a `MatchResult`, everyone gets `matchEnded`, the
   wallet settles (retried, idempotent per match), and players get their new
   balance.

## Disconnects

A player whose last socket closes shows as `isConnected: false`. Back within
60 seconds: nothing lost (watching the room again re-sends room, public and
private state). Gone longer: removed from a lobby, or `playerLeft` in a
match, which forfeits the stake. Leaving a match on purpose forfeits too.

## Coins are never stuck

Every match is written to PostgreSQL before any coin moves. On start the
server settles every match a previous run left unsettled: finished ones are
paid out from the stored result, unfinished ones are refunded. A match still
running after 2 hours, or whose engine throws on a clock tick, is cancelled
and refunded.

## Seams for other streams (`ports.dart`)

| Seam | Default until wired | Real one |
| --- | --- | --- |
| `GameEngine` | `MafiaEngine` (stream 1) | same |
| `WalletSettlement` | `FreeMatchesOnlyWallet`: free matches only | stream 4 |
| `TokenVerifier` | `JwtTokenVerifier` with `JWT_SECRET`, else deny all | stream 5 may pass its own |
| `PlayerDirectory` | `AnonymousPlayers`: "Player abcd", stakes closed | stream 5 `profileOf` |

For video (stream 3), `RoomService` exposes `room`, `isMember`,
`publicState`, `roleOf`, and the `publicChanges` and `roomChanges` streams;
`SocketHub.sendToUser` pushes a `CallGrantIssued` to one player.

## Environment

- `JWT_SECRET`: verifies access tokens (HS256, `sub` = user id, `exp`).
- `DEV_AUTH=true`: also accepts `dev:<userId>` tokens. Local testing only,
  never on the real server.
- `DATABASE_URL`: match records in PostgreSQL (migration 0002). Without it
  records stay in memory and crash recovery is off.

## Limits (`RoomsConfig`)

200 rooms, 4 to 12 players, stakes up to 10,000 coins, phases between the
bounds in `RoomService._validate`, idle lobbies closed after 30 minutes.
Sized for the current 2-core server shared with the store app.
