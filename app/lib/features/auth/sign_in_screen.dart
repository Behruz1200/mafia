import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../l10n/generated/app_localizations.dart';
import 'auth_error_text.dart';
import 'data/api.dart';
import 'widgets.dart';

enum _Step { phone, code, setup }

/// Stream 5 (accounts). Sign in by phone number (SMS code) or with Apple,
/// then, the first time, a short "about you" step: name and date of birth
/// for the 18+ age gate.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.showApple});

  /// Defaults to iOS only. Tests set it.
  final bool? showApple;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  /// Uzbekistan first; the only country the server accepts for now.
  static const _prefix = '+998';

  var _step = _Step.phone;
  var _busy = false;
  String? _error;
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  DateTime? _birthDate;
  Timer? _resendTimer;
  var _resendIn = 0;

  String get _phoneE164 =>
      '$_prefix${_phone.text.replaceAll(RegExp(r'\D'), '')}';

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = authErrorText(AppLocalizations.of(context), e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() => _run(() async {
    await ref.read(authRepositoryProvider).startPhoneSignIn(_phoneE164);
    _code.clear();
    _startResendTimer();
    setState(() => _step = _Step.code);
  });

  Future<void> _verify() => _run(() async {
    await ref
        .read(authRepositoryProvider)
        .verifyPhoneCode(_phoneE164, _code.text.trim());
    await _afterSignIn();
  });

  Future<void> _apple() => _run(() async {
    try {
      await ref.read(authRepositoryProvider).signInWithApple();
    } on ApiException catch (e) {
      if (e.code == 'apple_canceled') return;
      rethrow;
    }
    await _afterSignIn();
  });

  /// New players (no birth date yet) see the setup step; others go in.
  Future<void> _afterSignIn() async {
    final profile = await ref
        .read(profileRepositoryProvider)
        .watchMyProfile()
        .firstWhere((p) => p != null)
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    if (!mounted) return;
    if (profile != null && !profile.hasBirthDate) {
      _name.text = profile.displayName;
      setState(() => _step = _Step.setup);
    } else {
      context.go(Routes.lobby);
    }
  }

  Future<void> _finishSetup() => _run(() async {
    final repo = ref.read(profileRepositoryProvider);
    final current = await repo.watchMyProfile().firstWhere((p) => p != null);
    await repo.updateMyProfile(current!.copyWith(displayName: _name.text));
    await repo.setBirthDate(_birthDate!);
    if (mounted) context.go(Routes.lobby);
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    // A saved session is still loading: wait. A session appears while on
    // the first step (restored from the last launch): go straight in.
    final session = ref.watch(sessionProvider);
    ref.listen(sessionProvider, (_, next) {
      if (next.value != null && _step == _Step.phone && !_busy) {
        context.go(Routes.lobby);
      }
    });
    if (session.isLoading && _step == _Step.phone) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final showApple =
        widget.showApple ?? defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      appBar: AppBar(
        title: Text(_step == _Step.setup ? t.authSetupTitle : t.signInTitle),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  ...switch (_step) {
                    _Step.phone => _phoneStep(t, showApple),
                    _Step.code => _codeStep(t),
                    _Step.setup => _setupStep(t),
                  },
                  if (_error != null)
                    Text(
                      _error!,
                      key: const Key('authError'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneStep(AppLocalizations t, bool showApple) {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    return [
      TextField(
        key: const Key('phoneField'),
        controller: _phone,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumberNational],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(9),
        ],
        decoration: InputDecoration(
          labelText: t.authPhoneLabel,
          prefixText: '$_prefix ',
          hintText: '90 123 45 67',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => digits.length == 9 ? _sendCode() : null,
      ),
      FilledButton(
        key: const Key('sendCode'),
        onPressed: digits.length == 9 && !_busy ? _sendCode : null,
        child: Text(t.authSendCode),
      ),
      if (showApple) ...[
        Text(t.authOr, textAlign: TextAlign.center),
        OutlinedButton.icon(
          key: const Key('appleSignIn'),
          icon: const Icon(Icons.apple),
          onPressed: _busy ? null : _apple,
          label: Text(t.signInWithApple),
        ),
      ],
    ];
  }

  List<Widget> _codeStep(AppLocalizations t) => [
    Text(t.authCodeSentTo(_phoneE164), textAlign: TextAlign.center),
    TextField(
      key: const Key('codeField'),
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 28, letterSpacing: 8),
      decoration: InputDecoration(labelText: t.authCodeLabel),
      onChanged: (v) {
        setState(() {});
        if (v.length == 6 && !_busy) _verify();
      },
    ),
    FilledButton(
      key: const Key('verifyCode'),
      onPressed: _code.text.length == 6 && !_busy ? _verify : null,
      child: Text(t.authVerify),
    ),
    TextButton(
      onPressed: _resendIn > 0 || _busy ? null : _sendCode,
      child: Text(_resendIn > 0 ? t.authResendIn(_resendIn) : t.authResend),
    ),
    TextButton(
      onPressed: _busy
          ? null
          : () => setState(() {
              _step = _Step.phone;
              _error = null;
            }),
      child: Text(t.authChangeNumber),
    ),
  ];

  List<Widget> _setupStep(AppLocalizations t) {
    final nameOk = _name.text.trim().length >= 2;
    return [
      TextField(
        key: const Key('nameField'),
        controller: _name,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: t.authNameLabel),
        onChanged: (_) => setState(() {}),
      ),
      OutlinedButton.icon(
        key: const Key('birthDateButton'),
        icon: const Icon(Icons.cake_outlined),
        onPressed: _busy
            ? null
            : () async {
                final d = await pickBirthDate(context, initial: _birthDate);
                if (d != null) setState(() => _birthDate = d);
              },
        label: Text(
          _birthDate == null
              ? '${t.authBirthDateLabel}: ${t.authPickDate}'
              : '${t.authBirthDateLabel}: ${formatDate(_birthDate!)}',
        ),
      ),
      Text(t.authBirthDateHint, style: Theme.of(context).textTheme.bodySmall),
      FilledButton(
        key: const Key('finishSetup'),
        onPressed: nameOk && _birthDate != null && !_busy ? _finishSetup : null,
        child: Text(t.authContinue),
      ),
    ];
  }
}
