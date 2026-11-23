import '../models/game_state.dart';
import '../models/phase.dart';
import '../models/player.dart';
import '../models/role.dart';
import '../models/room.dart';

/// A fixed clock time so fixtures are deterministic.
final fixtureNow = DateTime.utc(2026, 1, 1, 20);

const _names = [
  'Aziza', 'Bekzod', 'Dilnoza', 'Jasur', 'Kamola', 'Otabek', //
  'Sardor', 'Shahzoda', 'Timur', 'Umida', 'Zafar', 'Nilufar',
];

/// [count] players, seats 0..count-1, first one is host.
List<Player> samplePlayers([int count = 8]) => [
  for (var i = 0; i < count; i++)
    Player(
      userId: 'user_$i',
      displayName: _names[i % _names.length],
      seat: i,
      isHost: i == 0,
    ),
];

Room sampleRoom({int players = 8, int stake = 100}) => Room(
  id: 'room_1',
  inviteCode: 'K7QF2',
  hostId: 'user_0',
  status: RoomStatus.open,
  settings: RoomSettings(stake: stake),
  memberIds: [for (final p in samplePlayers(players)) p.userId],
  memberNames: {
    for (final p in samplePlayers(players)) p.userId: p.displayName,
  },
  createdAt: fixtureNow,
);

PublicGameState samplePublicState({
  GamePhase phase = GamePhase.day,
  int players = 8,
}) => PublicGameState(
  roomId: 'room_1',
  matchId: 'match_1',
  phase: phase,
  round: 1,
  phaseEndsAt: fixtureNow.add(const Duration(minutes: 2)),
  players: samplePlayers(players),
);

PrivatePlayerState samplePrivateState({Role role = Role.civilian}) =>
    PrivatePlayerState(
      userId: 'user_0',
      role: role,
      teammates: role.team == Team.mafia ? const ['user_3'] : const [],
    );
