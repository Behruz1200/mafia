import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import 'comic_art.dart';
import 'story_scenes.dart';
import 'story_script.dart';

/// The "Watch the story" button on the results screen. The first time a
/// match's results show, it also opens the story by itself.
class MatchStoryButton extends StatefulWidget {
  const MatchStoryButton({
    super.key,
    required this.state,
    required this.result,
    this.me,
    this.autoOpen = true,
  });

  final PublicGameState state;
  final MatchResult result;
  final UserId? me;
  final bool autoOpen;

  /// Matches whose story already opened by itself, so it does not open
  /// again when the results screen rebuilds or comes back.
  static final _opened = <MatchId>{};

  @override
  State<MatchStoryButton> createState() => _MatchStoryButtonState();
}

class _MatchStoryButtonState extends State<MatchStoryButton> {
  @override
  void initState() {
    super.initState();
    final id = widget.result.matchId;
    if (widget.autoOpen &&
        !MatchStoryButton._opened.contains(id) &&
        storyScenes(widget.result).isNotEmpty) {
      MatchStoryButton._opened.add(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open();
      });
    }
  }

  void _open() => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => StoryPlayer(
        result: widget.result,
        cast: StoryCast(
          names: {
            for (final p in widget.state.players) p.userId: p.displayName,
          },
          roles: widget.result.roles,
          winners: widget.result.winners,
          me: widget.me,
        ),
      ),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (storyScenes(widget.result).isEmpty) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return FilledButton.icon(
      key: const Key('watch-story'),
      onPressed: _open,
      style: FilledButton.styleFrom(
        backgroundColor: Comic.yellow,
        foregroundColor: Comic.ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: Comic.ink, width: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.movie_filter_rounded),
      label: Text(t.storyWatch, style: Comic.lettersFor(t.storyWatch, 22)),
    );
  }
}

/// Plays the story scene by scene. Tap the picture to go to the next
/// scene; Skip jumps to the result.
class StoryPlayer extends StatefulWidget {
  const StoryPlayer({super.key, required this.result, required this.cast});

  final MatchResult result;
  final StoryCast cast;

  @override
  State<StoryPlayer> createState() => _StoryPlayerState();
}

class _StoryPlayerState extends State<StoryPlayer>
    with SingleTickerProviderStateMixin {
  late final List<StoryScene> _scenes = storyScenes(widget.result);
  late final AnimationController _clock = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);
  var _index = 0;

  bool get _last => _index == _scenes.length - 1;

  @override
  void initState() {
    super.initState();
    if (_scenes.isNotEmpty) _play(0);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _play(int i) {
    setState(() => _index = i);
    _clock
      ..duration = _scenes[i].duration
      ..forward(from: 0);
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && !_last) _play(_index + 1);
  }

  void _next() => _last ? _play(0) : _play(_index + 1);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_scenes.isEmpty) return const SizedBox.shrink();
    final scene = _scenes[_index];
    final text = sceneText(scene, widget.cast, t);
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: AnimatedBuilder(
                animation: _clock,
                builder: (context, _) {
                  final secs =
                      _clock.value *
                      (_clock.duration ?? scene.duration).inMilliseconds /
                      1000;
                  return Column(
                    children: [
                      _Bars(
                        count: _scenes.length,
                        index: _index,
                        progress: _clock.value,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Palette.surface,
                              border: Border.all(color: Palette.outline),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              text.label,
                              style: GameStyle.display(13, color: Colors.white),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            key: const Key('story-skip'),
                            onPressed: () =>
                                _last ? _play(0) : _play(_scenes.length - 1),
                            child: Text(_last ? t.storyReplay : t.storySkip),
                          ),
                          IconButton(
                            key: const Key('story-close'),
                            tooltip: t.storyClose,
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 8),
                            Flexible(
                              child: GestureDetector(
                                key: const Key('story-stage'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _next,
                                child: AspectRatio(
                                  aspectRatio:
                                      Comic.stageWidth / Comic.stageHeight,
                                  child: FittedBox(
                                    child: SceneStage(
                                      scene: scene,
                                      cast: widget.cast,
                                      t: secs,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: 118,
                                minWidth: double.infinity,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (i, c) in text.captions.indexed)
                                    if (secs >= c.at)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          left: i.isOdd ? 16 : 0,
                                          bottom: 8,
                                        ),
                                        child: _CaptionBox(
                                          text: c.text,
                                          tilt: i.isOdd ? 0.014 : -0.018,
                                          appear: ((secs - c.at) / 0.4).clamp(
                                            0.0,
                                            1.0,
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Story-style progress: one bar per scene.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.count,
    required this.index,
    required this.progress,
  });

  final int count;
  final int index;
  final double progress;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 4,
    children: [
      for (var i = 0; i < count; i++)
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: i < index ? 1 : (i == index ? progress : 0),
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
            ),
          ),
        ),
    ],
  );
}

/// A yellow comic caption box.
class _CaptionBox extends StatelessWidget {
  const _CaptionBox({
    required this.text,
    required this.tilt,
    required this.appear,
  });

  final String text;
  final double tilt;
  final double appear;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: appear,
    child: Transform.translate(
      offset: Offset(0, 8 * (1 - appear)),
      child: Transform.rotate(
        angle: tilt,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 3),
          decoration: const BoxDecoration(
            color: Comic.yellow,
            border: Border.fromBorderSide(
              BorderSide(color: Comic.ink, width: 3),
            ),
            borderRadius: BorderRadius.all(Radius.circular(4)),
            boxShadow: [BoxShadow(color: Comic.ink, offset: Offset(4, 4))],
          ),
          child: Text(text, style: Comic.lettersFor(text, 20)),
        ),
      ),
    ),
  );
}
