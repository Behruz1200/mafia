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

  EngineMemory copyWith({
    UserId? Function()? lastHeal,
    bool? selfHealUsed,
    Map<UserId, Map<UserId, Team>>? checks,
    Map<UserId, Map<UserId, bool>>? donChecks,
    List<UserId>? forfeited,
  }) => EngineMemory(
    lastHeal: lastHeal == null ? this.lastHeal : lastHeal(),
    selfHealUsed: selfHealUsed ?? this.selfHealUsed,
    checks: checks ?? this.checks,
    donChecks: donChecks ?? this.donChecks,
    forfeited: forfeited ?? this.forfeited,
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
  );
}
