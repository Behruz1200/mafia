import 'package:contracts/contracts.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../ui/game_style.dart';
import '../ui/game_text.dart';

/// The order roles are listed in, by side.
const _mafiaSide = [Role.don, Role.mafia];
const _ownSide = [Role.maniac];
const _townSide = [
  Role.detective,
  Role.doctor,
  Role.bodyguard,
  Role.hypnotist,
  Role.immortal,
];
const _shownOrder = [..._mafiaSide, ..._ownSide, ..._townSide, Role.civilian];

/// How many players the deal is shown for: who is seated, but never fewer
/// than the room needs to start.
int dealSize(Room room, int seated) {
  final min = room.settings.minPlayers < RoleSetup.minPlayers
      ? RoleSetup.minPlayers
      : room.settings.minPlayers;
  return seated < min ? min : seated;
}

/// The waiting room's "Roles in this game" panel. Everyone sees the roles
/// the match will be dealt; the host also gets Edit (in rooms joined by
/// code). Tapping a role explains it.
class RoleSetupPanel extends StatefulWidget {
  const RoleSetupPanel({
    super.key,
    required this.room,
    required this.seated,
    required this.isHost,
    this.onSetRoles,
  });

  final Room room;
  final int seated;
  final bool isHost;

  /// Saves the host's pick (null: standard deal). Null hides Edit.
  final Future<void> Function(Map<Role, int>? roleCounts)? onSetRoles;

  @override
  State<RoleSetupPanel> createState() => _RoleSetupPanelState();
}

class _RoleSetupPanelState extends State<RoleSetupPanel> {
  @override
  void didUpdateWidget(RoleSetupPanel old) {
    super.didUpdateWidget(old);
    // Tell the other players when the host changes the roles.
    final before = old.room.settings.roleCounts;
    final now = widget.room.settings.roleCounts;
    if (!widget.isHost &&
        old.room.id == widget.room.id &&
        !_sameCounts(before, now)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).gameRolesChanged),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final room = widget.room;
    final fixed = room.settings.roleCounts;
    final n = dealSize(room, widget.seated);
    final counts = RoleSetup.deal(n, fixed);
    final problem = fixed == null ? null : RoleSetup.check(n, fixed);
    final canEdit =
        widget.isHost &&
        widget.onSetRoles != null &&
        room.settings.visibility == RoomVisibility.private;

    return GamePanel(
      key: const ValueKey('role-setup-panel'),
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      t.gameRolesTitle.toUpperCase(),
                      style: const TextStyle(
                        color: GameStyle.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      fixed == null
                          ? t.gameRolesStandardLine
                          : widget.isHost
                          ? t.gameRolesByYou
                          : t.gameRolesByHost,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                TextButton.icon(
                  key: const ValueKey('edit-roles'),
                  style: TextButton.styleFrom(
                    foregroundColor: GameStyle.gold,
                    backgroundColor: GameStyle.feltLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(
                    t.gameRolesEdit,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onPressed: () async {
                    final picked = await showRolePicker(
                      context,
                      room: room,
                      seated: widget.seated,
                    );
                    if (picked != null) await widget.onSetRoles!(picked.counts);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final r in _shownOrder)
                if ((counts[r] ?? 0) > 0)
                  RoleChip(
                    role: r,
                    count: counts[r]!,
                    onTap: () => showRoleInfo(context, r),
                  ),
            ],
          ),
          const SizedBox(height: 10),
          if (problem != null)
            _Note(
              icon: Icons.warning_amber_rounded,
              color: GameStyle.crimson,
              text: t.errorText(problem.code) ?? t.errorRolesTooStrong,
            )
          else
            _Note(
              icon: Icons.info_outline_rounded,
              color: GameStyle.muted,
              text: t.gameRolesTapHint,
            ),
        ],
      ),
    );
  }
}

bool _sameCounts(Map<Role, int>? a, Map<Role, int>? b) {
  if (a == null || b == null) return a == b;
  final keys = {...a.keys, ...b.keys};
  return keys.every((k) => (a[k] ?? 0) == (b[k] ?? 0));
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      Icon(icon, size: 16, color: color),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: color == GameStyle.muted ? GameStyle.muted : color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

/// A role with its icon on the side's colour, and how many there are.
class RoleChip extends StatelessWidget {
  const RoleChip({
    super.key,
    required this.role,
    required this.count,
    this.onTap,
  });

  final Role role;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color = GameStyle.teamColor(role.team);
    return Material(
      color: GameStyle.feltLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('role-chip-${role.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  GameStyle.roleIcon(role),
                  size: 15,
                  color: Colors.white,
                ),
              ),
              Text(
                t.roleName(role),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              if (count > 1)
                Text(
                  '×$count',
                  style: const TextStyle(
                    color: GameStyle.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              if (role.isNew) const _NewTag(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewTag extends StatelessWidget {
  const _NewTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: GameStyle.gold,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      AppLocalizations.of(context).gameRolesNew,
      style: const TextStyle(
        color: Color(0xFF2E2200),
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// What a role does, in a small sheet.
Future<void> showRoleInfo(BuildContext context, Role role) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: GameStyle.felt,
    showDragHandle: true,
    builder: (context) {
      final t = AppLocalizations.of(context);
      final color = GameStyle.teamColor(role.team);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 14,
                children: [
                  IconBlob(
                    icon: GameStyle.roleIcon(role),
                    color: color,
                    size: 52,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(t.roleName(role), style: GameStyle.display(20)),
                        // The Maniac's side is only the Maniac.
                        if (t.teamName(role.team) != t.roleName(role))
                          Text(
                            t.teamName(role.team),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          t.roleGoal(role),
                          style: const TextStyle(color: GameStyle.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The host's pick: [counts] null means the standard deal.
typedef PickedRoles = ({Map<Role, int>? counts});

/// Lets the host pick the roles. Null when they close it without saving.
Future<PickedRoles?> showRolePicker(
  BuildContext context, {
  required Room room,
  required int seated,
}) {
  return showModalBottomSheet<PickedRoles>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GameStyle.felt,
    showDragHandle: true,
    builder: (_) => RolePickerSheet(room: room, seated: seated),
  );
}

class RolePickerSheet extends StatefulWidget {
  const RolePickerSheet({super.key, required this.room, required this.seated});

  final Room room;
  final int seated;

  @override
  State<RolePickerSheet> createState() => _RolePickerSheetState();
}

class _RolePickerSheetState extends State<RolePickerSheet> {
  late final int _n = dealSize(widget.room, widget.seated);
  late bool _standard = widget.room.settings.roleCounts == null;
  late final Map<Role, int> _counts = {
    for (final e
        in (widget.room.settings.roleCounts ?? RoleSetup.standard(_n)).entries)
      if (e.key != Role.civilian && e.value > 0) e.key: e.value,
  };

  int _count(Role r) => _counts[r] ?? 0;

  int get _special => _counts.values.fold(0, (a, b) => a + b);

  bool _canAdd(Role r) =>
      !_standard && _special < _n && !(r.unique && _count(r) >= 1);

  void _change(Role r, int by) => setState(() {
    final next = _count(r) + by;
    if (next <= 0) {
      _counts.remove(r);
    } else {
      _counts[r] = next;
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final shown = _standard
        ? RoleSetup.standard(_n)
        : RoleSetup.fill(_n, _counts);
    final problem = _standard ? null : RoleSetup.check(_n, _counts);
    final mafia = (shown[Role.mafia] ?? 0) + (shown[Role.don] ?? 0);
    final maniac = shown[Role.maniac] ?? 0;
    final town = _n - mafia - maniac;

    Widget section(String title, Color color, List<Role> roles) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ),
        for (final r in roles)
          _RoleRow(
            role: r,
            count: r == Role.civilian ? shown[Role.civilian] ?? 0 : _count(r),
            shownCount: shown[r] ?? 0,
            fixed: r == Role.civilian,
            enabled: !_standard,
            onAdd: _canAdd(r) ? () => _change(r, 1) : null,
            onRemove: !_standard && _count(r) > 0 ? () => _change(r, -1) : null,
          ),
      ],
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(t.gameRolesTitle, style: GameStyle.display(20)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                children: [
                  Material(
                    color: GameStyle.card,
                    borderRadius: BorderRadius.circular(GameStyle.radius),
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
                      key: const ValueKey('standard-deal'),
                      title: Text(
                        t.gameRolesStandardSwitch,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        t.gameRolesStandardHint,
                        style: const TextStyle(
                          color: GameStyle.muted,
                          fontSize: 12,
                        ),
                      ),
                      value: _standard,
                      onChanged: (v) => setState(() => _standard = v),
                    ),
                  ),
                  section(t.gameTeamMafia, GameStyle.crimson, _mafiaSide),
                  section(t.gameRolesOnTheirOwn, GameStyle.maniac, _ownSide),
                  section(t.gameTeamTown, GameStyle.town, [
                    ..._townSide,
                    Role.civilian,
                  ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                    decoration: BoxDecoration(
                      color:
                          (problem == null ? GameStyle.town : GameStyle.crimson)
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color:
                            (problem == null
                                    ? GameStyle.town
                                    : GameStyle.crimson)
                                .withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      spacing: 8,
                      children: [
                        Icon(
                          problem == null
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                          color: problem == null
                              ? GameStyle.town
                              : GameStyle.crimson,
                          size: 20,
                        ),
                        Expanded(
                          child: Text(
                            problem != null
                                ? t.errorText(problem.code) ??
                                      t.errorRolesTooStrong
                                : [
                                    '${t.gameTeamMafia} $mafia',
                                    if (maniac > 0)
                                      '${t.gameTeamManiac} $maniac',
                                    '${t.gameTeamTown} $town',
                                  ].join(' · '),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Text(
                          t.gamePlayersCount(
                            _n,
                            widget.room.settings.maxPlayers,
                          ),
                          style: const TextStyle(
                            color: GameStyle.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: problem == null
                          ? GameStyle.glow(GameStyle.crimson)
                          : null,
                    ),
                    child: FilledButton(
                      key: const ValueKey('save-roles'),
                      style: FilledButton.styleFrom(
                        backgroundColor: GameStyle.crimson,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: problem != null
                          ? null
                          : () => Navigator.pop<PickedRoles>(context, (
                              counts: _standard ? null : {..._counts},
                            )),
                      child: Text(t.gameRolesSave),
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

/// One role in the picker: icon, name, what it does, and − n +.
class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.role,
    required this.count,
    required this.shownCount,
    required this.fixed,
    required this.enabled,
    this.onAdd,
    this.onRemove,
  });

  final Role role;
  final int count;
  final int shownCount;

  /// Civilians: no stepper, they fill the rest.
  final bool fixed;
  final bool enabled;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final color = GameStyle.teamColor(role.team);
    return Opacity(
      opacity: enabled || shownCount > 0 ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Palette.outlineSoft)),
        ),
        child: Row(
          spacing: 12,
          children: [
            GestureDetector(
              onTap: () => showRoleInfo(context, role),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  GameStyle.roleIcon(role),
                  color: Colors.white,
                  size: 21,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Row(
                    spacing: 6,
                    children: [
                      Flexible(
                        child: Text(
                          t.roleName(role),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (role.isNew) const _NewTag(),
                    ],
                  ),
                  Text(
                    t.roleShort(role),
                    style: const TextStyle(
                      color: GameStyle.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (fixed || !enabled)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  '$shownCount',
                  style: GameStyle.display(15, color: GameStyle.muted),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: GameStyle.feltLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Step(
                      key: ValueKey('remove-${role.name}'),
                      tooltip: t.gameRolesRemove(t.roleName(role)),
                      icon: Icons.remove_rounded,
                      onTap: onRemove,
                    ),
                    SizedBox(
                      width: 20,
                      child: Text(
                        '$count',
                        textAlign: TextAlign.center,
                        style: GameStyle.display(14),
                      ),
                    ),
                    _Step(
                      key: ValueKey('add-${role.name}'),
                      tooltip: t.gameRolesAdd(t.roleName(role)),
                      icon: Icons.add_rounded,
                      onTap: onAdd,
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

class _Step extends StatelessWidget {
  const _Step({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    iconSize: 18,
    color: Colors.white,
    disabledColor: GameStyle.muted.withValues(alpha: 0.4),
    tooltip: tooltip,
    icon: Icon(icon),
    onPressed: onTap,
  );
}
