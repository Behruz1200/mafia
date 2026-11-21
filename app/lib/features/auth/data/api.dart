import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:http/http.dart' as http;

/// A failed call to the game server. [code] is the server's `ApiError`
/// code (`code_invalid`, ...) or `network` when the server could not be
/// reached. Screens turn it into text with `authErrorText`.
class ApiException implements Exception {
  const ApiException(this.code, {this.status});
  final String code;
  final int? status;

  static const network = 'network';

  @override
  String toString() => 'ApiException($code, $status)';
}

/// Small JSON-over-HTTP helper for the accounts calls.
class AccountsApi {
  AccountsApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Json?> send(
    String method,
    String path, {
    Json? body,
    String? accessToken,
  }) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json';
    if (accessToken != null) {
      req.headers['authorization'] = 'Bearer $accessToken';
    }
    if (body != null) req.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 20)),
      );
    } on Object {
      throw const ApiException(ApiException.network);
    }

    final text = utf8.decode(res.bodyBytes);
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded is Json ? decoded : null;
    }
    final code = decoded is Json && decoded['error'] is String
        ? ApiError.fromJson(decoded).code
        : 'http_${res.statusCode}';
    throw ApiException(code, status: res.statusCode);
  }
}
