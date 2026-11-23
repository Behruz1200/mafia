import 'dart:convert';
import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Plays a whole match with random but legal moves, saving and loading the
/// state as JSON after every step the way the server would.
({GameState state, MatchResult result, List<GameAction> actions}) playOut(
  int seed,
  int players,
) {
  final rnd = Random(seed);
  var now = fixtureNow;
  var state = engine.newMatch(
    roomId: 'r',
    matchId: 'm$seed',
    players: samplePlayers(players),
    settings: const RoomSettings(stake: 50),
    seed: seed,
    now: now,
  );
  final actions = <GameAction>[];
  MatchResult? result;

  T pick<T>(List<T> xs) => xs[rnd.nextInt(xs.length)];

  for (var step = 0; step < 2000 && result == null; step++) {
    final alive = [for (final p in state.public.alive) p.userId];
    final moves = <GameAction>[];
    final speaker = state.public.lastWordBy;
    for (final id in [...alive, ?speaker]) {
      final view = engine.privateView(state, id);
      for (final type in view.allowedActions) {
        final target = pick(alive);
        moves.add(switch (type) {
          'nightKill' => NightKill(actorId: id, targetId: target),
          'nightHeal' => NightHeal(actorId: id, targetId: target),
          'nightCheck' => NightCheck(actorId: id, targetId: target),
          'castVote' => CastVote(
            actorId: id,
            targetId: rnd.nextInt(5) == 0 ? null : target,
          ),
          'skipPhase' => SkipPhase(actorId: id, skip: rnd.nextInt(4) != 0),
          'lastWord' => SayLastWord(actorId: id, text: 'bye $step'),
          _ => const PhaseTimeout(),
        });
      }
    }
    final roll = rnd.nextInt(20);
    final GameAction action;
    if (roll == 0 && alive.isNotEmpty) {
      action = PlayerLeft(userId: pick(alive));
    } else if (roll < 4 || moves.isEmpty) {
      now = state.public.phaseEndsAt ?? now;
      action = const PhaseTimeout();
    } else {
      action = pick(moves);
    }

    final r = engine.apply(state, action, now: now);
    if (r case Accepted(state: final next, :final matchResult)) {
      actions.add(action);
      // Round-trip through JSON like the server's storage.
      state = GameState.fromJson(
        jsonDecode(jsonEncode(next.toJson())) as Map<String, Object?>,
      );
      if (matchResult != null) result = matchResult;
    }
  }
  if (result == null) fail('seed $seed with $players players never ended');
  return (state: state, result: result, actions: actions);
}

void main() {
  test('random matches always end with a fair result', () {
    for (var seed = 0; seed < 300; seed++) {
      final players = 4 + seed % 9;
      final (:state, :result, actions: _) = playOut(seed, players);
      final everyone = state.roles.keys.toSet();

      expect(state.public.phase, GamePhase.ended);
      expect(result.winningTeam, state.public.winner);
      expect({...result.winners, ...result.losers}, everyone);
      expect(
        result.winners.toSet().intersection(result.losers.toSet()),
        isEmpty,
      );
      expect(result.losers, containsAll(result.forfeited));
      for (final w in result.winners) {
        expect(state.roles[w]!.team, result.winningTeam);
      }

      final alive = state.public.alive.map((p) => state.roles[p.userId]!.team);
      final mafia = alive.where((t) => t == Team.mafia).length;
      final town = alive.length - mafia;
      if (result.winningTeam == Team.town) {
        expect(mafia, 0);
      } else {
        expect(mafia, greaterThanOrEqualTo(town));
      }
    }
  });

  test('a match replays exactly from its seed and actions', () {
    final first = playOut(99, 10);
    var state = engine.newMatch(
      roomId: 'r',
      matchId: 'm99',
      players: samplePlayers(10),
      settings: const RoomSettings(stake: 50),
      seed: 99,
      now: fixtureNow,
    );
    var now = fixtureNow;
    for (final a in first.actions) {
      if (a is PhaseTimeout) now = state.public.phaseEndsAt ?? now;
      final r = engine.apply(state, a, now: now);
      state = (r as Accepted).state;
    }
    expect(jsonEncode(state.toJson()), jsonEncode(first.state.toJson()));
  });

  test('the public state never carries a role', () {
    final (:state, result: _, actions: _) = playOut(5, 12);
    final public = jsonEncode(state.public.toJson());
    expect(public, isNot(contains('"role"')));
    // "mafia" is also a team name (the winner), so check the others.
    for (final role in Role.values.where((r) => r != Role.mafia)) {
      expect(public, isNot(contains('"${role.name}"')));
    }
  });
}
