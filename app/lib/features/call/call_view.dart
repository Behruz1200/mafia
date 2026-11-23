import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'call_providers.dart';
import 'call_state.dart';
import 'data/livekit_call_controller.dart';

/// Everyone in the call right now, with camera, mic and speaking state.
final callParticipantsProvider =
    StreamProvider.autoDispose<List<CallParticipant>>(
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

/// Stream 3 (video) owns this folder. LiveKit lives only in here.
///
/// The video is split in two so the game can put each player's camera in
/// their seat at the table:
///  * [CallControls] joins the room's call while it is on screen, follows
///    the game (muted at night, Mafia call for Mafia), says why when the
///    camera or mic is off, and has the camera and mic toggles.
///  * [SeatVideo] shows one player's camera, or a placeholder.
class CallControls extends ConsumerStatefulWidget {
  const CallControls({super.key, this.roomId});

  final RoomId? roomId;

  @override
  ConsumerState<CallControls> createState() => _CallControlsState();
}

class _CallControlsState extends ConsumerState<CallControls> {
  // Used only with the offline fake, which has no local state of its own.
  bool _fakeCamera = false;
  bool _fakeMic = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final roomId = widget.roomId;
    if (roomId != null) ref.watch(callSessionProvider(roomId));

    final call = ref.watch(callControllerProvider);
    final people = ref.watch(callParticipantsProvider).value ?? const [];
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

    final iAmOut =
        me != null &&
        (game?.players ?? const <Player>[]).any(
          (p) => p.userId == me && !p.isAlive,
        ) &&
        game?.phase != GamePhase.ended;
    final mafiaCall = local.activeChannel == CallChannel.mafia;
    final soundTap = local.audioBlocked && call is LiveKitCallController;
    final banner = switch (()) {
      _ when local.audioBlocked => t.callTapForSound,
      _ when local.mediaBlocked && kIsWeb => t.callMediaBlockedWeb,
      _ when local.mediaBlocked => t.callMediaBlocked,
      _ when mafiaCall => t.callMafiaPrivate,
      _ when game?.phase == GamePhase.night => t.callNightMuted,
      _ when game?.phase == GamePhase.lastWord && game?.lastWordBy == me =>
        t.callLastWordYou,
      _ when game?.phase == GamePhase.lastWord && game?.lastWordBy != null =>
        t.callLastWordListening(
          game!.players
                  .where((p) => p.userId == game.lastWordBy)
                  .firstOrNull
                  ?.displayName ??
              '…',
        ),
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

    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: banner == null
              ? const SizedBox.shrink()
              : GestureDetector(
                  key: const ValueKey('call-banner'),
                  behavior: HitTestBehavior.opaque,
                  // Browsers play sound only after a tap; this is that tap.
                  onTap: call is LiveKitCallController && soundTap
                      ? call.startAudio
                      : null,
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        soundTap
                            ? Icons.volume_up_rounded
                            : mafiaCall
                            ? Icons.lock_rounded
                            : game?.phase == GamePhase.night
                            ? Icons.bedtime_rounded
                            : Icons.info_outline_rounded,
                        size: 18,
                        color: soundTap || mafiaCall
                            ? Palette.accent
                            : Palette.muted,
                      ),
                      Expanded(
                        child: Text(
                          banner,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: soundTap || mafiaCall
                                ? Palette.text
                                : Palette.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        _toggle(
          key: const ValueKey('call-camera'),
          on: local.cameraOn,
          iconOn: Icons.videocam_rounded,
          iconOff: Icons.videocam_off_rounded,
          tooltip: local.cameraOn ? t.callTurnCameraOff : t.callTurnCameraOn,
          onPressed: local.canPublish ? toggleCamera : null,
        ),
        _toggle(
          key: const ValueKey('call-mic'),
          on: local.micOn,
          iconOn: Icons.mic_rounded,
          iconOff: Icons.mic_off_rounded,
          tooltip: local.micOn ? t.callTurnMicOff : t.callTurnMicOn,
          onPressed: local.canPublish ? toggleMic : null,
        ),
      ],
    );
  }
}

/// A big rounded camera or mic button: cyan while on.
IconButton _toggle({
  required Key key,
  required bool on,
  required IconData iconOn,
  required IconData iconOff,
  required String tooltip,
  required VoidCallback? onPressed,
}) {
  return IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(on ? iconOn : iconOff),
    style: IconButton.styleFrom(
      fixedSize: const Size(56, 52),
      backgroundColor: on ? Palette.cyan : Palette.surface,
      foregroundColor: on ? Palette.background : Palette.text,
      disabledBackgroundColor: Palette.surface.withValues(alpha: 0.6),
      disabledForegroundColor: Palette.muted.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

/// One player's camera, filling its box; [placeholder] when there is no
/// picture (camera off, not in the call, or night). A ring shows who is
/// talking.
class SeatVideo extends ConsumerWidget {
  const SeatVideo({
    super.key,
    required this.userId,
    required this.placeholder,
    this.radius = 18,
  });

  final UserId userId;
  final Widget placeholder;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callControllerProvider);
    final people = ref.watch(callParticipantsProvider).value ?? const [];
    final person = people.where((p) => p.userId == userId).firstOrNull;
    final video = person != null && person.cameraOn
        ? (call is LiveKitCallController ? call.videoTrackFor(userId) : null)
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (video != null)
          lk.VideoTrackRenderer(video, fit: lk.VideoViewFit.cover)
        else
          placeholder,
        if (person != null && person.isSpeaking)
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Palette.cyan, width: 3),
            ),
          ),
      ],
    );
  }
}
