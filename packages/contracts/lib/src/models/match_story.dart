import '../json.dart';
import 'ids.dart';

/// What really happened in a match, night by night and day by day. The app
/// plays it as the end-of-match cartoon, with roles from
/// `MatchResult.roles`.
///
/// It holds every secret night move, so the engine only builds it when the
/// match ends, on `MatchResult.story`.
class MatchStory {
  const MatchStory({this.nights = const [], this.days = const []});

  bool get isEmpty => nights.isEmpty && days.isEmpty;

  /// One entry per night that was resolved, oldest first.
  final List<StoryNight> nights;

  /// One entry per vote that was resolved, oldest first.
  final List<StoryVote> days;

  Json toJson() => {
    'nights': [for (final n in nights) n.toJson()],
    'days': [for (final d in days) d.toJson()],
  };

  factory MatchStory.fromJson(Json j) => MatchStory(
    nights: decodeList(j['nights'], StoryNight.fromJson),
    days: decodeList(j['days'], StoryVote.fromJson),
  );
}

/// One night's secret moves and their result.
class StoryNight {
  const StoryNight({
    required this.round,
    this.target,
    this.shooters = const [],
    this.doctorId,
    this.healed,
    this.saved = false,
    this.checks = const [],
  });

  final int round;

  /// Who the Mafia shot at, or null if they picked no one.
  final UserId? target;

  /// The Mafia members whose pick was [target].
  final List<UserId> shooters;

  /// The Doctor who picked someone tonight, and who they protected.
  final UserId? doctorId;
  final UserId? healed;

  /// True when the Doctor protected [target], so no one died.
  final bool saved;

  /// The Detective's and Don's checks, in the order they were made.
  final List<StoryCheck> checks;

  Json toJson() => {
    'round': round,
    'target': target,
    'shooters': shooters,
    'doctorId': doctorId,
    'healed': healed,
    'saved': saved,
    'checks': [for (final c in checks) c.toJson()],
  };

  factory StoryNight.fromJson(Json j) => StoryNight(
    round: j['round']! as int,
    target: j['target'] as String?,
    shooters: decodeStrings(j['shooters']),
    doctorId: j['doctorId'] as String?,
    healed: j['healed'] as String?,
    saved: j['saved'] as bool? ?? false,
    checks: decodeList(j['checks'], StoryCheck.fromJson),
  );
}

/// One night check. For the Detective, [found] means the target is Mafia;
/// for the Don, it means the target is the Detective.
class StoryCheck {
  const StoryCheck({
    required this.checkerId,
    required this.targetId,
    required this.byDon,
    required this.found,
  });

  final UserId checkerId;
  final UserId targetId;
  final bool byDon;
  final bool found;

  Json toJson() => {
    'checkerId': checkerId,
    'targetId': targetId,
    'byDon': byDon,
    'found': found,
  };

  factory StoryCheck.fromJson(Json j) => StoryCheck(
    checkerId: j['checkerId']! as String,
    targetId: j['targetId']! as String,
    byDon: j['byDon'] as bool? ?? false,
    found: j['found'] as bool? ?? false,
  );
}

/// One day's vote: who voted for whom, and who was voted out.
class StoryVote {
  const StoryVote({
    required this.round,
    this.votes = const {},
    this.votedOut,
    this.tied = false,
  });

  final int round;

  /// Voter -> target (null = skip). Only living voters who voted.
  final Map<UserId, UserId?> votes;

  /// Who left the table, or null if no one did.
  final UserId? votedOut;

  /// True when two or more players tied, so no one was out.
  final bool tied;

  Json toJson() => {
    'round': round,
    'votes': votes,
    'votedOut': votedOut,
    'tied': tied,
  };

  factory StoryVote.fromJson(Json j) => StoryVote(
    round: j['round']! as int,
    votes: (j['votes'] as Json? ?? const {}).map(
      (k, v) => MapEntry(k, v as String?),
    ),
    votedOut: j['votedOut'] as String?,
    tied: j['tied'] as bool? ?? false,
  );
}
