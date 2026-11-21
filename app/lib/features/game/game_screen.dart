import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../call/call_view.dart';

final _publicStateProvider = StreamProvider.family<PublicGameState, RoomId>(
  (ref, roomId) => ref.watch(roomRepositoryProvider).watchPublicState(roomId),
);

/// Stream 6 (game UI) owns this folder: the table, role card, night
/// actions, voting, results. It embeds the call from stream 3 and only
/// talks to the game through `RoomRepository`.
class GameScreen extends ConsumerWidget {
  const GameScreen({super.key, required this.roomId});

  final RoomId roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final state = ref.watch(_publicStateProvider(roomId)).value;
    final phase = switch (state?.phase) {
      GamePhase.night => t.phaseNight,
      GamePhase.day => t.phaseDay,
      GamePhase.voting => t.phaseVoting,
      _ => t.comingSoon,
    };
    return Scaffold(
      appBar: AppBar(title: Text(phase)),
      body: const Column(
        children: [
          Expanded(child: CallView()),
          // Stream 6: table, role card and action bar go here.
        ],
      ),
    );
  }
}
