import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:test/test.dart';

const engine = MafiaEngine();

/// 8 players: Don, Mafia, Detective, Doctor and 4 Civilians.
const eightDeal = {
  Role.don: 1,
  Role.mafia: 1,
  Role.detective: 1,
  Role.doctor: 1,
};

/// A small driver that keeps the current state and the clock.
class Table {
  Table({int players = 8, Map<Role, int>? deal = eightDeal, int seed = 7})
    : now = fixtureNow,
      state = engine.newMatch(
        roomId: 'room_1',
        matchId: 'match_1',
        players: samplePlayers(players),
        settings: RoomSettings(stake: 100, roleCounts: deal),
        seed: seed,
        now: fixtureNow,
      );

  GameState state;
  DateTime now;
  MatchResult? result;

  GamePhase get phase => state.public.phase;
  List<PublicEvent> get log => state.public.log;
  PublicEvent get lastEvent => log.last;

  /// Every player with [role], in seat order.
  List<UserId> all(Role role) => [
    for (final p in state.public.players)
      if (state.roles[p.userId] == role) p.userId,
  ];
  UserId one(Role role) => all(role).first;

  bool isAlive(UserId id) =>
      state.public.players.firstWhere((p) => p.userId == id).isAlive;

  /// Applies [a] and expects it to be accepted.
  void act(GameAction a) {
    final r = engine.apply(state, a, now: now);
    switch (r) {
      case Accepted(:final state, :final matchResult):
        this.state = state;
        if (matchResult != null) {
          expect(result, isNull, reason: 'match ended twice');
          result = matchResult;
        }
      case Rejected(:final code):
        fail('${a.type} by ${a.actorId} was rejected: $code');
    }
  }

  /// Applies [a] and returns the rejection code (fails if accepted).
  String reject(GameAction a) {
    final r = engine.apply(state, a, now: now);
    if (r is Rejected) return r.code;
    fail('${a.type} by ${a.actorId} was accepted');
  }

  /// Lets the current phase's timer run out.
  void timeout() {
    now = state.public.phaseEndsAt ?? now;
    act(const PhaseTimeout());
  }

  void toNight() {
    expect(phase, GamePhase.roleReveal);
    timeout();
    expect(phase, GamePhase.night);
  }

  void toVoting() {
    expect(phase, GamePhase.day);
    timeout();
    expect(phase, GamePhase.voting);
  }
}
