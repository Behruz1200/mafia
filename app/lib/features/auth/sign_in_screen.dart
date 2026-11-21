import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../l10n/generated/app_localizations.dart';

/// Stream 5 (accounts) owns this folder: phone sign-in by SMS code, Sign in
/// with Apple, age gate. Placeholder buttons sign in with the fake repo.
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final auth = ref.watch(authRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.signInTitle)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            FilledButton(
              onPressed: () async {
                await auth.verifyPhoneCode('+998000000000', '0000');
                if (context.mounted) context.go(Routes.lobby);
              },
              child: Text(t.signInWithPhone),
            ),
            OutlinedButton(
              onPressed: () async {
                await auth.signInWithApple();
                if (context.mounted) context.go(Routes.lobby);
              },
              child: Text(t.signInWithApple),
            ),
          ],
        ),
      ),
    );
  }
}
