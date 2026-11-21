import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

final _participantsProvider = StreamProvider<List<CallParticipant>>(
  (ref) => ref.watch(callControllerProvider).watchParticipants(),
);

/// Stream 3 (video) owns this folder. The video grid with camera and mic
/// toggles, which the game screen embeds. LiveKit lives only in here.
class CallView extends ConsumerWidget {
  const CallView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final call = ref.watch(callControllerProvider);
    final people = ref.watch(_participantsProvider).value ?? const [];
    return Column(
      children: [
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            children: [
              for (final p in people)
                Card(child: Center(child: Text(p.userId))),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.videocam),
              tooltip: t.camera,
              onPressed: () => call.setCamera(on: true),
            ),
            IconButton(
              icon: const Icon(Icons.mic),
              tooltip: t.microphone,
              onPressed: () => call.setMic(on: true),
            ),
          ],
        ),
      ],
    );
  }
}
