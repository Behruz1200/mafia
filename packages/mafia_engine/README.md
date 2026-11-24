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
players, but only one up to 6 players; from two Mafia members up, one is the
Don. There is a Detective from
4 players and a Doctor from 5; everyone else is a Civilian. The deal is
shuffled from the match seed, so the same seed always deals the same way.

| Players | Don | Mafia | Detective | Doctor | Civilian |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | 0 | 1 | 1 | 0 | 2 |
| 5 | 0 | 1 | 1 | 1 | 2 |
| 6 | 0 | 1 | 1 | 1 | 3 |
| 7 | 1 | 1 | 1 | 1 | 3 |
| 8 | 1 | 1 | 1 | 1 | 4 |
| 9 to 11 | 1 | 2 | 1 | 1 | 4 to 6 |
| 12 | 1 | 3 | 1 | 1 | 6 |

A fixed deal may have at most one Don, Doctor and Detective, needs at least
one Mafia member, and the Mafia must be fewer than the town.

**Phases.** `roleReveal` (the host may skip it with `StartMatch`), then
`night -> day -> voting` until a team wins, with a `lastWord` after each
elimination (see below). The round number goes up each night. The server sends `PhaseTimeout` when `phaseEndsAt` passes; the engine
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

**Day.** Talk. The night's result is in the log. Ends on the timer, or
early once two thirds of the living players (rounded up, `SkipPhase.needed`)
have sent `SkipPhase` ("skip the timer").
Each agreement shows in `PublicGameState.skipVotes`; a player can take it
back with `SkipPhase(skip: false)`, and the list clears when the phase
changes. One player alone can never skip for everyone. The role reveal can
be skipped the same way.

**Voting.** Every living player votes for another living player or skips,
and may change their vote. The most-voted player is out if they have more
votes than anyone else and more votes than there are skips. Players who did
not vote do not count. Voting ends early once every living player has voted.

**Last word.** When someone is killed at night or voted out and the match
goes on, a `lastWord` phase comes first (`night -> lastWord -> day`,
`voting -> lastWord -> night`). `PublicGameState.lastWordBy` is the speaker:
already out, but the only one who may talk at the table (30 seconds by
default, `PhaseDurations.lastWord`). They may type up to three lines
(`SayLastWord`, each cleaned and cut to 200 characters by
`ChatRules.clean`), which go to the log as `lastWord` events with `text`, and
may end it early with `SkipPhase`; nobody else can. It ends at once if the
speaker leaves. A player saved by the Doctor, a player who leaves, and an
elimination that ends the match get no last word.

**Winning.** Checked after every elimination. The town wins when no Mafia
member is alive. The Mafia win once they are at least as many as the living
town. Everyone on the winning team wins, dead or alive.

**Leaving.** `PlayerLeft` for a living player takes them out of the game and
forfeits their stake: they are listed as a loser even if their team wins. A
player who is already out can leave without forfeiting.

## Log messages

`PublicEvent.message` is always one of `EventKeys`: `rolesDealt`,
`nightStarted`, `eliminated` (with `userId` and `cause`), `nobodyDied`,
`dayStarted`, `votingStarted`, `voteTied`, `nobodyVotedOut`, `phaseSkipped`,
`lastWord` (with `userId` and the typed `text`), `playerLeft`,
`townWon`, `mafiaWon`. The app localises them.

## The match story

Each resolved night (the Mafia's target and who picked it, the Doctor's
pick, whether it saved them, every check and its result) and each resolved
vote (every vote, who was out, or a tie) is kept in the engine's memory.
When the match ends it goes out as `MatchResult.story`, beside
`MatchResult.roles`, and the app plays it as the end-of-match cartoon.
It is never on the public state while the match runs.

## Rejection codes

See `RejectCodes`: `wrong_phase`, `match_ended`, `not_host`,
`not_your_role`, `unknown_player`, `actor_dead`, `target_dead`,
`target_self`, `target_teammate`, `already_checked`, `same_heal_twice`,
`self_heal_used`, `already_left`, `too_early`, `empty_text`,
`last_word_full`.

## What the engine keeps between phases

`GameState.engineData` holds the Doctor's last protection, whether they used
their self protection, every check result, who forfeited and, during a last
word, which phase comes next. It is plain
JSON: store it with the rest of the state and pass it back unchanged.
