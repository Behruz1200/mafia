import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

final _profileProvider = StreamProvider(
  (ref) => ref.watch(profileRepositoryProvider).watchMyProfile(),
);

/// Stream 5 (accounts) owns this folder: profile, avatar, language,
/// block and report, account deletion.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final profile = ref.watch(_profileProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(t.profileTitle)),
      body: Center(child: Text(profile?.displayName ?? '…')),
    );
  }
}
