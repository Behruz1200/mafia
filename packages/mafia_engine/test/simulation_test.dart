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
  int players, {
  Map<Role, int>? roles,
}) {
  final rnd = Random(seed);
  var now = fixtureNow;
  var state = engine.newMatch(
    roomId: 'r',
    matchId: 'm$seed',
    players: samplePlayers(players),
    settings: RoomSettings(stake: 50, roleCounts: roles),
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
          'nightGuard' => NightGuard(actorId: id, targetId: target),
          'nightSleep' => NightSleep(actorId: id, targetId: target),
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

/// As many of the newer roles as fit a fair game for [players].
Map<Role, int> withNewRoles(int players) {
  final roles = <Role, int>{Role.mafia: 1};
  for (final r in [
    Role.maniac,
    Role.detective,
    Role.doctor,
    Role.bodyguard,
    Role.hypnotist,
    Role.immortal,
    Role.don,
  ]) {
    final next = {...roles, r: 1};
    if (RoleSetup.check(players, next) == null) roles[r] = 1;
  }
  return roles;
}

void main() {
  for (final newRoles in [false, true]) {
    test(
      newRoles
          ? 'random matches with the newer roles end with a fair result'
          : 'random matches always end with a fair result',
      () => checkFairEnds(newRoles: newRoles),
    );
  }

  test('the newer roles fit from 5 players', () {
    expect(withNewRoles(5), contains(Role.maniac));
    expect(withNewRoles(12).length, 8);
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
    // "mafia" and "maniac" are also team names (the winner), so check the
    // others.
    for (final role in Role.values.where(
      (r) => r != Role.mafia && r != Role.maniac,
    )) {
      expect(public, isNot(contains('"${role.name}"')));
    }
  });
}

void checkFairEnds({required bool newRoles}) {
  for (var seed = 0; seed < 300; seed++) {
    final players = (newRoles ? 5 : 4) + seed % (newRoles ? 8 : 9);
    final (:state, :result, actions: _) = playOut(
      seed,
      players,
      roles: newRoles ? withNewRoles(players) : null,
    );
    final everyone = state.roles.keys.toSet();

    expect(state.public.phase, GamePhase.ended);
    expect(result.winningTeam, state.public.winner);
    expect({...result.winners, ...result.losers}, everyone);
    // Every card is revealed at the end, and matches the deal.
    expect(result.roles, state.roles);
    expect(result.winners.toSet().intersection(result.losers.toSet()), isEmpty);
    expect(result.losers, containsAll(result.forfeited));
    for (final w in result.winners) {
      expect(state.roles[w]!.team, result.winningTeam);
    }

    final alive = state.public.alive.map((p) => state.roles[p.userId]!.team);
    final mafia = alive.where((t) => t == Team.mafia).length;
    final town =
        alive.length - mafia - alive.where((t) => t == Team.maniac).length;
    final maniac = alive.where((t) => t == Team.maniac).length;
    switch (result.winningTeam) {
      case Team.town:
        expect(mafia + maniac, 0);
      case Team.mafia:
        expect(mafia, greaterThanOrEqualTo(town));
      case Team.maniac:
        expect(maniac, 1);
        expect(alive.length, lessThanOrEqualTo(2));
      case null:
        fail('no winner');
    }
  }
}
