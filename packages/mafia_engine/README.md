# mafia_engine

The rules of Mafia, owned by stream 1. Implements `GameEngine` from
`package:contracts`. Pure Dart, deterministic, fully unit tested. The game
server runs it; the app may use it for previews, but never to decide results.

```dart
const engine = MafiaEngine();
var state = engine.newMatch(roomId: ..., matchId: ..., players: ...,
    settings: room.settings, seed: seed, now: now);
switch (engine.apply(state, action, now: now)) {
  case Accepted(:final state, :final matchResult): // save, push, settle
  case Rejected(:final code): // tell the sender, see RejectCodes
}
final mine = engine.privateView(state, userId); // send on their socket only
```

## Rules (version 1)

**Deal.** At least 4 players. Unless the host fixes a deal in
`RoomSettings.roleCounts`, the engine deals one Mafia member per three
players; from two Mafia members up, one is the Don. There is a Detective from
4 players and a Doctor from 5; everyone else is a Civilian. The deal is
shuffled from the match seed, so the same seed always deals the same way.

| Players | Don | Mafia | Detective | Doctor | Civilian |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 0 | 1 | 1 | 0 | 2 |
| 5 | 0 | 1 | 1 | 1 | 2 |
| 6 | 1 | 1 | 1 | 1 | 2 |
| 7 | 1 | 1 | 1 | 1 | 3 |
| 8 | 1 | 1 | 1 | 1 | 4 |
| 9 to 11 | 1 | 2 | 1 | 1 | 4 to 6 |
| 12 | 1 | 3 | 1 | 1 | 6 |

A fixed deal may have at most one Don, Doctor and Detective, needs at least
one Mafia member, and the Mafia must be fewer than the town.

**Phases.** `roleReveal` (the host may skip it with `StartMatch`), then
`night -> day -> voting` until a team wins. The round number goes up each
night. The server sends `PhaseTimeout` when `phaseEndsAt` passes; the engine
rejects it earlier with `too_early`.

**Night.** Every pick can be changed until the night ends.

- Mafia and Don pick a kill target (not a Mafia member). The Don's pick wins;
  without one, the most-picked target, ties going to the pick of the lowest
  seat.
- The Doctor protects one player. Not the same player two nights in a row,
  and themselves only once per match. A protected target survives, and the
  town only hears that nobody died.
- The Detective checks one player and learns their team (the Don shows as
  Mafia). The Don checks one non-Mafia player and learns whether they are the
  Detective. Nobody checks the same player twice. Results arrive in the
  private view when the night ends.
- The night ends early once every living night role has made every pick.

**Day.** Talk. The night's result is in the log. Ends on the timer.

**Voting.** Every living player votes for another living player or skips,
and may change their vote. The most-voted player is out if they have more
votes than anyone else and more votes than there are skips. Players who did
not vote do not count. Voting ends early once every living player has voted.

**Winning.** Checked after every elimination. The town wins when no Mafia
member is alive. The Mafia win once they are at least as many as the living
town. Everyone on the winning team wins, dead or alive.

**Leaving.** `PlayerLeft` for a living player takes them out of the game and
forfeits their stake: they are listed as a loser even if their team wins. A
player who is already out can leave without forfeiting.

## Log messages

`PublicEvent.message` is always one of `EventKeys`: `rolesDealt`,
`nightStarted`, `eliminated` (with `userId` and `cause`), `nobodyDied`,
`dayStarted`, `votingStarted`, `voteTied`, `nobodyVotedOut`, `playerLeft`,
`townWon`, `mafiaWon`. The app localises them.

## Rejection codes

See `RejectCodes`: `wrong_phase`, `match_ended`, `not_host`,
`not_your_role`, `unknown_player`, `actor_dead`, `target_dead`,
`target_self`, `target_teammate`, `already_checked`, `same_heal_twice`,
`self_heal_used`, `already_left`, `too_early`.

## What the engine keeps between phases

`GameState.engineData` holds the Doctor's last protection, whether they used
their self protection, every check result and who forfeited. It is plain
JSON: store it with the rest of the state and pass it back unchanged.
