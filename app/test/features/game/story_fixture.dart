import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';

/// A three-round match won by the town, with every kind of scene: a save,
/// a kill, both kinds of check, a vote out, a tie and a quiet night.
MatchResult storyResult({String matchId = 'match_1'}) => MatchResult(
  roomId: 'room_1',
  matchId: matchId,
  stake: 100,
  winningTeam: Team.town,
  winners: const ['user_0', 'user_1', 'user_2', 'user_4', 'user_5', 'user_7'],
  losers: const ['user_3', 'user_6'],
  roles: const {
    'user_0': Role.civilian,
    'user_1': Role.detective,
    'user_2': Role.doctor,
    'user_3': Role.mafia,
    'user_4': Role.civilian,
    'user_5': Role.civilian,
    'user_6': Role.don,
    'user_7': Role.civilian,
  },
  story: const MatchStory(
    nights: [
      StoryNight(
        round: 1,
        target: 'user_4',
        shooters: ['user_3', 'user_6'],
        doctorId: 'user_2',
        healed: 'user_4',
        saved: true,
        checks: [
          StoryCheck(
            checkerId: 'user_6',
            targetId: 'user_5',
            byDon: true,
            found: false,
          ),
          StoryCheck(
            checkerId: 'user_1',
            targetId: 'user_3',
            byDon: false,
            found: true,
          ),
        ],
      ),
      StoryNight(
        round: 2,
        target: 'user_1',
        shooters: ['user_6'],
        doctorId: 'user_2',
        healed: 'user_5',
        checks: [
          StoryCheck(
            checkerId: 'user_6',
            targetId: 'user_1',
            byDon: true,
            found: true,
          ),
          StoryCheck(
            checkerId: 'user_1',
            targetId: 'user_7',
            byDon: false,
            found: false,
          ),
        ],
      ),
      StoryNight(round: 3),
    ],
    days: [
      StoryVote(
        round: 1,
        votes: {
          'user_0': 'user_3',
          'user_1': 'user_3',
          'user_2': 'user_3',
          'user_4': 'user_3',
          'user_5': 'user_3',
          'user_3': 'user_0',
          'user_6': null,
        },
        votedOut: 'user_3',
      ),
      StoryVote(
        round: 2,
        votes: {
          'user_0': 'user_6',
          'user_2': 'user_6',
          'user_6': 'user_0',
          'user_4': 'user_0',
        },
        tied: true,
      ),
      StoryVote(
        round: 3,
        votes: {
          'user_0': 'user_6',
          'user_2': 'user_6',
          'user_4': 'user_6',
          'user_6': 'user_0',
        },
        votedOut: 'user_6',
      ),
    ],
  ),
  endedAt: fixtureNow,
);
