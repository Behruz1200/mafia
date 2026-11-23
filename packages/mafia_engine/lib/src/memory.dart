import 'package:contracts/contracts.dart';

/// Typed view over `GameState.engineData`: what the engine remembers from
/// one phase to the next. Stored as plain JSON so the server can persist a
/// match and replay it.
class EngineMemory {
  const EngineMemory({
    this.lastHeal,
    this.selfHealUsed = false,
    this.checks = const {},
    this.donChecks = const {},
    this.forfeited = const [],
    this.afterLastWord,
    this.nights = const [],
    this.days = const [],
  });

  /// Who the Doctor protected last night (they cannot pick them again
  /// tonight).
  final UserId? lastHeal;

  /// The Doctor may protect themselves once per match.
  final bool selfHealUsed;

  /// Detective results: checker -> target -> team.
  final Map<UserId, Map<UserId, Team>> checks;

  /// Don results: checker -> target -> is the Detective.
  final Map<UserId, Map<UserId, bool>> donChecks;

  /// Players who left while alive, in the order they left.
  final List<UserId> forfeited;

  /// During a last word: the phase that follows it (`day` after a night
  /// kill, `night` after a vote).
  final GamePhase? afterLastWord;

  /// What happened each resolved night and vote, for the end-of-match
  /// story. Only revealed once the match is over.
  final List<StoryNight> nights;
  final List<StoryVote> days;

  EngineMemory copyWith({
    UserId? Function()? lastHeal,
    bool? selfHealUsed,
    Map<UserId, Map<UserId, Team>>? checks,
    Map<UserId, Map<UserId, bool>>? donChecks,
    List<UserId>? forfeited,
    GamePhase? Function()? afterLastWord,
    List<StoryNight>? nights,
    List<StoryVote>? days,
  }) => EngineMemory(
    lastHeal: lastHeal == null ? this.lastHeal : lastHeal(),
    selfHealUsed: selfHealUsed ?? this.selfHealUsed,
    checks: checks ?? this.checks,
    donChecks: donChecks ?? this.donChecks,
    forfeited: forfeited ?? this.forfeited,
    afterLastWord: afterLastWord == null ? this.afterLastWord : afterLastWord(),
    nights: nights ?? this.nights,
    days: days ?? this.days,
  );

  Json toJson() => {
    'lastHeal': lastHeal,
    'selfHealUsed': selfHealUsed,
    'checks': {
      for (final MapEntry(:key, :value) in checks.entries)
        key: value.map((k, v) => MapEntry(k, v.name)),
    },
    'donChecks': {
      for (final MapEntry(:key, :value) in donChecks.entries) key: value,
    },
    'forfeited': forfeited,
    'afterLastWord': afterLastWord?.name,
    'nights': [for (final n in nights) n.toJson()],
    'days': [for (final d in days) d.toJson()],
  };

  factory EngineMemory.fromJson(Json j) => EngineMemory(
    lastHeal: j['lastHeal'] as String?,
    selfHealUsed: j['selfHealUsed'] as bool? ?? false,
    checks: {
      for (final MapEntry(:key, :value)
          in (j['checks'] as Map? ?? const {}).entries)
        key as String: (value as Map).map(
          (k, v) => MapEntry(k as String, Team.values.byName(v as String)),
        ),
    },
    donChecks: {
      for (final MapEntry(:key, :value)
          in (j['donChecks'] as Map? ?? const {}).entries)
        key as String: (value as Map).map(
          (k, v) => MapEntry(k as String, v as bool),
        ),
    },
    forfeited: [
      for (final e in (j['forfeited'] as List? ?? const [])) e as String,
    ],
    afterLastWord: j['afterLastWord'] == null
        ? null
        : GamePhase.values.byName(j['afterLastWord']! as String),
    nights: [
      for (final e in (j['nights'] as List? ?? const []))
        StoryNight.fromJson(e as Json),
    ],
    days: [
      for (final e in (j['days'] as List? ?? const []))
        StoryVote.fromJson(e as Json),
    ],
  );
}
