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
      SayLastWord(actorId: 'a', text: 'It was the Don'),
      PhaseTimeout(),
      PlayerLeft(userId: 'b'),
    ];
    for (final a in actions) {
      final back = GameAction.fromJson(wire(a.toJson()));
      expect(back.runtimeType, a.runtimeType);
      expect(back.toJson(), a.toJson());
    }
  });

  test('last word fields', () {
    final s = PublicGameState(
      roomId: 'r',
      matchId: 'm',
      phase: GamePhase.lastWord,
      round: 1,
      players: samplePlayers(6),
      lastWordBy: 'user_2',
      log: const [
        PublicEvent(
          round: 1,
          phase: GamePhase.lastWord,
          message: 'lastWord',
          userId: 'user_2',
          text: 'Trust user_4',
        ),
      ],
    );
    final back = PublicGameState.fromJson(wire(s.toJson()));
    expect(back.toJson(), s.toJson());
    expect(back.lastWordBy, 'user_2');
    expect(back.log.single.text, 'Trust user_4');

    const d = PhaseDurations(lastWord: Duration(seconds: 45));
    expect(PhaseDurations.fromJson(wire(d.toJson())).lastWord.inSeconds, 45);
    // Settings stored before last words existed get the default.
    final old = d.toJson()..remove('lastWordSec');
    expect(PhaseDurations.fromJson(old).lastWord, const Duration(seconds: 30));
  });

  test('chat messages on the socket', () {
    final m = ChatMessage(
      id: 'c1',
      roomId: 'r',
      matchId: 'm',
      senderId: 'u',
      senderName: 'Aziz',
      text: 'salom',
      channel: ChatChannel.mafia,
      sentAt: DateTime.utc(2026, 11, 23, 18),
      lastWord: true,
    );
    final posted = ServerMessage.fromJson(wire(ChatPosted(m).toJson()));
    expect((posted as ChatPosted).message.toJson(), m.toJson());
    final hist = ServerMessage.fromJson(wire(ChatHistory('r', [m]).toJson()));
    expect((hist as ChatHistory).messages.single.toJson(), m.toJson());
    final r = ChatReaction(
      roomId: 'r',
      senderId: 'u',
      emoji: '🤫',
      channel: ChatChannel.dead,
      sentAt: DateTime.utc(2026, 11, 23, 18),
    );
    final shown = ServerMessage.fromJson(wire(ReactionShown(r).toJson()));
    expect((shown as ReactionShown).reaction.toJson(), r.toJson());
    final react = ClientMessage.fromJson(
      wire(const SendReaction('r', '👍').toJson()),
    );
    expect((react as SendReaction).emoji, '👍');
    final sent = ClientMessage.fromJson(
      wire(const SendChat('r', 'hi').toJson()),
    );
    expect((sent as SendChat).text, 'hi');
  });

  group('ChatRules', () {
    test('clean squeezes blanks and cuts long text', () {
      expect(ChatRules.clean('  a\n\t b\u0000c  '), 'a b c');
      expect(ChatRules.clean(' \n '), isEmpty);
      expect(ChatRules.clean('😀' * 300).runes, hasLength(200));
    });

    ChatChannel? where(
      GamePhase? phase, {
      bool alive = true,
      Role role = Role.civilian,
      bool speaker = false,
    }) => ChatRules.channelFor(
      phase: phase,
      inMatch: true,
      isAlive: alive,
      role: role,
      isLastWordSpeaker: speaker,
    );

    test('who writes where', () {
      expect(where(null), ChatChannel.table);
      expect(where(GamePhase.day), ChatChannel.table);
      expect(where(GamePhase.voting), ChatChannel.table);
      expect(where(GamePhase.day, alive: false), ChatChannel.dead);
      expect(where(GamePhase.night), isNull);
      expect(where(GamePhase.night, role: Role.don), ChatChannel.mafia);
      expect(where(GamePhase.night, alive: false), ChatChannel.dead);
      expect(where(GamePhase.lastWord), isNull);
      expect(
        where(GamePhase.lastWord, alive: false, speaker: true),
        ChatChannel.table,
      );
      expect(where(GamePhase.ended, alive: false), ChatChannel.table);
    });

    test('who reads what', () {
      bool reads(ChatChannel c, {bool alive = true, Role role = Role.doctor}) =>
          ChatRules.canRead(
            channel: c,
            inMatch: true,
            isAlive: alive,
            role: role,
          );
      expect(reads(ChatChannel.table), isTrue);
      expect(reads(ChatChannel.mafia), isFalse);
      expect(reads(ChatChannel.mafia, role: Role.mafia), isTrue);
      expect(reads(ChatChannel.dead), isFalse);
      expect(reads(ChatChannel.dead, alive: false), isTrue);
    });
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
      roles: const {'a': Role.don, 'b': Role.detective, 'c': Role.civilian},
      endedAt: fixtureNow,
    );
    expect(
      MatchResult.fromJson(wire(result.toJson())).toJson(),
      result.toJson(),
    );
    expect(MatchResult.fromJson(wire(result.toJson())).roles['a'], Role.don);
    // Results from older servers carry no roles.
    final old = result.toJson()..remove('roles');
    expect(MatchResult.fromJson(wire(old)).roles, isEmpty);

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
