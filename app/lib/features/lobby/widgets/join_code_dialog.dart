import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Asks for a room's invite code, e.g. `K7QF2`. Returns it upper-cased, or
/// null on cancel.
Future<String?> showJoinCodeDialog(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const JoinCodeDialog(),
);

class JoinCodeDialog extends StatefulWidget {
  const JoinCodeDialog({super.key});

  @override
  State<JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<JoinCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _value => _code.text.trim().toUpperCase();

  void _submit() {
    if (_value.length >= 4) Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.joinRoom),
      content: TextField(
        controller: _code,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        textAlign: TextAlign.center,
        maxLength: 8,
        style: const TextStyle(
          fontSize: 28,
          letterSpacing: 6,
          fontWeight: FontWeight.w800,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
        ],
        decoration: InputDecoration(labelText: t.lobbyCodeLabel),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.lobbyCancel),
        ),
        FilledButton(
          onPressed: _value.length >= 4 ? _submit : null,
          child: Text(t.lobbyJoin),
        ),
      ],
    );
  }
}
