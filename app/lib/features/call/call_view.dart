import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import 'call_providers.dart';
import 'call_state.dart';
import 'data/livekit_call_controller.dart';

final _participantsProvider = StreamProvider.autoDispose<List<CallParticipant>>(
  (ref) => ref.watch(callControllerProvider).watchParticipants(),
);

final _localProvider = StreamProvider.autoDispose<LocalCallState?>((ref) {
  final call = ref.watch(callControllerProvider);
  return call is TableCallController
      ? call.watchLocal()
      : Stream.value(null); // offline fake: the view keeps its own toggles
});

final _gameProvider = StreamProvider.autoDispose
    .family<PublicGameState, RoomId>(
      (ref, roomId) =>
          ref.watch(roomRepositoryProvider).watchPublicState(roomId),
    );

/// Stream 3 (video) owns this folder. The video grid with camera and mic
/// toggles, which the game screen embeds. LiveKit lives only in here.
///
/// Give it the [roomId] and it joins that room's call, follows the game
/// (muted at night, Mafia call for Mafia) and leaves when it goes away.
class CallView extends ConsumerStatefulWidget {
  const CallView({super.key, this.roomId});

  final RoomId? roomId;

  @override
  ConsumerState<CallView> createState() => _CallViewState();
}

class _CallViewState extends ConsumerState<CallView> {
  // Used only with the offline fake, which has no local state of its own.
  bool _fakeCamera = false;
  bool _fakeMic = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final roomId = widget.roomId;
    if (roomId != null) ref.watch(callSessionProvider(roomId));

    final call = ref.watch(callControllerProvider);
    final people = ref.watch(_participantsProvider).value ?? const [];
    final game = roomId == null ? null : ref.watch(_gameProvider(roomId)).value;
    final me = ref.watch(sessionProvider).value?.userId;
    final local =
        ref.watch(_localProvider).value ??
        LocalCallState(
          cameraOn: _fakeCamera,
          micOn: _fakeMic,
          canPublish: true,
          activeChannel: CallChannel.table,
          connected: people.isNotEmpty,
        );

    final players = {
      for (final p in game?.players ?? const <Player>[]) p.userId: p,
    };
    final iAmOut =
        me != null &&
        players[me]?.isAlive == false &&
        game?.phase != GamePhase.ended;
    final banner = switch (()) {
      _ when local.mediaBlocked => t.callMediaBlocked,
      _ when local.activeChannel == CallChannel.mafia => t.callMafiaPrivate,
      _ when game?.phase == GamePhase.night => t.callNightMuted,
      _ when iAmOut => t.callYouAreOut,
      _ when !local.connected => t.callConnecting,
      _ => null,
    };

    Future<void> toggleCamera() async {
      if (call is! TableCallController) {
        setState(() => _fakeCamera = !local.cameraOn);
      }
      await call.setCamera(on: !local.cameraOn);
    }

    Future<void> toggleMic() async {
      if (call is! TableCallController) {
        setState(() => _fakeMic = !local.micOn);
      }
      await call.setMic(on: !local.micOn);
    }

    final columns = people.length > 9 ? 4 : 3;
    return Column(
      children: [
        if (banner != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(banner, textAlign: TextAlign.center),
          ),
        Expanded(
          child: GridView.count(
            crossAxisCount: columns,
            childAspectRatio: 3 / 4,
            padding: const EdgeInsets.all(4),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final p in people)
                _Tile(
                  key: ValueKey(p.userId),
                  person: p,
                  name: p.userId == me
                      ? t.callYou
                      : players[p.userId]?.displayName ??
                            (call is LiveKitCallController
                                ? call.displayNameFor(p.userId)
                                : null) ??
                            p.userId,
                  isOut: players[p.userId]?.isAlive == false,
                  video: call is LiveKitCallController
                      ? call.videoTrackFor(p.userId)
                      : null,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                key: const ValueKey('call-camera'),
                icon: Icon(
                  local.cameraOn ? Icons.videocam : Icons.videocam_off,
                ),
                tooltip: local.cameraOn
                    ? t.callTurnCameraOff
                    : t.callTurnCameraOn,
                onPressed: local.canPublish ? toggleCamera : null,
              ),
              const SizedBox(width: 16),
              IconButton.filledTonal(
                key: const ValueKey('call-mic'),
                icon: Icon(local.micOn ? Icons.mic : Icons.mic_off),
                tooltip: local.micOn ? t.callTurnMicOff : t.callTurnMicOn,
                onPressed: local.canPublish ? toggleMic : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.person,
    required this.name,
    required this.isOut,
    this.video,
  });

  final CallParticipant person;
  final String name;
  final bool isOut;
  final lk.VideoTrack? video;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final video = this.video;
    final face = video != null && person.cameraOn
        ? lk.VideoTrackRenderer(video, fit: lk.VideoViewFit.cover)
        : Center(
            child: CircleAvatar(
              radius: 24,
              child: Text(name.isEmpty ? '?' : name.characters.first),
            ),
          );
    return Opacity(
      opacity: isOut ? 0.4 : 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: person.isSpeaking ? colors.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            face,
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: Row(
                children: [
                  if (!person.micOn)
                    const Icon(Icons.mic_off, size: 14, color: Colors.white),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        shadows: [Shadow(blurRadius: 2)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
