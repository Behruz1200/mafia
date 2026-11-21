import 'dart:async';

import 'package:contracts/contracts.dart';

import '../../auth/data/api.dart';
import '../../auth/data/http_auth_repository.dart';

/// The real [ProfileRepository]: `GET/PATCH /v1/me` on the game server.
/// Loads the profile again whenever the signed-in account changes.
class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository({required this.api, required this.auth}) {
    _sub = auth.watchSession().listen((s) {
      if (s?.userId != _profile?.userId) {
        _emit(null);
        if (s != null) unawaited(reload().then((_) {}, onError: (Object _) {}));
      }
    });
  }

  final AccountsApi api;
  final HttpAuthRepository auth;
  late final StreamSubscription<AuthSession?> _sub;
  UserProfile? _profile;
  final _ctrl = StreamController<UserProfile?>.broadcast();

  void _emit(UserProfile? p) => _ctrl.add(_profile = p);

  Future<String> _token() async {
    final s = await auth.freshSession();
    if (s == null) throw const ApiException('unauthorized', status: 401);
    return s.accessToken;
  }

  /// Fetches the profile from the server.
  Future<UserProfile> reload() async {
    final j = await api.send('GET', ApiRoutes.me, accessToken: await _token());
    final p = UserProfile.fromJson(j!);
    _emit(p);
    return p;
  }

  @override
  Stream<UserProfile?> watchMyProfile() async* {
    if (_profile != null) {
      yield _profile;
    } else if (auth.currentSession != null) {
      unawaited(reload().then((_) {}, onError: (Object _) {}));
    }
    yield* _ctrl.stream;
  }

  Future<UserProfile> _patch(UpdateProfileRequest req) async {
    final j = await api.send(
      'PATCH',
      ApiRoutes.me,
      body: req.toJson(),
      accessToken: await _token(),
    );
    final p = UserProfile.fromJson(j!);
    _emit(p);
    return p;
  }

  @override
  Future<UserProfile> updateMyProfile(UserProfile profile) => _patch(
    UpdateProfileRequest(
      displayName: profile.displayName,
      locale: profile.locale,
    ),
  );

  @override
  Future<UserProfile> setBirthDate(DateTime birthDate) =>
      _patch(UpdateProfileRequest(birthDate: birthDate));

  void dispose() {
    _sub.cancel();
    _ctrl.close();
  }
}
