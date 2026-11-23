import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:test/test.dart';

/// Encodes to a JSON string and back, like the socket does.
Json wire(Json j) => jsonDecode(jsonEncode(j)) as Json;

void main() {
  test('Room', () {
    final room = sampleRoom();
    final back = Room.fromJson(wire(room.toJson()));
    expect(back.toJson(), room.toJson());
  });

  test('RoomSettings with a fixed deal', () {
    const s = RoomSettings(roleCounts: {Role.mafia: 2, Role.doctor: 1});
    expect(RoomSettings.fromJson(wire(s.toJson())).roleCounts, s.roleCounts);
  });

  test('PublicGameState with votes and log', () {
    final s = PublicGameState(
      roomId: 'r',
      matchId: 'm',
      phase: GamePhase.voting,
      round: 2,
      players: samplePlayers(6),
      votes: const {'user_1': 'user_2', 'user_3': null},
      skipVotes: const ['user_5'],
      log: const [
        PublicEvent(
          round: 1,
          phase: GamePhase.day,
          message: 'eliminated',
          userId: 'user_4',
          cause: EliminationCause.killedAtNight,
        ),
      ],
      winner: Team.town,
    );
    expect(PublicGameState.fromJson(wire(s.toJson())).toJson(), s.toJson());
  });

  test('PrivatePlayerState', () {
    const s = PrivatePlayerState(
      userId: 'u',
      role: Role.detective,
      checks: {'x': Team.mafia},
      detectiveChecks: {'y': false},
      allowedActions: ['nightCheck'],
    );
    expect(PrivatePlayerState.fromJson(wire(s.toJson())).toJson(), s.toJson());
  });

  test('GameState keeps roles and pending actions', () {
    final s = GameState(
      public: samplePublicState(phase: GamePhase.night),
      roles: const {'user_0': Role.don, 'user_1': Role.doctor},
      settings: const RoomSettings(),
      pendingNightActions: const [
        NightHeal(actorId: 'user_1', targetId: 'user_0'),
      ],
      seed: 42,
      engineData: const {
        'lastHeal': 'user_0',
        'checks': {
          'user_2': {'user_0': 'mafia'},
        },
      },
    );
    expect(GameState.fromJson(wire(s.toJson())).toJson(), s.toJson());
  });

  test('every GameAction type', () {
    const actions = <GameAction>[
      StartMatch(actorId: 'a'),
      NightKill(actorId: 'a', targetId: 'b'),
      NightHeal(actorId: 'a', targetId: 'b'),
      NightCheck(actorId: 'a', targetId: 'b'),
      CastVote(actorId: 'a', targetId: null),
      SkipPhase(actorId: 'a'),
      SkipPhase(actorId: 'a', skip: false),
      PhaseTimeout(),
      PlayerLeft(userId: 'b'),
    ];
    for (final a in actions) {
      final back = GameAction.fromJson(wire(a.toJson()));
      expect(back.runtimeType, a.runtimeType);
      expect(back.toJson(), a.toJson());
    }
  });

  test('unknown action type is rejected', () {
    expect(
      () => GameAction.fromJson({'type': 'cashOut', 'actorId': 'a'}),
      throwsFormatException,
    );
  });

  test('MatchResult, LedgerEntry, CallGrant, UserProfile, AuthSession', () {
    final result = MatchResult(
      roomId: 'r',
      matchId: 'm',
      stake: 100,
      winningTeam: Team.mafia,
      winners: const ['a'],
      losers: const ['b', 'c'],
      forfeited: const ['c'],
      endedAt: fixtureNow,
    );
    expect(
      MatchResult.fromJson(wire(result.toJson())).toJson(),
      result.toJson(),
    );

    final entry = LedgerEntry(
      id: '1',
      userId: 'a',
      kind: LedgerKind.matchPayout,
      delta: 270,
      balanceAfter: 1270,
      reference: 'm',
      createdAt: fixtureNow,
    );
    expect(LedgerEntry.fromJson(wire(entry.toJson())).toJson(), entry.toJson());

    final grant = CallGrant(
      serverUrl: 'wss://video.local',
      token: 't',
      livekitRoom: 'room_1-table',
      channel: CallChannel.table,
      canPublish: true,
      expiresAt: fixtureNow,
    );
    expect(CallGrant.fromJson(wire(grant.toJson())).toJson(), grant.toJson());

    final profile = UserProfile(
      userId: 'a',
      displayName: 'Aziza',
      createdAt: fixtureNow,
    );
    expect(
      UserProfile.fromJson(wire(profile.toJson())).toJson(),
      profile.toJson(),
    );

    final session = AuthSession(
      userId: 'a',
      accessToken: 'x',
      refreshToken: 'y',
      expiresAt: fixtureNow,
    );
    expect(
      AuthSession.fromJson(wire(session.toJson())).toJson(),
      session.toJson(),
    );
  });

  test('coin model has no way for coins to leave the app', () {
    final names = LedgerKind.values.map((k) => k.name.toLowerCase());
    for (final banned in ['withdraw', 'cashout', 'transfer', 'gift']) {
      expect(names.where((n) => n.contains(banned)), isEmpty);
    }
  });
}
