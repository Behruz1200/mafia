import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../l10n/generated/app_localizations.dart';
import 'auth_error_text.dart';
import 'data/api.dart';
import 'sign_in_art.dart';
import 'widgets.dart';

enum _Step { phone, code, setup }

/// Stream 5 (accounts). Sign in by phone number (SMS code) or with Apple,
/// then, the first time, a short "about you" step: name and date of birth
/// for the 18+ age gate.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.showApple, this.showGuest});

  /// Defaults to iOS only. Tests set it.
  final bool? showApple;

  /// "Play as guest": defaults to the GUEST_SIGN_IN build setting.
  final bool? showGuest;

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

  /// The setup step asks for a date of birth only when the account has
  /// none yet. Guests come with one from the server, so they see only
  /// the name field.
  var _askBirthDate = true;
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

  Future<void> _guest() => _run(() async {
    await ref.read(authRepositoryProvider).signInAsGuest();
    await _afterSignIn(guest: true);
  });

  /// New players (no birth date yet) see the setup step; others go in.
  /// A guest always gets to pick a name, and nothing else.
  Future<void> _afterSignIn({bool guest = false}) async {
    final profile = await ref
        .read(profileRepositoryProvider)
        .watchMyProfile()
        .firstWhere((p) => p != null)
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    if (!mounted) return;
    if (profile != null && (guest || !profile.hasBirthDate)) {
      _name.text = profile.displayName;
      setState(() {
        _askBirthDate = !profile.hasBirthDate;
        _step = _Step.setup;
      });
    } else {
      context.go(Routes.lobby);
    }
  }

  Future<void> _finishSetup() => _run(() async {
    final repo = ref.read(profileRepositoryProvider);
    final current = await repo.watchMyProfile().firstWhere((p) => p != null);
    await repo.updateMyProfile(current!.copyWith(displayName: _name.text));
    if (_askBirthDate) await repo.setBirthDate(_birthDate!);
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

    // Apple sign-in is set up for the iPhone app only, not for the browser
    // (an iPhone browser also reports iOS).
    final showApple =
        widget.showApple ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
    final showGuest = widget.showGuest ?? AppConfig.guestSignIn;

    final status = [
      if (_error != null)
        Text(
          _error!,
          key: const Key('authError'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontWeight: FontWeight.w700,
          ),
        ),
      if (_busy) const LinearProgressIndicator(),
    ];

    return Scaffold(
      backgroundColor: Palette.background,
      body: Stack(
        children: [
          const Positioned.fill(child: SignInBackdrop()),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _step == _Step.phone
                          ? _phoneLayout(t, showApple, showGuest, status)
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 16,
                                children: [
                                  ...switch (_step) {
                                    _Step.code => _codeStep(t),
                                    _ => _setupStep(t),
                                  },
                                  ...status,
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The first screen: a hand of role cards, the logo, and a panel at the
  /// bottom with the phone number and Apple.
  Widget _phoneLayout(
    AppLocalizations t,
    bool showApple,
    bool showGuest,
    List<Widget> status,
  ) {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    // The cards get whatever height the logo and the panel leave, and are
    // left out on short screens so the buttons stay in view.
    final media = MediaQuery.of(context);
    final fan = min(270.0, media.size.height - media.padding.vertical - 520);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 36),
        if (fan >= 140) ...[
          RoleCardFan(height: fan),
          const SizedBox(height: 32),
        ],
        Text(
          t.appTitle.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: Palette.display,
            fontWeight: FontWeight.w800,
            fontSize: 46,
            height: 1,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          t.lobbyTagline,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.muted,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const Spacer(),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            color: Palette.surfaceSheet.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: const Border(top: BorderSide(color: Palette.outlineSoft)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Text(
                t.signInTitle,
                style: const TextStyle(
                  fontFamily: Palette.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              TextField(
                key: const Key('phoneField'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  labelText: t.authPhoneLabel,
                  hintText: '90 123 45 67',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        const UzFlag(),
                        Text(
                          _prefix,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(width: 1, height: 24, color: Palette.outline),
                      ],
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => digits.length == 9 ? _sendCode() : null,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: digits.length == 9
                      ? [
                          BoxShadow(
                            color: Palette.accent.withValues(alpha: 0.45),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: FilledButton(
                  key: const Key('sendCode'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: digits.length == 9 && !_busy ? _sendCode : null,
                  child: Text(t.authSendCode),
                ),
              ),
              if (showApple || showGuest) ...[
                Row(
                  spacing: 12,
                  children: [
                    const Expanded(child: Divider()),
                    Text(
                      t.authOr,
                      style: const TextStyle(
                        color: Palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
              ],
              if (showApple) ...[
                // Apple's own look: a white button with a black logo.
                FilledButton.icon(
                  key: const Key('appleSignIn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(56),
                  ),
                  icon: const Icon(Icons.apple, size: 24),
                  onPressed: _busy ? null : _apple,
                  label: Text(t.signInWithApple),
                ),
              ],
              if (showGuest)
                OutlinedButton.icon(
                  key: const Key('guestSignIn'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.text,
                    side: const BorderSide(color: Palette.outline),
                    minimumSize: const Size.fromHeight(56),
                  ),
                  icon: const Icon(Icons.bolt_rounded, color: Palette.gold),
                  onPressed: _busy ? null : _guest,
                  label: Text(t.authPlayAsGuest),
                ),
              ...status,
            ],
          ),
        ),
      ],
    );
  }

  /// A step's big heading with a line under it.
  Widget _heading(String title, String? subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Palette.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: Palette.accent, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontFamily: Palette.display,
              fontWeight: FontWeight.w800,
              fontSize: 26,
              height: 1.15,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(
                color: Palette.muted,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _codeStep(AppLocalizations t) => [
    _heading(t.authCodeLabel, t.authCodeSentTo(_phoneE164), Icons.sms_rounded),
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
      style: const TextStyle(
        fontFamily: Palette.display,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: 14,
      ),
      decoration: const InputDecoration(
        hintText: '••••••',
        contentPadding: EdgeInsets.symmetric(vertical: 22),
      ),
      onChanged: (v) {
        setState(() {});
        if (v.length == 6 && !_busy) _verify();
      },
    ),
    FilledButton(
      key: const Key('verifyCode'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      onPressed: _code.text.length == 6 && !_busy ? _verify : null,
      child: Text(t.authVerify),
    ),
    Wrap(
      alignment: WrapAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _step = _Step.phone;
                  _error = null;
                }),
          child: Text(t.authChangeNumber),
        ),
        TextButton(
          onPressed: _resendIn > 0 || _busy ? null : _sendCode,
          child: Text(_resendIn > 0 ? t.authResendIn(_resendIn) : t.authResend),
        ),
      ],
    ),
  ];

  List<Widget> _setupStep(AppLocalizations t) {
    final nameOk = _name.text.trim().length >= 2;
    return [
      _heading(t.authSetupTitle, null, Icons.person_rounded),
      TextField(
        key: const Key('nameField'),
        controller: _name,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        decoration: InputDecoration(labelText: t.authNameLabel),
        onChanged: (_) => setState(() {}),
      ),
      if (_askBirthDate) ...[
        OutlinedButton.icon(
          key: const Key('birthDateButton'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            alignment: Alignment.centerLeft,
          ),
          icon: const Icon(Icons.cake_rounded, color: Palette.gold),
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
      ],
      FilledButton(
        key: const Key('finishSetup'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: nameOk && (_birthDate != null || !_askBirthDate) && !_busy
            ? _finishSetup
            : null,
        child: Text(t.authContinue),
      ),
    ];
  }
}
