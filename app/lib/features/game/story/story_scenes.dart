import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_text.dart';
import 'comic_art.dart';
import 'story_script.dart';

/// Who is in the story: names, roles, and who is watching.
class StoryCast {
  const StoryCast({
    required this.names,
    required this.roles,
    required this.winners,
    this.me,
  });

  final Map<UserId, String> names;
  final Map<UserId, Role> roles;
  final List<UserId> winners;
  final UserId? me;

  String name(UserId id) => names[id] ?? '?';
  Role role(UserId id) => roles[id] ?? Role.civilian;
}

/// A caption line and the second it appears at.
typedef Caption = ({double at, String text});

/// The chip label ("Night 1") and captions for [scene].
({String label, List<Caption> captions}) sceneText(
  StoryScene scene,
  StoryCast c,
  AppLocalizations t,
) => switch (scene) {
  ShotScene(:final round, :final target, :final doctor) => (
    label: t.storyNight(round),
    captions: [
      (
        at: 0.25,
        text: scene.byManiac
            ? t.storyManiacShotAt(c.name(target))
            : t.storyShotAt(c.name(target)),
      ),
      if (scene.bodyguard case final bodyguard?)
        (at: 1.9, text: t.storyGuarded(c.name(bodyguard))),
      (
        at: scene.bodyguard == null ? 2.1 : 3.3,
        text: doctor != null
            ? (scene.selfHeal
                  ? t.storySavedSelf(c.name(doctor))
                  : t.storySaved(c.name(doctor)))
            : scene.immortal
            ? t.storyImmortal(c.name(scene.hit))
            : t.storyKilled(c.name(scene.hit)),
      ),
    ],
  ),
  SleepScene(:final round, :final hypnotist, :final target) => (
    label: t.storyNight(round),
    captions: [
      (at: 0.25, text: t.storySlept(c.name(hypnotist), c.name(target))),
      (at: 2.2, text: t.storySleptLine),
    ],
  ),
  QuietNightScene(:final round) => (
    label: t.storyNight(round),
    captions: [(at: 0.25, text: t.storyNoShot)],
  ),
  CheckScene(:final round, :final check) => (
    label: t.storyNight(round),
    captions: [
      (
        at: 0.25,
        text: check.byDon
            ? t.storyDonCheck(c.name(check.checkerId), c.name(check.targetId))
            : t.storyCheck(c.name(check.checkerId), c.name(check.targetId)),
      ),
      (
        at: 2.0,
        text: switch ((check.byDon, check.found)) {
          (false, true) => t.storyCheckMafia,
          (false, false) => t.storyCheckTown,
          (true, true) => t.storyDonFound,
          (true, false) => t.storyDonMissed,
        },
      ),
    ],
  ),
  VoteScene(:final round, :final target, :final tied) => (
    label: t.storyDay(round),
    captions: target == null
        ? [(at: 0.25, text: tied ? t.storyVoteTied : t.storyNobodyOut)]
        : [
            (at: 0.25, text: t.storyVotedOut(c.name(target))),
            (at: 2.9, text: t.storyWasRole(t.roleName(c.role(target)))),
          ],
  ),
  FinaleScene(:final winner) => (
    label: t.storyResult,
    captions: [
      (
        at: 0.3,
        text: switch (winner) {
          Team.town => t.storyTownWinsLine,
          Team.mafia => t.storyMafiaWinsLine,
          Team.maniac => t.storyManiacWinsLine,
        },
      ),
    ],
  ),
};

/// The picture for [scene] at [t] seconds into it, on the 360 × 400 stage.
class SceneStage extends StatelessWidget {
  const SceneStage({
    super.key,
    required this.scene,
    required this.cast,
    required this.t,
  });

  final StoryScene scene;
  final StoryCast cast;
  final double t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final b = _Scene(cast, t, l);
    final children = switch (scene) {
      final ShotScene s => b.shot(s),
      final SleepScene s => b.sleep(s),
      final QuietNightScene s => b.quiet(s),
      final CheckScene s => b.check(s),
      final VoteScene s => b.vote(s),
      final FinaleScene s => b.finale(s),
    };
    return SizedBox(
      width: Comic.stageWidth,
      height: Comic.stageHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }
}

/// Overshooting ease, for things that pop in.
const _pop = Cubic(0.3, 1.4, 0.5, 1);
const _enter = Cubic(0.3, 1.25, 0.5, 1);

class _Scene {
  _Scene(this.c, this.t, this.l);

  final StoryCast c;
  final double t;
  final AppLocalizations l;

  static const _k = Comic.figureScale;
  static const _gy = Comic.ground;

  /// 0 → 1 as [t] runs from [start] for [dur] seconds.
  double p(double start, double dur, [Curve curve = Curves.linear]) =>
      curve.transform(((t - start) / dur).clamp(0.0, 1.0));

  double lerp(double a, double b, double v) => a + (b - a) * v;

  /// A gentle idle bob.
  double get bob => -4 * (0.5 - 0.5 * math.cos(2 * math.pi * t / 1.6));

  /// A side-to-side shake for [dur] seconds from [start].
  double shake(double start, double dur) {
    if (t < start || t > start + dur) return 0;
    return 5 *
        math.sin((t - start) * 2 * math.pi * 6) *
        (1 - (t - start) / dur);
  }

  /// [child] centred on (x, y).
  Widget at(double x, double y, Widget child) => Positioned(
    left: x,
    top: y,
    child: FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: child,
    ),
  );

  /// [child] popping in at [start], centred on (x, y).
  Widget popAt(
    double x,
    double y,
    double start,
    Widget child, {
    double dur = 0.4,
  }) {
    final v = p(start, dur, _pop);
    if (t < start) return const SizedBox.shrink();
    return at(
      x,
      y,
      Opacity(
        opacity: p(start, dur * 0.4),
        child: Transform.scale(scale: v, child: child),
      ),
    );
  }

  Widget figure(
    UserId id,
    double x, {
    bool left = false,
    ComicFace face = ComicFace.smile,
    double arm = armDown,
    ArmTool tool = ArmTool.none,
    Offset shift = Offset.zero,
    double angle = 0,
    double opacity = 1,
    double lift = 0,
    bool grey = false,
  }) {
    final role = c.role(id);
    Widget fig = Transform.translate(
      offset: Offset(0, bob + lift),
      child: ComicFigure(
        role: role,
        face: face,
        facingLeft: left,
        arm: arm,
        tool: tool,
      ),
    );
    if (grey) {
      fig = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.33, 0.59, 0.11, 0, 0, //
          0.33, 0.59, 0.11, 0, 0, //
          0.33, 0.59, 0.11, 0, 0, //
          0, 0, 0, 1, 0,
        ]),
        child: fig,
      );
    }
    return Positioned(
      left: x - ComicFigure.width / 2,
      top: _gy - ComicFigure.height,
      width: ComicFigure.width,
      child: Transform.translate(
        offset: shift,
        child: Transform.rotate(
          angle: angle,
          alignment: const Alignment(0, 0.6),
          child: Opacity(
            opacity: opacity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                fig,
                const SizedBox(height: 6),
                ComicNameTag(
                  name: c.name(id),
                  role: role,
                  roleName: l.roleName(role),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Slides in from the left (negative) or right (positive) side.
  Offset slideIn(double start, {bool fromRight = false}) =>
      Offset((fromRight ? 190 : -190) * (1 - p(start, 0.8, _enter)), 0);

  /// Drops in from the top of the panel.
  Offset dropIn(double start, [double dur = 0.55]) =>
      Offset(0, -330 * (1 - p(start, dur, Curves.easeOutBack)));

  double raise(double start) => lerp(armDown, armUp, p(start, 0.4, _pop));

  // ------------------------------------------------------------- scenes

  List<Widget> shot(ShotScene s) {
    final shooter = s.shooters.isNotEmpty ? s.shooters.first : null;
    const muzzleY = _gy - _k * 58;
    final guard = s.bodyguard;
    final killed = s.killed;
    final fall = killed ? p(1.85, 0.4, Curves.easeOut) : 0.0;
    // The bullet stops at the shield, the Bodyguard, or the target.
    final bulletEnd = s.saved || s.immortal
        ? 172.0
        : guard != null
        ? 214.0
        : 276.0;
    final bulletDur = s.saved || s.immortal ? 0.3 : 0.4;
    final bullet = p(1.45, bulletDur);
    final ghostX = guard != null ? 238.0 : 318.0;
    return [
      const ComicBackdrop(Backdrop.night),
      figure(
        s.target,
        310,
        left: true,
        // Saved players cheer up once the shield has caught the bullet.
        face: s.saved && t > 2.15 ? ComicFace.smile : ComicFace.scared,
        // A Doctor who healed themself is drawn once, pointing at the shield.
        arm: s.selfHeal ? lerp(armDown, -0.35, p(1.15, 0.4, _pop)) : armDown,
        tool: s.selfHeal ? ArmTool.point : ArmTool.none,
        shift:
            slideIn(0.1, fromRight: true) +
            Offset(guard == null ? shake(1.45, 0.9) : 0, 0),
        angle: guard == null ? fall * 0.35 : 0,
        opacity: guard == null ? 1 - fall * 0.45 : 1,
        grey: guard == null && killed && t > 1.9,
      ),
      if (guard != null)
        figure(
          guard,
          230,
          left: true,
          face: ComicFace.scared,
          arm: armUp - 0.4,
          shift: dropIn(0.9) + Offset(shake(1.85, 0.6), 0),
          angle: fall * 0.35,
          // Hidden until it drops, so its name tag doesn't hang in the sky.
          opacity: t < 0.9 ? 0 : 1 - fall * 0.45,
          grey: killed && t > 1.9,
        ),
      if (shooter != null)
        figure(
          shooter,
          50,
          face: ComicFace.smirk,
          arm: raise(1.0),
          tool: ArmTool.gun,
          shift: slideIn(0.2),
        ),
      if (s.doctor case final doctor? when guard == null && !s.selfHeal)
        figure(
          doctor,
          244,
          left: true,
          arm: -0.35,
          tool: ArmTool.point,
          shift: dropIn(1.15),
          opacity: t < 1.15 ? 0 : 1,
        ),
      if (s.saved || s.immortal)
        popAt(200, muzzleY, 1.55, const ComicShield(), dur: 0.3),
      if (t >= 1.45 && bullet < 1)
        Positioned(
          left: lerp(140, bulletEnd, bullet),
          top: muzzleY - 4,
          child: Container(
            width: 14,
            height: 7,
            decoration: BoxDecoration(
              color: Comic.yellow,
              border: Border.all(color: Comic.ink, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      popAt(150, muzzleY - 48, 1.38, ComicBurst(l.storyBang), dur: 0.35),
      if (s.saved)
        popAt(
          232,
          110,
          2.15,
          ComicWord(l.storySavedWord, color: Palette.cyan, maxWidth: 224),
        ),
      if (s.immortal)
        popAt(
          232,
          110,
          2.15,
          ComicWord(
            l.roleName(Role.immortal).toUpperCase(),
            color: Palette.gold,
            maxWidth: 224,
          ),
        ),
      if (killed && t > 2.3)
        at(
          ghostX,
          _gy - 150 - 60 * p(2.3, 1.6, Curves.easeOut),
          Opacity(
            opacity: (1 - p(3.2, 0.7)) * p(2.3, 0.3),
            child: const ComicGhost(),
          ),
        ),
    ];
  }

  List<Widget> sleep(SleepScene s) {
    final drowsy = p(1.4, 0.8, Curves.easeOut);
    return [
      const ComicBackdrop(Backdrop.night),
      figure(
        s.hypnotist,
        80,
        face: ComicFace.smirk,
        arm: raise(0.8),
        tool: ArmTool.point,
        shift: slideIn(0.2),
      ),
      // Rings drift from the Hypnotist's hand to the target.
      for (var i = 0; i < 3; i++)
        if (t > 0.9 + i * 0.25)
          at(
            lerp(150, 270, p(0.9 + i * 0.25, 0.9)),
            _gy - _k * 70,
            Opacity(
              opacity: 1 - p(1.6 + i * 0.25, 0.3),
              child: Container(
                width: 26.0 + i * 6,
                height: 26.0 + i * 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Palette.lavender, width: 4),
                ),
              ),
            ),
          ),
      figure(
        s.target,
        290,
        left: true,
        face: t > 1.6 ? ComicFace.smile : ComicFace.scared,
        shift: slideIn(0.1, fromRight: true),
        angle: drowsy * 0.18,
      ),
      for (var i = 0; i < 3; i++)
        popAt(
          300 + i * 16.0,
          110 - i * 26.0,
          1.9 + i * 0.3,
          ComicWord('Z', color: Palette.lavender, size: 26.0 + i * 8),
        ),
    ];
  }

  List<Widget> quiet(QuietNightScene s) {
    final shown = s.mafia.take(2).toList();
    final xs = shown.length == 1 ? const [180.0] : const [120.0, 240.0];
    return [
      const ComicBackdrop(Backdrop.night),
      for (var i = 0; i < shown.length; i++)
        figure(
          shown[i],
          xs[i],
          left: i == 1,
          face: ComicFace.smirk,
          arm: armDown - 0.6 * p(0.9, 0.3),
          shift: slideIn(0.15 + i * 0.1, fromRight: i == 1),
        ),
      for (var i = 0; i < shown.length; i++)
        popAt(
          xs[i],
          120,
          1.0 + i * 0.25,
          const ComicWord('?', color: Comic.yellow, size: 48),
        ),
    ];
  }

  List<Widget> check(CheckScene s) {
    final ch = s.check;
    const lensX = 70 + _k * 64, lensY = _gy - _k * 66;
    final sweep = p(0.95, 0.7, Curves.easeOut);
    final question = t < 1.2 ? 0.0 : (t < 2.2 ? 1.0 : 1 - p(2.2, 0.3));
    final cardRole = ch.byDon
        ? (ch.found ? Role.detective : null)
        : (ch.found ? Role.mafia : Role.civilian);
    final cardLabel = ch.byDon
        ? l.roleName(Role.detective)
        : l.teamName(ch.found ? Team.mafia : Team.town);
    return [
      const ComicBackdrop(Backdrop.night),
      Positioned(
        left: lensX,
        top: lensY - 75,
        child: Opacity(
          opacity: sweep * 0.85,
          child: Transform.rotate(
            angle: (1 - sweep) * -0.5,
            alignment: Alignment.centerLeft,
            child: const ComicBeam(length: 122),
          ),
        ),
      ),
      figure(
        ch.targetId,
        290,
        left: true,
        face: ch.found ? ComicFace.scared : ComicFace.smile,
        shift:
            slideIn(0.1, fromRight: true) +
            Offset(ch.found ? shake(2.05, 1.2) : 0, 0),
      ),
      figure(
        ch.checkerId,
        70,
        face: ch.byDon ? ComicFace.smirk : ComicFace.smile,
        arm: raise(0.75),
        tool: ArmTool.lens,
        shift: slideIn(0.25),
      ),
      if (question > 0)
        at(
          290,
          150,
          Opacity(
            opacity: question,
            child: const ComicWord('?', color: Comic.yellow, size: 46),
          ),
        ),
      if (t >= 1.9)
        at(
          290,
          100,
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(
              p(1.9, 0.45, Curves.easeOut),
              1,
              1,
            ),
            child: ComicRoleCard(role: cardRole, label: cardLabel),
          ),
        ),
      if (ch.found)
        popAt(200, 90, 2.25, const ComicWord('!', color: Comic.red, size: 64)),
    ];
  }

  List<Widget> vote(VoteScene s) {
    final shown = s.voters.take(3).toList();
    final extra = s.voters.length - shown.length;
    const xs = [40.0, 110.0, 180.0];
    final target = s.target;
    final kick = p(2.55, 0.7, const Cubic(0.5, 0, 0.8, 0.6));
    return [
      const ComicBackdrop(Backdrop.day),
      for (var i = 0; i < shown.length; i++)
        figure(
          shown[i],
          xs[i],
          arm: target == null
              ? armDown - 0.7 * p(0.8 + i * 0.15, 0.3)
              : raise(0.85 + i * 0.15),
          tool: ArmTool.point,
          shift: slideIn(0.1 + i * 0.15),
        ),
      if (target != null) ...[
        figure(
          target,
          300,
          left: true,
          face: ComicFace.scared,
          shift: Offset(230 * kick + shake(1.9, 0.6), -140 * kick),
          angle: kick * 2.8,
        ),
        for (var i = 0; i < shown.length; i++)
          if (t >= 1.25 + i * 0.22)
            () {
              final v = p(1.25 + i * 0.22, 0.55, Curves.easeOut);
              final from = Offset(xs[i] + _k * 48, _gy - _k * 54);
              final to = Offset(300 + (i - 1) * 24.0, _gy - _k * 150);
              final pos = Offset.lerp(from, to, v)!;
              return at(
                pos.dx,
                pos.dy,
                Opacity(
                  opacity: p(1.25 + i * 0.22, 0.12),
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * v,
                    child: const VoteToken(),
                  ),
                ),
              );
            }(),
        if (extra > 0)
          popAt(
            248,
            _gy - _k * 150,
            2.0,
            InkedText(
              '+$extra',
              style: Comic.letters(20, color: Comic.paper),
              strokeWidth: 4,
            ),
          ),
        if (t >= 2.75)
          at(
            296,
            _gy - 70,
            Opacity(
              opacity: p(2.75, 0.15),
              child: Transform.rotate(
                angle: -14 * math.pi / 180,
                child: Transform.scale(
                  scale: lerp(2.6, 1, p(2.75, 0.4, Curves.easeOutBack)),
                  child: ComicWord(
                    l.storyOutWord,
                    color: Comic.red,
                    size: 44,
                    maxWidth: 112,
                  ),
                ),
              ),
            ),
          ),
        popAt(
          296,
          _gy - 180,
          3.05,
          ComicRoleCard(
            role: c.role(target),
            label: l.roleName(c.role(target)),
          ),
        ),
      ] else ...[
        popAt(
          290,
          150,
          1.0,
          const ComicWord('?', color: Comic.paper, size: 56),
        ),
        popAt(
          250,
          110,
          1.3,
          const ComicWord('?', color: Comic.yellow, size: 40),
        ),
      ],
    ];
  }

  List<Widget> finale(FinaleScene s) {
    final shown = s.team.take(3).toList();
    final xs = switch (shown.length) {
      1 => const [180.0],
      2 => const [130.0, 230.0],
      _ => const [84.0, 180.0, 276.0],
    };
    final me = c.me;
    final iPlayed = me != null && c.roles.containsKey(me);
    final iWon = iPlayed && c.winners.contains(me);
    final town = s.winner == Team.town;
    return [
      ComicBackdrop(town ? Backdrop.townWin : Backdrop.mafiaWin),
      ComicConfetti(t: t),
      for (var i = 0; i < shown.length; i++)
        () {
          final d = 0.4 + i * 0.15;
          final jumping = t > d + 0.5;
          final phase = jumping ? ((t - d - 0.5) % 0.7) / 0.7 : 0.0;
          return figure(
            shown[i],
            xs[i],
            left: xs[i] > 180,
            face: town ? ComicFace.smile : ComicFace.smirk,
            arm: jumping ? armUp - 0.9 : armDown,
            shift: dropIn(d - 0.3, 0.5),
            opacity: t < d - 0.3 ? 0 : 1,
            lift: -34 * math.sin(math.pi * phase),
          );
        }(),
      popAt(
        180,
        56,
        0.35,
        ComicWord(
          switch (s.winner) {
            Team.town => l.gameResultTownWins,
            Team.mafia => l.gameResultMafiaWins,
            Team.maniac => l.gameResultManiacWins,
          }.toUpperCase(),
          color: Comic.yellow,
          size: 38,
          maxWidth: 330,
        ),
      ),
      if (iPlayed)
        popAt(
          180,
          104,
          1.3,
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
            decoration: BoxDecoration(
              color: iWon ? Palette.gold : Comic.paper,
              border: Border.all(color: Comic.ink, width: 3.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              (iWon ? l.gameResultYouWon : l.gameResultYouLost).toUpperCase(),
              style: Comic.lettersFor(
                (iWon ? l.gameResultYouWon : l.gameResultYouLost),
                20,
              ),
            ),
          ),
        ),
    ];
  }
}
