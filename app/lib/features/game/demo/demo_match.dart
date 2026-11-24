import 'dart:async';
import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';

/// A short scripted match that plays out on [FakeRoomRepository], so the
/// game screens can be tried end to end before the real game server and
/// rules engine exist. It only pushes states through the fake's `emit*`
/// hooks, exactly the way the real server pushes them over the socket.
///
/// Nothing here decides a real game: it is a puppet show for the UI. Once
/// the rooms stream ships its real repository, this file is not used.
class DemoMatch {
  DemoMatch({
    required this.repo,
    required this.call,
    required this.me,
    Random? random,
  }) : _random = random ?? Random();

  final FakeRoomRepository repo;
  final CallController call;
  final UserId me;
  final Random _random;

  static const reveal = Duration(seconds: 6);
  static const night = Duration(seconds: 12);
  static const day = Duration(seconds: 15);
  static const voting = Duration(seconds: 15);

  final _timers = <Timer>[];
  late List<Player> _players;
  late Map<UserId, Role> _roles;
  PublicGameState? _public;
  PrivatePlayerState? _private;
  final _log = <PublicEvent>[];
  var _round = 0;
  var _matchNo = 0;
  UserId? _myNightTarget;
  bool _disposed = false;

  Room get _room => repo.room;

  /// Show the waiting room with a full table.
  void prepare() {
    _cancel();
    _players = samplePlayers(_room.memberIds.length.clamp(6, 12));
    if (!_players.any((p) => p.userId == me)) {
      _players = [
        Player(userId: me, displayName: me, seat: 0, isHost: true),
        ..._players.skip(1),
      ];
    }
    _log.clear();
    _round = 0;
    _matchNo++;
    _emitPublic(phase: GamePhase.lobby, endsIn: null);
  }

  void reset() => prepare();

  void onPlayerAction(GameAction action) {
    if (_disposed) return;
    if (action is! StartMatch && _private == null) return;
    switch (action) {
      case StartMatch():
        if (_public?.phase == GamePhase.lobby) _deal();
      case NightKill(:final targetId) || NightHeal(:final targetId):
        _myNightTarget = targetId;
        _allow(const []);
      case NightCheck(:final targetId):
        _allow(const []);
        final checks = {..._private!.checks, targetId: _roles[targetId]!.team};
        _emitPrivate(checks: checks);
      case CastVote(:final targetId):
        _allow(const []);
        _setVotes({..._public!.votes, me: targetId});
      default:
        break;
    }
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }

  // --- script -------------------------------------------------------------

  void _deal() {
    final pool = <Role>[
      Role.don,
      Role.mafia,
      Role.doctor,
      Role.detective,
      for (var i = 4; i < _players.length; i++) Role.civilian,
    ]..shuffle(_random);
    _roles = {
      for (var i = 0; i < _players.length; i++) _players[i].userId: pool[i],
    };
    _emitPublic(phase: GamePhase.roleReveal, endsIn: reveal);
    _emitPrivate(checks: const {}, allowed: const []);
    unawaited(
      call.join(
        CallGrant(
          serverUrl: 'wss://demo.invalid',
          token: 'demo',
          livekitRoom: _room.id,
          channel: CallChannel.table,
          canPublish: true,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      ),
    );
    _after(reveal, _startNight);
  }

  List<UserId> get _mafia => [
    for (final p in _players)
      if (p.isAlive && _roles[p.userId]!.team == Team.mafia) p.userId,
  ];

  List<UserId> get _town => [
    for (final p in _players)
      if (p.isAlive && _roles[p.userId]!.team == Team.town) p.userId,
  ];

  bool get _meAlive => _players.firstWhere((p) => p.userId == me).isAlive;

  void _startNight() {
    _round++;
    _myNightTarget = null;
    _emitPublic(phase: GamePhase.night, endsIn: night, votes: const {});
    if (_meAlive) {
      _allow(switch (_roles[me]!) {
        Role.mafia || Role.don => const ['nightKill'],
        Role.doctor => const ['nightHeal'],
        Role.detective => const ['nightCheck'],
        // The demo deal has none of the newer roles.
        Role.civilian ||
        Role.maniac ||
        Role.bodyguard ||
        Role.hypnotist ||
        Role.immortal => const [],
      });
    }
    _after(night, _startDay);
  }

  void _startDay() {
    _allow(const []);
    final myRole = _roles[me]!;
    // The Mafia's victim: my pick if I am Mafia, else a town player who
    // is not me (so the demo player stays in to see the whole match).
    UserId? victim;
    if (myRole.team == Team.mafia &&
        _myNightTarget != null &&
        _town.contains(_myNightTarget)) {
      victim = _myNightTarget;
    } else {
      final candidates = _town.where((u) => u != me).toList();
      victim = candidates.isEmpty
          ? null
          : candidates[_random.nextInt(candidates.length)];
    }
    if (myRole == Role.doctor && _myNightTarget == victim) victim = null;
    if (victim == null) {
      _log.add(
        PublicEvent(round: _round, phase: GamePhase.day, message: 'nobodyDied'),
      );
    } else {
      _eliminate(victim, EliminationCause.killedAtNight, GamePhase.day);
    }
    _emitPublic(phase: GamePhase.day, endsIn: day);
    _after(day, _startVoting);
  }

  void _startVoting() {
    _emitPublic(phase: GamePhase.voting, endsIn: voting, votes: const {});
    if (_meAlive) _allow(const ['castVote']);
    // The table slowly turns on one Mafia member.
    final suspect = _mafia.first;
    final bots = [
      for (final p in _players)
        if (p.isAlive && p.userId != me) p.userId,
    ]..shuffle(_random);
    for (var i = 0; i < bots.length; i++) {
      _after(Duration(milliseconds: 1500 + i * 1200), () {
        if (_public?.phase != GamePhase.voting) return;
        final voter = bots[i];
        final target = voter == suspect
            ? _town[_random.nextInt(_town.length)]
            : suspect;
        _setVotes({..._public!.votes, voter: target});
      });
    }
    _after(voting, () => _endVoting(suspect));
  }

  void _endVoting(UserId out) {
    _allow(const []);
    _eliminate(out, EliminationCause.votedOut, GamePhase.voting);
    if (_mafia.isEmpty || _mafia.length >= _town.length) {
      _end(_mafia.isEmpty ? Team.town : Team.mafia);
    } else {
      _emitPublic(phase: GamePhase.voting, endsIn: null);
      _after(const Duration(seconds: 2), _startNight);
    }
  }

  void _end(Team winner) {
    final winners = [
      for (final p in _players)
        if (_roles[p.userId]!.team == winner) p.userId,
    ];
    final losers = [
      for (final p in _players)
        if (_roles[p.userId]!.team != winner) p.userId,
    ];
    _emitPublic(phase: GamePhase.ended, endsIn: null, winner: winner);
    repo.emitMatchEnd(
      MatchResult(
        roomId: _room.id,
        matchId: _matchId,
        stake: _room.settings.stake,
        winningTeam: winner,
        winners: winners,
        losers: losers,
        roles: {for (final p in _players) p.userId: _roles[p.userId]!},
        endedAt: DateTime.now().toUtc(),
      ),
    );
    unawaited(call.leave());
  }

  void _eliminate(UserId who, EliminationCause cause, GamePhase phase) {
    _players = [
      for (final p in _players)
        p.userId == who ? p.copyWith(isAlive: false) : p,
    ];
    _log.add(
      PublicEvent(
        round: _round,
        phase: phase,
        message: 'eliminated',
        userId: who,
        cause: cause,
      ),
    );
  }

  // --- emit helpers --------------------------------------------------------

  String get _matchId => 'demo_match_$_matchNo';

  void _emitPublic({
    required GamePhase phase,
    required Duration? endsIn,
    Map<UserId, UserId?>? votes,
    Team? winner,
  }) {
    if (_disposed) return;
    _public = PublicGameState(
      roomId: _room.id,
      matchId: _matchId,
      phase: phase,
      round: _round,
      phaseEndsAt: endsIn == null ? null : DateTime.now().add(endsIn),
      players: _players,
      votes: votes ?? _public?.votes ?? const {},
      log: List.unmodifiable(_log),
      winner: winner,
    );
    repo.emitPublic(_public!);
  }

  void _setVotes(Map<UserId, UserId?> votes) {
    final p = _public!;
    _public = PublicGameState(
      roomId: p.roomId,
      matchId: p.matchId,
      phase: p.phase,
      round: p.round,
      phaseEndsAt: p.phaseEndsAt,
      players: p.players,
      votes: votes,
      log: p.log,
      winner: p.winner,
    );
    repo.emitPublic(_public!);
  }

  void _emitPrivate({Map<UserId, Team>? checks, List<String>? allowed}) {
    if (_disposed) return;
    final role = _roles[me]!;
    _private = PrivatePlayerState(
      userId: me,
      role: role,
      teammates: role.team == Team.mafia
          ? [
              for (final e in _roles.entries)
                if (e.key != me && e.value.team == Team.mafia) e.key,
            ]
          : const [],
      checks: checks ?? _private?.checks ?? const {},
      allowedActions: allowed ?? _private?.allowedActions ?? const [],
    );
    repo.emitPrivate(_private!);
  }

  void _allow(List<String> actions) => _emitPrivate(allowed: actions);

  void _after(Duration d, void Function() f) {
    _timers.add(
      Timer(d, () {
        if (!_disposed) f();
      }),
    );
  }

  void _cancel() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }
}
