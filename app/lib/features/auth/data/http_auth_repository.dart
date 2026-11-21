import 'dart:async';

import 'package:contracts/contracts.dart';

import 'api.dart';
import 'apple_credentials.dart';
import 'session_storage.dart';

/// The real [AuthRepository]: our own sign-in on the game server.
///
/// The session is kept in secure storage and refreshed a minute before the
/// access token runs out, so `currentSession.accessToken` is always usable
/// by the other parts of the app.
class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository({
    required this.api,
    SessionStorage? storage,
    AppleCredentialSource? apple,
    DateTime Function()? now,
  }) : _storage = storage ?? SecureSessionStorage(),
       _apple = apple ?? appleSignInSheet,
       _now = now ?? DateTime.now {
    _restored = _restore();
  }

  final AccountsApi api;
  final SessionStorage _storage;
  final AppleCredentialSource _apple;
  final DateTime Function() _now;

  AuthSession? _session;
  final _ctrl = StreamController<AuthSession?>.broadcast();
  late final Future<void> _restored;
  Future<AuthSession?>? _refreshing;
  Timer? _timer;

  /// Done once the saved session (if any) has been loaded.
  Future<void> get restored => _restored;

  Future<void> _restore() async {
    final saved = await _storage.read();
    if (saved == null) return;
    _session = saved;
    _schedule();
    if (_isStale(saved)) await refreshNow();
  }

  bool _isStale(AuthSession s) =>
      _now().isAfter(s.expiresAt.subtract(const Duration(minutes: 1)));

  Future<void> _set(AuthSession? s) async {
    _session = s;
    await _storage.write(s);
    _schedule();
    _ctrl.add(s);
  }

  void _schedule() {
    _timer?.cancel();
    final s = _session;
    if (s == null) return;
    final wait = s.expiresAt
        .subtract(const Duration(minutes: 1))
        .difference(_now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () => refreshNow());
  }

  @override
  AuthSession? get currentSession => _session;

  @override
  Stream<AuthSession?> watchSession() async* {
    await _restored;
    yield _session;
    yield* _ctrl.stream;
  }

  /// A session whose access token is good for at least a minute, or null
  /// when signed out.
  Future<AuthSession?> freshSession() async {
    await _restored;
    final s = _session;
    if (s == null || !_isStale(s)) return s;
    return refreshNow();
  }

  /// Swaps the refresh token for a new session. Signs out when the server
  /// says the token is no longer valid; keeps the session (and retries in
  /// 30 seconds) when the server cannot be reached.
  Future<AuthSession?> refreshNow() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<AuthSession?> _refresh() async {
    final s = _session;
    if (s == null) return null;
    try {
      final j = await api.send(
        'POST',
        ApiRoutes.authRefresh,
        body: RefreshRequest(refreshToken: s.refreshToken).toJson(),
      );
      final next = AuthSession.fromJson(j!);
      await _set(next);
      return next;
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _set(null);
        return null;
      }
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 30), () => refreshNow());
      return s;
    }
  }

  @override
  Future<void> startPhoneSignIn(String phoneE164) async {
    await api.send(
      'POST',
      ApiRoutes.authPhoneStart,
      body: PhoneStartRequest(phoneE164: phoneE164).toJson(),
    );
  }

  @override
  Future<AuthSession> verifyPhoneCode(String phoneE164, String code) async {
    final j = await api.send(
      'POST',
      ApiRoutes.authPhoneVerify,
      body: PhoneVerifyRequest(phoneE164: phoneE164, code: code).toJson(),
    );
    final s = AuthSession.fromJson(j!);
    await _set(s);
    return s;
  }

  @override
  Future<AuthSession> signInWithApple() async {
    final req = await _apple();
    if (req == null) throw const ApiException('apple_canceled');
    final j = await api.send('POST', ApiRoutes.authApple, body: req.toJson());
    final s = AuthSession.fromJson(j!);
    await _set(s);
    return s;
  }

  @override
  Future<void> signOut() async {
    final s = _session;
    await _set(null);
    if (s == null) return;
    try {
      await api.send(
        'POST',
        ApiRoutes.authSignOut,
        body: RefreshRequest(refreshToken: s.refreshToken).toJson(),
      );
    } on ApiException {
      // Signed out on this phone either way; the token expires by itself.
    }
  }

  @override
  Future<void> deleteAccount() async {
    final s = await freshSession();
    if (s == null) return;
    await api.send('DELETE', ApiRoutes.me, accessToken: s.accessToken);
    await _set(null);
  }

  void dispose() {
    _timer?.cancel();
    _ctrl.close();
  }
}
