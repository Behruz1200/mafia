/// Which side a role plays for. The game ends when one side wins.
enum Team { town, mafia }

/// Roles in version 1. Add new roles at the end so stored names stay valid.
///
/// The rules for each role live in `mafia_engine`; this enum is only the
/// shared vocabulary.
enum Role {
  civilian(Team.town),
  doctor(Team.town),
  detective(Team.town),
  mafia(Team.mafia),
  don(Team.mafia);

  const Role(this.team);

  final Team team;

  /// True for roles that wake up at night and act.
  bool get actsAtNight => this != Role.civilian;
}
