import '../json.dart';
import 'game_action.dart';
import 'ids.dart';
import 'phase.dart';
import 'player.dart';
import 'role.dart';
import 'room.dart';

/// Why a player left the game.
enum EliminationCause { killedAtNight, votedOut, leftMatch }

/// A public line in the match log, shown to everyone.
class PublicEvent {
  const PublicEvent({
    required this.round,
    required this.phase,
    required this.message,
    this.userId,
    this.cause,
    this.text,
  });

  final int round;
  final GamePhase phase;

  /// Stable message key for the UI to localise, e.g. `eliminated`,
  /// `nobodyDied`, `voteTied`. Never free text from the server.
  final String message;
  final UserId? userId;
  final EliminationCause? cause;

  /// Only for `lastWord` events: what [userId] typed as their last word,
  /// in their own words (cleaned by `ChatRules.clean`). Null otherwise.
  final String? text;

  Json toJson() => {
    'round': round,
    'phase': phase.name,
    'message': message,
    'userId': userId,
    'cause': cause?.name,
    if (text != null) 'text': text,
  };

  factory PublicEvent.fromJson(Json j) => PublicEvent(
    round: j['round']! as int,
    phase: decodeEnum(GamePhase.values, j['phase']),
    message: j['message']! as String,
    userId: j['userId'] as String?,
    cause: j['cause'] == null
        ? null
        : decodeEnum(EliminationCause.values, j['cause']),
    text: j['text'] as String?,
  );
}

/// What everyone in the room may see. Pushed to every member over the
/// realtime socket as `ServerMessage.publicState`.
class PublicGameState {
  const PublicGameState({
    required this.roomId,
    required this.matchId,
    required this.phase,
    required this.round,
    required this.players,
    this.phaseEndsAt,
    this.votes = const {},
    this.lastVotes = const {},
    this.skipVotes = const [],
    this.log = const [],
    this.winner,
    this.lastWordBy,
  });

  final RoomId roomId;
  final MatchId matchId;
  final GamePhase phase;

  /// 1 on the first night, +1 each night.
  final int round;
  final DateTime? phaseEndsAt;
  final List<Player> players;

  /// Open votes during [GamePhase.voting]: voter -> target (null = skip).
  final Map<UserId, UserId?> votes;

  /// How the last day vote ended: each voter -> their target (null =
  /// skipped). Open to everyone from the end of a vote until the next one
  /// starts, so the table can see who voted for whom.
  final Map<UserId, UserId?> lastVotes;

  /// Living players who agreed to end this phase's timer early
  /// (`SkipPhase`). Cleared whenever the phase changes.
  final List<UserId> skipVotes;
  final List<PublicEvent> log;

  /// Set once [phase] is [GamePhase.ended]. Null if the match was cancelled.
  final Team? winner;

  /// During [GamePhase.lastWord]: the player saying their last word. They
  /// are already out ([Player.isAlive] false) but may talk until it ends.
  final UserId? lastWordBy;

  Iterable<Player> get alive => players.where((p) => p.isAlive);

  Json toJson() => {
    'roomId': roomId,
    'matchId': matchId,
    'phase': phase.name,
    'round': round,
    'phaseEndsAt': phaseEndsAt == null ? null : encodeTime(phaseEndsAt!),
    'players': [for (final p in players) p.toJson()],
    'votes': votes,
    'lastVotes': lastVotes,
    'skipVotes': skipVotes,
    'log': [for (final e in log) e.toJson()],
    'winner': winner?.name,
    'lastWordBy': lastWordBy,
  };

  factory PublicGameState.fromJson(Json j) => PublicGameState(
    roomId: j['roomId']! as String,
    matchId: j['matchId']! as String,
    phase: decodeEnum(GamePhase.values, j['phase']),
    round: j['round']! as int,
    phaseEndsAt: decodeTimeOrNull(j['phaseEndsAt']),
    players: decodeList(j['players'], Player.fromJson),
    votes: (j['votes'] as Json? ?? const {}).map(
      (k, v) => MapEntry(k, v as String?),
    ),
    lastVotes: (j['lastVotes'] as Json? ?? const {}).map(
      (k, v) => MapEntry(k, v as String?),
    ),
    skipVotes: decodeStrings(j['skipVotes']),
    log: decodeList(j['log'], PublicEvent.fromJson),
    winner: j['winner'] == null ? null : decodeEnum(Team.values, j['winner']),
    lastWordBy: j['lastWordBy'] as String?,
  );
}

/// What only one player may see. The server sends it only on that player's
/// own socket, as `ServerMessage.privateState`.
class PrivatePlayerState {
  const PrivatePlayerState({
    required this.userId,
    required this.role,
    this.teammates = const [],
    this.checks = const {},
    this.detectiveChecks = const {},
    this.allowedActions = const [],
    this.wasAsleep = false,
  });

  final UserId userId;
  final Role role;

  /// True from the morning after the Hypnotist put this player to sleep
  /// until the next night: their power did nothing last night.
  final bool wasAsleep;

  /// Other Mafia members, for Mafia and Don only. Empty for everyone else.
  final List<UserId> teammates;

  /// Results of this player's night checks (Detective, Don).
  final Map<UserId, Team> checks;

  /// Results of the Don's night checks: true if that player is the
  /// Detective. Empty for every other role.
  final Map<UserId, bool> detectiveChecks;

  /// Action types this player may send right now, e.g. `['nightHeal']`.
  /// The UI uses it to show the right buttons; the server re-checks anyway.
  final List<String> allowedActions;

  Json toJson() => {
    'userId': userId,
    'role': role.name,
    'teammates': teammates,
    'checks': checks.map((k, v) => MapEntry(k, v.name)),
    'detectiveChecks': detectiveChecks,
    'allowedActions': allowedActions,
    'wasAsleep': wasAsleep,
  };

  factory PrivatePlayerState.fromJson(Json j) => PrivatePlayerState(
    userId: j['userId']! as String,
    role: decodeEnum(Role.values, j['role']),
    teammates: decodeStrings(j['teammates']),
    checks: (j['checks'] as Json? ?? const {}).map(
      (k, v) => MapEntry(k, decodeEnum(Team.values, v)),
    ),
    detectiveChecks: (j['detectiveChecks'] as Json? ?? const {}).map(
      (k, v) => MapEntry(k, v! as bool),
    ),
    allowedActions: decodeStrings(j['allowedActions']),
    wasAsleep: j['wasAsleep'] as bool? ?? false,
  );
}

/// The full match state, including every role. Lives only on the server
/// and inside the engine; never sent to any client.
class GameState {
  const GameState({
    required this.public,
    required this.roles,
    required this.settings,
    this.pendingNightActions = const [],
    this.seed = 0,
    this.engineData = const {},
  });

  final PublicGameState public;
  final Map<UserId, Role> roles;
  final RoomSettings settings;

  /// Night actions collected so far this night; resolved at night's end.
  final List<GameAction> pendingNightActions;

  /// Random seed used for the deal, kept so a match can be replayed.
  final int seed;

  /// The engine's own memory across phases (past heals, check results).
  /// Plain JSON so the server can store it; only `mafia_engine` reads it.
  final Json engineData;

  Json toJson() => {
    'public': public.toJson(),
    'roles': roles.map((k, v) => MapEntry(k, v.name)),
    'settings': settings.toJson(),
    'pendingNightActions': [for (final a in pendingNightActions) a.toJson()],
    'seed': seed,
    'engineData': engineData,
  };

  factory GameState.fromJson(Json j) => GameState(
    public: PublicGameState.fromJson(j['public']! as Json),
    roles: (j['roles']! as Json).map(
      (k, v) => MapEntry(k, decodeEnum(Role.values, v)),
    ),
    settings: RoomSettings.fromJson(j['settings']! as Json),
    pendingNightActions: decodeList(
      j['pendingNightActions'],
      GameAction.fromJson,
    ),
    seed: j['seed'] as int? ?? 0,
    engineData: j['engineData'] as Json? ?? const {},
  );
}
