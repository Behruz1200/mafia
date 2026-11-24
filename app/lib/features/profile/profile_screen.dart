import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../core/top_bar_buttons.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_error_text.dart';
import '../auth/widgets.dart';

/// Stream 5 (accounts) owns this folder: name, age gate, sign out and
/// account deletion (Apple requires deletion inside the app). Avatar
/// upload and block/report come in a later change.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  String? _loadedFor;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(authErrorText(t, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final t = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.profileDeleteTitle),
        content: Text(t.profileDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.profileCancel),
          ),
          TextButton(
            key: const Key('confirmDelete'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.profileDeleteConfirm),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(() async {
      await ref.read(authRepositoryProvider).deleteAccount();
      if (mounted) context.go(Routes.signIn);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final profile = ref.watch(myProfileProvider).value;
    if (profile != null && _loadedFor != profile.userId) {
      _loadedFor = profile.userId;
      _name.text = profile.displayName;
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.profileTitle)),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    child: Text(
                      profile.displayName.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('profileName'),
                  controller: _name,
                  maxLength: 24,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: t.authNameLabel),
                ),
                FilledButton(
                  key: const Key('saveProfile'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ref
                              .read(profileRepositoryProvider)
                              .updateMyProfile(
                                profile.copyWith(displayName: _name.text),
                              ),
                          done: t.profileSaved,
                        ),
                  child: Text(t.profileSave),
                ),
                const SizedBox(height: 24),
                _AgeTile(profile: profile, busy: _busy, run: _run),
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(t.languageTitle),
                ),
                const LanguagePicker(),
                const Divider(height: 48),
                OutlinedButton(
                  key: const Key('signOut'),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await ref.read(authRepositoryProvider).signOut();
                          if (context.mounted) context.go(Routes.signIn);
                        }),
                  child: Text(t.profileSignOut),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const Key('deleteAccount'),
                  onPressed: _busy ? null : _confirmDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: Text(t.profileDelete),
                ),
              ],
            ),
    );
  }
}

class _AgeTile extends ConsumerWidget {
  const _AgeTile({
    required this.profile,
    required this.busy,
    required this.run,
  });

  final UserProfile profile;
  final bool busy;
  final Future<void> Function(Future<void> Function(), {String? done}) run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    if (profile.hasBirthDate) {
      return ListTile(
        leading: Icon(profile.isAdult ? Icons.verified_user : Icons.lock),
        title: Text(profile.isAdult ? t.profileAdult : t.profileUnder18),
      );
    }
    return ListTile(
      key: const Key('addBirthDate'),
      leading: const Icon(Icons.cake_outlined),
      title: Text(t.profileAddBirthDate),
      subtitle: Text(t.authBirthDateHint),
      enabled: !busy,
      onTap: () async {
        final d = await pickBirthDate(context);
        if (d == null) return;
        await run(
          () => ref.read(profileRepositoryProvider).setBirthDate(d),
          done: t.profileSaved,
        );
      },
    );
  }
}
