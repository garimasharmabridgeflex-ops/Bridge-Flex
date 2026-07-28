import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'api_exception.dart';

/// Thin wrapper over the plain-HTTP Cloud Function endpoints
/// (ARCHITECTURE.md v2 §1a: no callable envelope, just JSON POST + Bearer
/// token). One process per function locally, so each call resolves its own
/// base URL from [Env.functionUri].
class ApiClient {
  ApiClient(this._auth);

  final FirebaseAuth _auth;
  final http.Client _http = http.Client();

  // Firebase's own token-refresh call and the HTTP request itself both used
  // to be able to hang indefinitely on a bad connection — with nothing
  // above this layer imposing a limit either, that could strand a caller
  // forever (ownProfileProvider sits on the splash → app redirect path in
  // router.dart, so this wasn't just a slow-spinner problem).
  static const _tokenTimeout = Duration(seconds: 10);
  static const _requestTimeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> post(
    ApiFunction fn, {
    Map<String, dynamic> body = const {},
  }) async {
    final token = await _auth.currentUser?.getIdToken().timeout(_tokenTimeout);
    final response = await _http
        .post(
          Env.functionUri(fn),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);
    return _decode(response);
  }

  /// A handful of endpoints (GetShift, GetPublicProfile, ListChatMessages)
  /// read params from the query string, not a JSON body — there's no
  /// method check server-side (any verb works), so POST-with-query-string
  /// keeps this client's header/auth handling uniform.
  Future<Map<String, dynamic>> postWithQuery(
    ApiFunction fn, {
    Map<String, String> query = const {},
  }) async {
    final token = await _auth.currentUser?.getIdToken().timeout(_tokenTimeout);
    final uri = Env.functionUri(fn).replace(queryParameters: query);
    final response = await _http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(_requestTimeout);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Map<String, dynamic> json = response.body.isEmpty
        ? const {}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    final error = json['error'] as Map<String, dynamic>?;
    throw ApiException(
      statusCode: response.statusCode,
      code: error?['code'] as String? ?? 'UNKNOWN',
      message: error?['message'] as String? ?? 'Something went wrong',
    );
  }
}
