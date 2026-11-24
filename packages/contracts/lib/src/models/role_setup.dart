import 'role.dart';

/// Why a room's chosen roles can't be dealt. [code] is the stable error
/// code the server sends; the app localises it.
enum RoleSetupProblem {
  /// Fewer players than a match needs.
  tooFewPlayers('not_enough_players'),

  /// A count below zero, or more than one of a role there can only be one
  /// of (everything except Mafia and Civilian).
  invalidCount('roles_invalid'),

  /// No Mafia at all.
  noMafia('roles_no_mafia'),

  /// More roles than seated players.
  tooManyRoles('roles_too_many'),

  /// The Mafia and the Maniac together are not fewer than the town, so the
  /// town would lose at once.
  tooStrong('roles_too_strong');

  const RoleSetupProblem(this.code);
  final String code;
}

/// The rules for which roles a match is dealt. Shared by the engine (which
/// deals), the server (which refuses a bad setup) and the app (which shows
/// the setup and only lets the host pick a fair one).
abstract final class RoleSetup {
  /// The fewest players a match can be dealt for.
  static const minPlayers = 4;

  /// The deal used when the host does not pick one.
  ///
  /// One Mafia member for every three players, but only one up to 6 players
  /// (two Mafia against four town ends most 6-player games on day one).
  /// From two Mafia members up, one of them is the Don. A Detective from 4
  /// players and a Doctor from 5. Everyone else is a Civilian. The newer
  /// roles (Maniac, Bodyguard, Hypnotist, Immortal) only play when the host
  /// adds them.
  ///
  /// | Players | Don | Mafia | Detective | Doctor | Civilian |
  /// | ---: | ---: | ---: | ---: | ---: | ---: |
  /// | 4 | 0 | 1 | 1 | 0 | 2 |
  /// | 5 | 0 | 1 | 1 | 1 | 2 |
  /// | 6 | 0 | 1 | 1 | 1 | 3 |
  /// | 7 | 1 | 1 | 1 | 1 | 3 |
  /// | 8 | 1 | 1 | 1 | 1 | 4 |
  /// | 9 | 1 | 2 | 1 | 1 | 4 |
  /// | 12 | 1 | 3 | 1 | 1 | 6 |
  static Map<Role, int> standard(int players) {
    final n = players < minPlayers ? minPlayers : players;
    final mafiaTeam = n <= 6 ? 1 : n ~/ 3;
    final don = mafiaTeam >= 2 ? 1 : 0;
    final counts = <Role, int>{
      Role.don: don,
      Role.mafia: mafiaTeam - don,
      Role.detective: 1,
      Role.doctor: n >= 5 ? 1 : 0,
    };
    counts[Role.civilian] = n - _sum(counts);
    return counts;
  }

  /// Null when [counts] (every role except Civilian; Civilians fill the
  /// rest) makes a fair match for [players], else what is wrong.
  static RoleSetupProblem? check(int players, Map<Role, int> counts) {
    if (players < minPlayers) return RoleSetupProblem.tooFewPlayers;
    for (final MapEntry(key: role, value: n) in counts.entries) {
      if (role == Role.civilian) continue;
      if (n < 0 || (role.unique && n > 1)) {
        return RoleSetupProblem.invalidCount;
      }
    }
    final mafia = (counts[Role.mafia] ?? 0) + (counts[Role.don] ?? 0);
    if (mafia == 0) return RoleSetupProblem.noMafia;
    final special = _sum({
      for (final e in counts.entries)
        if (e.key != Role.civilian) e.key: e.value,
    });
    if (special > players) return RoleSetupProblem.tooManyRoles;
    final evil = mafia + (counts[Role.maniac] ?? 0);
    if (evil * 2 >= players) return RoleSetupProblem.tooStrong;
    return null;
  }

  /// [counts] with Civilians filling the seats no other role takes, for
  /// [players]. Call [check] first.
  static Map<Role, int> fill(int players, Map<Role, int> counts) {
    final out = <Role, int>{
      for (final r in Role.values)
        if (r != Role.civilian && (counts[r] ?? 0) > 0) r: counts[r]!,
    };
    out[Role.civilian] = players - _sum(out);
    return out;
  }

  /// What a room deals for [players]: the host's [fixed] roles with
  /// Civilians filling the rest, or [standard] when there are none.
  static Map<Role, int> deal(int players, Map<Role, int>? fixed) =>
      fixed == null ? standard(players) : fill(players, fixed);

  static int _sum(Map<Role, int> m) => m.values.fold(0, (a, b) => a + b);
}
