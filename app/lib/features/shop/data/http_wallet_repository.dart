import 'dart:async';
import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;

import 'store_billing.dart';

/// A wallet call the server turned down. [code] is the `ApiError` code,
/// e.g. `purchase_invalid`, `store_unavailable`, `unauthorized`.
class WalletException implements Exception {
  const WalletException(this.code, {this.status});
  final String code;
  final int? status;

  /// Retrying later may work (server or store down, no network).
  bool get isTemporary => status == null || status! >= 500;

  @override
  String toString() => 'WalletException($code)';
}

/// The real [WalletRepository]: balance and history from our server,
/// purchases through the phone's store and verified by our server.
class HttpWalletRepository implements WalletRepository {
  HttpWalletRepository({
    required this.baseUrl,
    required this.accessToken,
    required this.billing,
    http.Client? client,
    this.refreshEvery = const Duration(seconds: 30),
  }) : _http = client ?? http.Client() {
    _unfinishedSub = billing.unfinished.listen(_deliver);
  }

  final String baseUrl;

  /// The signed-in player's token, or null when signed out.
  final String? Function() accessToken;
  final StoreBilling billing;
  final Duration refreshEvery;
  final http.Client _http;
  late final StreamSubscription<StorePurchase> _unfinishedSub;

  WalletBalance? _latest;
  Timer? _timer;
  late final _balances = StreamController<WalletBalance>.broadcast(
    onListen: () {
      _refreshQuietly();
      _timer = Timer.periodic(refreshEvery, (_) => _refreshQuietly());
    },
    onCancel: () => _timer?.cancel(),
  );

  Map<String, String> get _headers {
    final token = accessToken();
    if (token == null) throw const WalletException('unauthorized', status: 401);
    return {
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    };
  }

  Future<Object?> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response res;
    try {
      res = method == 'GET'
          ? await _http.get(uri, headers: _headers)
          : await _http.post(uri, headers: _headers, body: jsonEncode(body));
    } on WalletException {
      rethrow;
    } on Object {
      throw const WalletException('network');
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    final code = decoded is Map<String, Object?> && decoded['error'] is String
        ? decoded['error']! as String
        : 'http_${res.statusCode}';
    throw WalletException(code, status: res.statusCode);
  }

  WalletBalance _emit(WalletBalance b) {
    _latest = b;
    if (_balances.hasListener) _balances.add(b);
    return b;
  }

  /// Fetches the balance now, e.g. after a match ends.
  Future<WalletBalance> refresh() async => _emit(
    WalletBalance.fromJson((await _send('GET', ApiRoutes.wallet))! as Json),
  );

  /// Background refresh: an error only reaches the screen while it has no
  /// balance at all to show.
  void _refreshQuietly() {
    refresh().then<void>(
      (_) {},
      onError: (Object e) {
        if (_latest == null && _balances.hasListener) _balances.addError(e);
      },
    );
  }

  @override
  Stream<WalletBalance> watchBalance() async* {
    if (_latest case final b?) yield b;
    yield* _balances.stream;
  }

  @override
  Future<List<LedgerEntry>> history({int limit = 50}) async {
    final rows = await _send('GET', '${ApiRoutes.ledger}?limit=$limit');
    return [for (final r in rows! as List) LedgerEntry.fromJson(r as Json)];
  }

  @override
  Future<List<CoinPack>> coinPacks() async {
    final rows = await _send('GET', ApiRoutes.coinPacks);
    return [for (final r in rows! as List) CoinPack.fromJson(r as Json)];
  }

  @override
  Future<WalletBalance> buy(CoinPack pack) async {
    final purchase = await billing.buy(pack.productId);
    return _deliver(purchase);
  }

  /// Sends a store purchase to the server, then finishes it with the store.
  /// If the server or network is down the purchase stays unfinished and the
  /// store hands it back on the next launch, so the coins are not lost.
  Future<WalletBalance> _deliver(StorePurchase purchase) async {
    try {
      final body = await _send(
        'POST',
        ApiRoutes.purchases,
        purchase.toRequest().toJson(),
      );
      await billing.finish(purchase);
      return _emit(WalletBalance.fromJson(body! as Json));
    } on WalletException catch (e) {
      // The server looked and said no (fake, refunded, other account):
      // retrying will not change that, so let the store close it.
      if (!e.isTemporary && e.code != 'unauthorized') {
        await billing.finish(purchase);
      }
      rethrow;
    }
  }

  void dispose() {
    _timer?.cancel();
    _unfinishedSub.cancel();
    _balances.close();
    billing.dispose();
  }
}
