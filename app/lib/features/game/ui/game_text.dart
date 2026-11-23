import 'package:contracts/contracts.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Turns contract values (roles, teams, log keys) into the player's
/// language. The server only ever sends stable keys, never text.
extension GameText on AppLocalizations {
  String roleName(Role role) => switch (role) {
    Role.civilian => gameRoleCivilian,
    Role.doctor => gameRoleDoctor,
    Role.detective => gameRoleDetective,
    Role.mafia => gameRoleMafia,
    Role.don => gameRoleDon,
  };

  String roleGoal(Role role) => switch (role) {
    Role.civilian => gameRoleCivilianGoal,
    Role.doctor => gameRoleDoctorGoal,
    Role.detective => gameRoleDetectiveGoal,
    Role.mafia => gameRoleMafiaGoal,
    Role.don => gameRoleDonGoal,
  };

  String teamName(Team team) => switch (team) {
    Team.town => gameTeamTown,
    Team.mafia => gameTeamMafia,
  };

  String phaseName(GamePhase phase) => switch (phase) {
    GamePhase.lobby => gameWaitingTitle,
    GamePhase.roleReveal => gamePhaseRoleReveal,
    GamePhase.night => phaseNight,
    GamePhase.day => phaseDay,
    GamePhase.voting => phaseVoting,
    GamePhase.ended => gamePhaseEnded,
  };

  /// One log line, or null for keys this version of the app does not know
  /// (so a newer server never shows players a raw key).
  String? eventText(PublicEvent e, String Function(UserId) nameOf) {
    final name = e.userId == null ? '' : nameOf(e.userId!);
    return switch (e.message) {
      'eliminated' => switch (e.cause) {
        EliminationCause.killedAtNight => gameEventKilled(name),
        EliminationCause.votedOut => gameEventVotedOut(name),
        EliminationCause.leftMatch => gameEventLeft(name),
        null => null,
      },
      'nobodyDied' => gameEventNobodyDied,
      'voteTied' => gameEventVoteTied,
      'phaseSkipped' => gameEventPhaseSkipped,
      _ => null,
    };
  }
}
