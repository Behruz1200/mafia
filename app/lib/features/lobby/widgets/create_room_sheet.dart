import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../game/ui/game_style.dart';

/// Stakes the host can pick. 0 is a free game. The server still checks
/// every player's age, region and balance at match start.
const stakeOptions = [0, 50, 100, 250, 500];

/// Asks the host how the room should be set up. Returns null on cancel.
Future<RoomSettings?> showCreateRoomSheet(
  BuildContext context, {
  required int available,
  required bool canStake,
}) {
  return showModalBottomSheet<RoomSettings>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GameStyle.felt,
    showDragHandle: true,
    builder: (_) => CreateRoomSheet(available: available, canStake: canStake),
  );
}

class CreateRoomSheet extends StatefulWidget {
  const CreateRoomSheet({
    super.key,
    required this.available,
    required this.canStake,
  });

  /// The player's coins, to grey out stakes they cannot afford.
  final int available;

  /// False until the player has passed the 18+ check.
  final bool canStake;

  @override
  State<CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<CreateRoomSheet> {
  var _stake = 0;
  var _maxPlayers = 10;
  var _public = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              t.createRoom,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(t.lobbyStake, style: const TextStyle(color: GameStyle.muted)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in stakeOptions)
                  ChoiceChip(
                    key: ValueKey('stake-$s'),
                    label: Text(s == 0 ? t.lobbyStakeFree : t.coins(s)),
                    avatar: s == 0
                        ? null
                        : const Icon(
                            Icons.toll,
                            size: 16,
                            color: GameStyle.gold,
                          ),
                    selected: _stake == s,
                    onSelected:
                        s == 0 || (widget.canStake && widget.available >= s)
                        ? (_) => setState(() => _stake = s)
                        : null,
                  ),
              ],
            ),
            Text(
              !widget.canStake
                  ? t.lobbyStakeAdultsOnly
                  : _stake > widget.available
                  ? t.lobbyNotEnoughCoins
                  : t.lobbyStakeHint,
              style: const TextStyle(color: GameStyle.muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              t.lobbyMaxPlayers(_maxPlayers),
              style: const TextStyle(color: GameStyle.muted),
            ),
            Slider(
              value: _maxPlayers.toDouble(),
              min: 6,
              max: 12,
              divisions: 6,
              label: '$_maxPlayers',
              onChanged: (v) => setState(() => _maxPlayers = v.round()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.lobbyPublicRoom),
              subtitle: Text(t.lobbyPublicRoomHint),
              value: _public,
              onChanged: (v) => setState(() => _public = v),
            ),
            const SizedBox(height: 4),
            FilledButton(
              key: const ValueKey('createRoomConfirm'),
              style: FilledButton.styleFrom(
                backgroundColor: GameStyle.crimson,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.pop(
                context,
                RoomSettings(
                  maxPlayers: _maxPlayers,
                  stake: _stake,
                  visibility: _public
                      ? RoomVisibility.public
                      : RoomVisibility.private,
                ),
              ),
              child: Text(t.lobbyCreate),
            ),
          ],
        ),
      ),
    );
  }
}
