import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('the match result tells the story of every night and vote', () {
    final t = Table();
    final don = t.one(Role.don);
    final mafia = t.one(Role.mafia);
    final detective = t.one(Role.detective);
    final doctor = t.one(Role.doctor);
    final civilians = t.all(Role.civilian);

    // Night 1: the Mafia shoot civilian 0, the Doctor saves them; the
    // Detective finds the Mafia; the Don checks a civilian.
    t.toNight();
    t.act(NightKill(actorId: don, targetId: civilians[0]));
    t.act(NightKill(actorId: mafia, targetId: civilians[0]));
    t.act(NightHeal(actorId: doctor, targetId: civilians[0]));
    t.act(NightCheck(actorId: don, targetId: civilians[1]));
    t.act(NightCheck(actorId: detective, targetId: mafia));
    expect(t.phase, GamePhase.day);

    // Day 1: everyone votes the Mafia out except the Don, who skips.
    t.toVoting();
    for (final p in t.state.public.alive.toList()) {
      if (p.userId == mafia) continue;
      t.act(
        CastVote(actorId: p.userId, targetId: p.userId == don ? null : mafia),
      );
    }
    t.act(CastVote(actorId: mafia, targetId: civilians[2]));
    expect(t.isAlive(mafia), isFalse);

    // Night 2: the Don shoots the Detective; nobody saves them.
    expect(t.phase, GamePhase.night);
    t.act(NightKill(actorId: don, targetId: detective));
    t.act(NightHeal(actorId: doctor, targetId: civilians[3]));
    t.act(NightCheck(actorId: don, targetId: detective));
    t.act(NightCheck(actorId: detective, targetId: don));
    expect(t.isAlive(detective), isFalse);

    // Day 2: the town votes the Don out and wins.
    t.toVoting();
    for (final p in t.state.public.alive.toList()) {
      t.act(
        CastVote(
          actorId: p.userId,
          targetId: p.userId == don ? civilians[0] : don,
        ),
      );
    }
    expect(t.phase, GamePhase.ended);

    final story = t.result!.story!;
    expect(story.nights, hasLength(2));
    expect(story.days, hasLength(2));

    final n1 = story.nights[0];
    expect(n1.round, 1);
    expect(n1.target, civilians[0]);
    expect(n1.shooters, unorderedEquals([don, mafia]));
    expect(n1.doctorId, doctor);
    expect(n1.healed, civilians[0]);
    expect(n1.saved, isTrue);
    expect(n1.checks, hasLength(2));
    final detCheck = n1.checks.firstWhere((c) => c.checkerId == detective);
    expect(detCheck.targetId, mafia);
    expect(detCheck.byDon, isFalse);
    expect(detCheck.found, isTrue);
    final donCheck = n1.checks.firstWhere((c) => c.checkerId == don);
    expect(donCheck.byDon, isTrue);
    expect(donCheck.found, isFalse);

    final d1 = story.days[0];
    expect(d1.round, 1);
    expect(d1.votedOut, mafia);
    expect(d1.votes[don], isNull);
    expect(d1.votes.containsKey(don), isTrue);
    expect(d1.votes[mafia], civilians[2]);

    final n2 = story.nights[1];
    expect(n2.target, detective);
    expect(n2.saved, isFalse);
    expect(n2.healed, civilians[3]);
    expect(
      n2.checks.firstWhere((c) => c.checkerId == don).found,
      isTrue,
      reason: 'the Don found the Detective',
    );
    // A checker killed tonight still had their check resolved.
    expect(n2.checks.firstWhere((c) => c.checkerId == detective).found, isTrue);

    expect(story.days[1].votedOut, don);

    // The story survives the trip to the app.
    final back = MatchResult.fromJson(t.result!.toJson()).story!;
    expect(back.toJson(), story.toJson());
  });

  test('a tied vote is part of the story', () {
    final t = Table();
    final civilians = t.all(Role.civilian);
    t.toNight();
    t.timeout();
    t.toVoting();
    final alive = t.state.public.alive.map((p) => p.userId).toList();
    for (var i = 0; i < alive.length; i++) {
      t.act(
        CastVote(
          actorId: alive[i],
          targetId: i.isEven
              ? (alive[i] == civilians[0] ? civilians[1] : civilians[0])
              : (alive[i] == civilians[1] ? civilians[0] : civilians[1]),
        ),
      );
    }
    final mem = t.state.engineData['days']! as List;
    expect(mem, hasLength(1));
    final day = StoryVote.fromJson(mem.single as Json);
    expect(day.tied, isTrue);
    expect(day.votedOut, isNull);
    final night = StoryNight.fromJson(
      (t.state.engineData['nights']! as List).single as Json,
    );
    expect(night.target, isNull);
    expect(night.saved, isFalse);
  });
}
