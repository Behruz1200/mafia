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

The table is `RoleSetup.standard` in `package:contracts`. The newer roles
(Maniac, Bodyguard, Hypnotist, Immortal) only play when the host adds them.
A fixed deal lists every role but Civilian; Civilians fill the other seats
(`RoleSetup.fill`). `RoleSetup.check` refuses it unless there is at most one
of every role except Mafia and Civilian, at least one Mafia member, no more
roles than players, and the Mafia and the Maniac together are fewer than
half the players. The server runs the same check when the host changes the
roles and again at start.

| Role | Team | At night |
| --- | --- | --- |
| Civilian | town | sleeps |
| Doctor | town | protects one player |
| Detective | town | checks one player's team |
| Bodyguard | town | guards one other player |
| Hypnotist | town | puts one other player to sleep |
| Immortal | town | sleeps, and can't be killed at night |
| Mafia | mafia | picks a kill with the Don |
| Don | mafia | picks the kill, checks for the Detective |
| Maniac | maniac (alone) | kills one player of their own |

**Phases.** `roleReveal` (the host may skip it with `StartMatch`), then
`night -> day -> voting` until a team wins, with a `lastWord` after each
elimination (see below). The round number goes up each night. The server sends `PhaseTimeout` when `phaseEndsAt` passes; the engine
rejects it earlier with `too_early`.

**Night.** Every pick can be changed until the night ends.

- The Hypnotist (`NightSleep`) puts one other player to sleep, not the same
  player two nights in a row. The sleeper's picks tonight do nothing, and
  their private view says so (`wasAsleep`) until the next night.
- Mafia and Don pick a kill target (not a Mafia member). The Don's pick wins;
  without one, the most-picked target, ties going to the pick of the lowest
  seat.
- The Maniac picks a kill of their own (`NightKill`, anyone but themselves),
  so up to two players can die in one night.
- The Doctor protects one player. Not the same player two nights in a row,
  and themselves only once per match. A protected target survives, and the
  town only hears that nobody died.
- The Bodyguard (`NightGuard`) guards one other player, not the same player
  two nights in a row. A shot at the guarded player hits the Bodyguard
  instead, unless the Doctor protected the target or the Bodyguard.
- A shot that reaches the Immortal does nothing.
- The Detective checks one player and learns their team (the Don shows as
  Mafia, the Maniac as Maniac). The Don checks one non-Mafia player and learns whether they are the
  Detective. Nobody checks the same player twice. Results arrive in the
  private view when the night ends.
- The night ends early once every living night role has made every pick.
  Once the Don has shot, the other Mafia need not pick (the Don's shot
  decides), unless the Hypnotist put the Don to sleep that night.

**Day.** Talk. The night's result is in the log. Ends on the timer, or
early once more than half of the living players (`SkipPhase.needed`: 3 of 4,
3 of 5, 4 of 7) have sent `SkipPhase` ("skip the timer").
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
speaker leaves. When two players die in one night they speak one after the
other (the Mafia's victim first). A player saved by the Doctor, a player who
leaves, and an elimination that ends the match get no last word.

**Winning.** Checked after every elimination. The Maniac wins when they are
alive and at most two players are left. The town wins when no Mafia member
and no Maniac is alive. The Mafia win once they are at least as many as
everyone else alive (town and Maniac). Everyone on the winning team wins,
dead or alive.

**Leaving.** `PlayerLeft` for a living player takes them out of the game and
forfeits their stake: they are listed as a loser even if their team wins. A
player who is already out can leave without forfeiting.

## Log messages

`PublicEvent.message` is always one of `EventKeys`: `rolesDealt`,
`nightStarted`, `eliminated` (with `userId` and `cause`), `nobodyDied`,
`dayStarted`, `votingStarted`, `voteTied`, `nobodyVotedOut`, `phaseSkipped`,
`lastWord` (with `userId` and the typed `text`), `playerLeft`,
`townWon`, `mafiaWon`, `maniacWon`. The app localises them.

## The match story

Each resolved night (the Mafia's target and who picked it, the Doctor's
pick, whether it saved them, every check and its result, every shot in
`attacks` with its outcome, who the Bodyguard guarded and the Hypnotist put
to sleep) and each resolved
vote (every vote, who was out, or a tie) is kept in the engine's memory.
When the match ends it goes out as `MatchResult.story`, beside
`MatchResult.roles`, and the app plays it as the end-of-match cartoon.
It is never on the public state while the match runs.

## Rejection codes

See `RejectCodes`: `wrong_phase`, `match_ended`, `not_host`,
`not_your_role`, `unknown_player`, `actor_dead`, `target_dead`,
`target_self`, `target_teammate`, `already_checked`, `same_heal_twice`,
`same_guard_twice`, `same_sleep_twice`, `self_heal_used`, `already_left`, `too_early`, `empty_text`,
`last_word_full`.

## What the engine keeps between phases

`GameState.engineData` holds the Doctor's last protection, whether they used
their self protection, the Bodyguard's and Hypnotist's last picks, who
slept last night, every check result, who forfeited and, during a last
word, which phase comes next and who speaks after. It is plain
JSON: store it with the rest of the state and pass it back unchanged.
