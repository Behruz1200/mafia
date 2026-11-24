import 'package:contracts/contracts.dart';

import 'rng.dart';

/// The fewest players a match can be dealt for.
const minPlayersForMatch = RoleSetup.minPlayers;

/// The deal used when the host does not fix one. See [RoleSetup.standard].
Map<Role, int> defaultRoleCounts(int players) {
  if (players < minPlayersForMatch) {
    throw ArgumentError.value(
      players,
      'players',
      'need at least $minPlayersForMatch players',
    );
  }
  return RoleSetup.standard(players);
}

/// Checks a host's fixed deal and fills the rest with Civilians.
///
/// Throws [ArgumentError] when the deal cannot make a fair game (see
/// [RoleSetup.check]); its message is the problem's stable code.
Map<Role, int> resolveRoleCounts(int players, Map<Role, int>? fixed) {
  if (fixed == null) return defaultRoleCounts(players);
  final problem = RoleSetup.check(players, fixed);
  if (problem != null) throw ArgumentError(problem.code);
  return RoleSetup.fill(players, fixed);
}

/// Deals one role to each player, shuffled by [seed].
Map<UserId, Role> dealRoles(
  List<Player> players,
  Map<Role, int> counts,
  int seed,
) {
  final deck = <Role>[
    for (final r in Role.values)
      for (var i = 0; i < (counts[r] ?? 0); i++) r,
  ];
  SeededRandom(seed).shuffle(deck);
  final bySeat = [...players]..sort((a, b) => a.seat.compareTo(b.seat));
  return {for (var i = 0; i < bySeat.length; i++) bySeat[i].userId: deck[i]};
}
