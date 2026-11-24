/// Which side a role plays for. The game ends when one side wins.
enum Team {
  town,
  mafia,

  /// The Maniac plays for no one and wins alone.
  maniac,
}

/// Every role. Add new roles at the end so stored names stay valid.
///
/// The rules for each role live in `mafia_engine`; this enum is only the
/// shared vocabulary.
enum Role {
  civilian(Team.town),
  doctor(Team.town),
  detective(Team.town),
  mafia(Team.mafia),
  don(Team.mafia),

  /// Kills one player each night on their own and wins alone.
  maniac(Team.maniac),

  /// Guards one player each night and dies in their place if they are shot.
  bodyguard(Team.town),

  /// Puts one player to sleep each night: their power does nothing that
  /// night.
  hypnotist(Team.town),

  /// Cannot be killed at night; can still be voted out.
  immortal(Team.town);

  const Role(this.team);

  final Team team;

  /// True for roles that wake up at night and act.
  bool get actsAtNight => this != Role.civilian && this != Role.immortal;

  /// Roles a room may have at most one of. Only Mafia and Civilian repeat.
  bool get unique => this != Role.mafia && this != Role.civilian;

  /// Roles added after the first version, so the app can mark them new.
  bool get isNew => index >= Role.maniac.index;
}
