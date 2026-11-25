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
      // The Hypnotist acts first: whoever they put to sleep did nothing.
      if ((n.hypnotistId, n.slept) case (final h?, final slept?)) {
        scenes.add(SleepScene(round: round, hypnotist: h, target: slept));
      }
      // Older stories only tell the Mafia's shot.
      final attacks = n.attacks.isNotEmpty || n.target == null
          ? n.attacks
          : [
              StoryAttack(
                shooters: n.shooters,
                target: n.target!,
                outcome: n.saved ? ShotOutcome.healed : ShotOutcome.died,
              ),
            ];
      if (attacks.isEmpty) {
        scenes.add(
          QuietNightScene(
            round: round,
            mafia: [
              for (final id in roles.keys)
                if (roles[id]!.team == Team.mafia && alive.contains(id)) id,
            ],
          ),
        );
      }
      for (final a in attacks) {
        // The Don leads, so the Don is the one shown holding the gun.
        final shooters = [...a.shooters]
          ..sort(
            (x, y) => (roles[x] == Role.don ? 0 : 1).compareTo(
              roles[y] == Role.don ? 0 : 1,
            ),
          );
        scenes.add(
          ShotScene(
            round: round,
            shooters: shooters,
            target: a.target,
            doctor: a.outcome == ShotOutcome.healed ? n.doctorId : null,
            bodyguard: a.bodyguardId,
            byManiac: a.byManiac,
            immortal: a.outcome == ShotOutcome.immortal,
          ),
        );
        if (a.outcome == ShotOutcome.died) alive.remove(a.hit);
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

/// The Mafia (or the Maniac, [byManiac]) shot at [target]. If [doctor] is
/// set, the Doctor saved whoever was hit. If [bodyguard] is set, they
/// stepped in front of [target] and took the shot. [immortal] means the
/// player hit shrugged it off.
class ShotScene extends StoryScene {
  const ShotScene({
    required this.round,
    required this.shooters,
    required this.target,
    this.doctor,
    this.bodyguard,
    this.byManiac = false,
    this.immortal = false,
  });

  final int round;
  final List<UserId> shooters;
  final UserId target;
  final UserId? doctor;
  final UserId? bodyguard;
  final bool byManiac;
  final bool immortal;

  bool get saved => doctor != null;

  /// The Doctor healed themself, and the shot was at them.
  bool get selfHeal => doctor != null && doctor == hit;

  /// Who the shot hit.
  UserId get hit => bodyguard ?? target;

  /// True when the player hit is out of the game.
  bool get killed => !saved && !immortal;

  @override
  Duration get duration => const Duration(milliseconds: 5200);
}

/// The Hypnotist put [target] to sleep for the night.
class SleepScene extends StoryScene {
  const SleepScene({
    required this.round,
    required this.hypnotist,
    required this.target,
  });

  final int round;
  final UserId hypnotist;
  final UserId target;

  @override
  Duration get duration => const Duration(milliseconds: 4200);
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
