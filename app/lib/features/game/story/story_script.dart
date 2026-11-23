import 'package:contracts/contracts.dart';

/// Turns a finished match into the list of scenes the story plays: for each
/// round, the Mafia's shot, then the night checks, then the day's vote, and
/// last the result.
///
/// Pure data, so it is easy to test; the drawing lives in `story_scenes`.
List<StoryScene> storyScenes(MatchResult result) {
  final story = result.story;
  if (story == null || result.roles.isEmpty || story.isEmpty) return const [];
  final roles = result.roles;

  // Who is still at the table, so a quiet night shows a living Mafia.
  final alive = {...roles.keys};
  final scenes = <StoryScene>[];
  final rounds = {
    for (final n in story.nights) n.round,
    for (final d in story.days) d.round,
  }.toList()..sort();

  for (final round in rounds) {
    for (final n in story.nights.where((n) => n.round == round)) {
      final target = n.target;
      if (target == null) {
        scenes.add(
          QuietNightScene(
            round: round,
            mafia: [
              for (final id in roles.keys)
                if (roles[id]!.team == Team.mafia && alive.contains(id)) id,
            ],
          ),
        );
      } else {
        // The Don leads, so the Don is the one shown holding the gun.
        final shooters = [...n.shooters]
          ..sort(
            (a, b) => (roles[a] == Role.don ? 0 : 1).compareTo(
              roles[b] == Role.don ? 0 : 1,
            ),
          );
        scenes.add(
          ShotScene(
            round: round,
            shooters: shooters,
            target: target,
            doctor: n.saved ? n.doctorId : null,
          ),
        );
        if (!n.saved) alive.remove(target);
      }
      // The Detective's check first, then the Don's.
      final checks = [...n.checks]
        ..sort((a, b) => (a.byDon ? 1 : 0).compareTo(b.byDon ? 1 : 0));
      for (final c in checks) {
        scenes.add(CheckScene(round: round, check: c));
      }
    }
    for (final d in story.days.where((d) => d.round == round)) {
      final out = d.votedOut;
      scenes.add(
        VoteScene(
          round: round,
          target: out,
          tied: d.tied,
          voters: [
            for (final MapEntry(key: voter, value: target) in d.votes.entries)
              if (target != null && (out == null || target == out)) voter,
          ],
        ),
      );
      if (out != null) alive.remove(out);
    }
  }

  final winner = result.winningTeam;
  if (winner != null) {
    final team = [
      for (final id in roles.keys)
        if (roles[id]!.team == winner) id,
    ];
    // Survivors first: they are the ones celebrating.
    team.sort(
      (a, b) =>
          (alive.contains(a) ? 0 : 1).compareTo(alive.contains(b) ? 0 : 1),
    );
    scenes.add(FinaleScene(winner: winner, team: team));
  }
  return scenes;
}

sealed class StoryScene {
  const StoryScene();

  /// How long the scene plays before the next one starts.
  Duration get duration;
}

/// The Mafia shot at [target]. If [doctor] is set, the Doctor saved them.
class ShotScene extends StoryScene {
  const ShotScene({
    required this.round,
    required this.shooters,
    required this.target,
    this.doctor,
  });

  final int round;
  final List<UserId> shooters;
  final UserId target;
  final UserId? doctor;

  bool get saved => doctor != null;

  @override
  Duration get duration => const Duration(milliseconds: 5200);
}

/// The Mafia picked no one.
class QuietNightScene extends StoryScene {
  const QuietNightScene({required this.round, required this.mafia});

  final int round;
  final List<UserId> mafia;

  @override
  Duration get duration => const Duration(milliseconds: 3800);
}

/// The Detective (or the Don) checked someone.
class CheckScene extends StoryScene {
  const CheckScene({required this.round, required this.check});

  final int round;
  final StoryCheck check;

  @override
  Duration get duration => const Duration(milliseconds: 5000);
}

/// The day's vote. [target] is who was voted out, or null if no one was;
/// [voters] are those who voted for them (or for anyone, if no one left).
class VoteScene extends StoryScene {
  const VoteScene({
    required this.round,
    required this.voters,
    this.target,
    this.tied = false,
  });

  final int round;
  final List<UserId> voters;
  final UserId? target;
  final bool tied;

  @override
  Duration get duration => Duration(milliseconds: target == null ? 3800 : 5400);
}

/// Who won, with the winning team celebrating.
class FinaleScene extends StoryScene {
  const FinaleScene({required this.winner, required this.team});

  final Team winner;
  final List<UserId> team;

  @override
  Duration get duration => const Duration(milliseconds: 5500);
}
