import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:server/realtime/socket_hub.dart';
import 'package:server/rooms/match_recorder.dart';
import 'package:server/rooms/ports.dart';
import 'package:server/rooms/room_service.dart';

/// A tiny stand-in for the real rules (stream 1), just enough to drive a
/// match through the server: seat 0 is Mafia, everyone else is a civilian.
///
/// - `PhaseTimeout` steps roleReveal -> night -> day -> voting -> night.
/// - Only the Mafia may `nightKill`, only at night.
/// - When the Mafia leaves or is voted out, the town wins.
class ScriptEngine implements GameEngine {
  const ScriptEngine();

  static const order = [
    GamePhase.roleReveal,
    GamePhase.night,
    GamePhase.day,
    GamePhase.voting,
  ];

  Duration _len(RoomSettings s, GamePhase p) => switch (p) {
    GamePhase.roleReveal => s.durations.roleReveal,
    GamePhase.night => s.durations.night,
    GamePhase.day => s.durations.day,
    _ => s.durations.voting,
  };

  @override
  GameState newMatch({
    required RoomId roomId,
    required MatchId matchId,
    required List<Player> players,
    required RoomSettings settings,
    required int seed,
    required DateTime now,
  }) => GameState(
    settings: settings,
    seed: seed,
    roles: {
      for (final p in players)
        p.userId: p.seat == 0 ? Role.mafia : Role.civilian,
    },
    public: PublicGameState(
      roomId: roomId,
      matchId: matchId,
      phase: GamePhase.roleReveal,
      round: 0,
      players: players,
      phaseEndsAt: now.add(settings.durations.roleReveal),
    ),
  );

  GameState _with(GameState s, PublicGameState p) =>
      GameState(public: p, roles: s.roles, settings: s.settings, seed: s.seed);

  PublicGameState _pub(
    PublicGameState p, {
    GamePhase? phase,
    int? round,
    DateTime? endsAt,
    List<Player>? players,
    Team? winner,
  }) => PublicGameState(
    roomId: p.roomId,
    matchId: p.matchId,
    phase: phase ?? p.phase,
    round: round ?? p.round,
    phaseEndsAt: phase == GamePhase.ended ? null : (endsAt ?? p.phaseEndsAt),
    players: players ?? p.players,
    winner: winner,
  );

  ApplyResult _townWins(GameState s, List<Player> players, DateTime now) {
    final mafia = s.roles.entries.where((e) => e.value == Role.mafia);
    final mafiaIds = {for (final e in mafia) e.key};
    final next = _with(
      s,
      _pub(
        s.public,
        phase: GamePhase.ended,
        players: players,
        winner: Team.town,
      ),
    );
    return Accepted(
      next,
      matchResult: MatchResult(
        roomId: s.public.roomId,
        matchId: s.public.matchId,
        stake: s.settings.stake,
        winningTeam: Team.town,
        winners: [
          for (final u in s.roles.keys)
            if (!mafiaIds.contains(u)) u,
        ],
        losers: [...mafiaIds],
        forfeited: [
          for (final p in players)
            if (!p.isAlive && mafiaIds.contains(p.userId)) p.userId,
        ],
        endedAt: now,
      ),
    );
  }

  @override
  ApplyResult apply(GameState s, GameAction a, {required DateTime now}) {
    final p = s.public;
    switch (a) {
      case PhaseTimeout():
        final i = order.indexOf(p.phase);
        final next = order[i == order.length - 1 ? 1 : i + 1];
        return Accepted(
          _with(
            s,
            _pub(
              p,
              phase: next,
              round: next == GamePhase.night ? p.round + 1 : p.round,
              endsAt: now.add(_len(s.settings, next)),
            ),
          ),
        );
      case NightKill(:final actorId):
        if (p.phase != GamePhase.night) return const Rejected('wrong_phase');
        if (s.roles[actorId] != Role.mafia) {
          return const Rejected('not_allowed');
        }
        return Accepted(s);
      case CastVote():
        if (p.phase != GamePhase.voting) return const Rejected('wrong_phase');
        return Accepted(s);
      case PlayerLeft(:final userId):
        final players = [
          for (final x in p.players)
            x.userId == userId ? x.copyWith(isAlive: false) : x,
        ];
        if (s.roles[userId] == Role.mafia) return _townWins(s, players, now);
        return Accepted(_with(s, _pub(p, players: players)));
      default:
        return const Rejected('invalid_action');
    }
  }

  @override
  PrivatePlayerState privateView(GameState s, UserId u) =>
      PrivatePlayerState(userId: u, role: s.roles[u]!);
}

/// A fake socket that records every frame it is sent.
class TestSocket {
  TestSocket(this.hub, this.userId) {
    conn = ClientConnection(userId, frames.add);
    hub.add(conn);
  }

  final SocketHub hub;
  final UserId userId;
  late final ClientConnection conn;
  final frames = <String>[];

  List<ServerMessage> get messages => [
    for (final f in frames) ServerMessage.fromJson(jsonDecode(f) as Json),
  ];

  T? last<T extends ServerMessage>() => messages.whereType<T>().lastOrNull;

  void close() => hub.remove(conn);
}

/// Profiles for staked rooms: everyone is an adult in Uzbekistan unless
/// listed in [minors].
class TestPlayers implements PlayerDirectory {
  TestPlayers({this.minors = const {}});
  final Set<UserId> minors;

  @override
  Future<UserProfile?> profile(UserId u) async => UserProfile(
    userId: u,
    displayName: 'Name of $u',
    countryCode: 'UZ',
    isAdult: !minors.contains(u),
    createdAt: fixtureNow,
  );
}

class Rig {
  Rig({
    Map<UserId, int> coins = const {},
    PlayerDirectory? players,
    RoomsConfig config = const RoomsConfig(),
    MatchRecorder? recorder,
    GameEngine engine = const ScriptEngine(),
  }) : wallet = InMemoryWalletSettlement(balances: coins),
       recorder = recorder ?? InMemoryMatchRecorder() {
    service = RoomService(
      engine: engine,
      wallet: wallet,
      hub: hub,
      players: players ?? TestPlayers(),
      recorder: this.recorder,
      config: config,
      now: () => clock.now(),
      log: logs.add,
    );
  }

  final hub = SocketHub();
  final InMemoryWalletSettlement wallet;
  final MatchRecorder recorder;
  final logs = <String>[];
  late final RoomService service;

  final sockets = <UserId, TestSocket>{};

  TestSocket socket(UserId u) => sockets[u] = TestSocket(hub, u);
}

/// A free match settings object with the shortest allowed phases.
const fastSettings = RoomSettings(
  minPlayers: 4,
  maxPlayers: 6,
  durations: PhaseDurations(
    roleReveal: Duration(seconds: 3),
    night: Duration(seconds: 10),
    day: Duration(seconds: 20),
    voting: Duration(seconds: 10),
  ),
);

RoomSettings staked(int stake, {RoomVisibility v = RoomVisibility.private}) =>
    RoomSettings(
      minPlayers: fastSettings.minPlayers,
      maxPlayers: fastSettings.maxPlayers,
      durations: fastSettings.durations,
      stake: stake,
      visibility: v,
    );
