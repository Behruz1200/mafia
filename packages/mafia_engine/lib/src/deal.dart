import 'package:contracts/contracts.dart';

import 'rng.dart';

/// The fewest players a match can be dealt for.
const minPlayersForMatch = 4;

/// The deal used when the host does not fix one.
///
/// One Mafia member for every three players, but only one up to 6 players
/// (two Mafia against four town ends most 6-player games on day one). From
/// two Mafia members up, one of them is the Don. A Detective from 4 players and a
/// Doctor from 5. Everyone else is a Civilian.
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
Map<Role, int> defaultRoleCounts(int players) {
  if (players < minPlayersForMatch) {
    throw ArgumentError.value(
      players,
      'players',
      'need at least $minPlayersForMatch players',
    );
  }
  final mafiaTeam = players <= 6 ? 1 : players ~/ 3;
  final don = mafiaTeam >= 2 ? 1 : 0;
  final counts = <Role, int>{
    Role.don: don,
    Role.mafia: mafiaTeam - don,
    Role.detective: 1,
    Role.doctor: players >= 5 ? 1 : 0,
  };
  counts[Role.civilian] = players - counts.values.fold(0, (a, b) => a + b);
  return counts;
}

/// Checks a host's fixed deal and fills the rest with Civilians.
///
/// Throws [ArgumentError] when the deal cannot make a fair game: no Mafia,
/// more than one Don, Doctor or Detective, more roles than players, or a
/// Mafia team that would already be as big as the town.
Map<Role, int> resolveRoleCounts(int players, Map<Role, int>? fixed) {
  if (fixed == null) return defaultRoleCounts(players);
  if (players < minPlayersForMatch) {
    throw ArgumentError.value(
      players,
      'players',
      'need at least $minPlayersForMatch players',
    );
  }
  final counts = <Role, int>{
    for (final r in Role.values)
      if (r != Role.civilian) r: fixed[r] ?? 0,
  };
  for (final MapEntry(:key, :value) in counts.entries) {
    if (value < 0) throw ArgumentError('roleCounts[$key] is negative');
  }
  for (final r in [Role.don, Role.doctor, Role.detective]) {
    if (counts[r]! > 1) throw ArgumentError('at most one ${r.name}');
  }
  final mafiaTeam = counts[Role.mafia]! + counts[Role.don]!;
  if (mafiaTeam == 0) throw ArgumentError('the deal needs at least one Mafia');
  if (mafiaTeam * 2 >= players) {
    throw ArgumentError('the Mafia must be fewer than the town');
  }
  final special = counts.values.fold(0, (a, b) => a + b);
  if (special > players) throw ArgumentError('more roles than players');
  counts[Role.civilian] = players - special;
  return counts;
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
