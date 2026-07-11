import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() {
    final String prefix = code == null ? 'API' : 'API $code';
    return '$prefix ($statusCode): $message';
  }
}

class NfcBattleApiClient {
  const NfcBattleApiClient();

  Future<Map<String, dynamic>> get(
    String path, {
    required String token,
    Map<String, String>? query,
    bool staffDanger = false,
  }) {
    return _request(
      'GET',
      path,
      token: token,
      query: query,
      staffDanger: staffDanger,
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool staffDanger = false,
  }) {
    return _request(
      'POST',
      path,
      token: token,
      body: body,
      query: query,
      staffDanger: staffDanger,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    required String token,
    Map<String, dynamic>? body,
  }) {
    return _request('PATCH', path, token: token, body: body);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool staffDanger = false,
  }) async {
    final Uri base = Uri.parse(AppConfig.apiBaseUrl);
    final String normalizedPath =
        '${base.path.replaceFirst(RegExp(r'/$'), '')}/${path.replaceFirst(RegExp(r'^/'), '')}';
    final Uri uri = base.replace(path: normalizedPath, queryParameters: query);
    final HttpClient client = HttpClient();

    try {
      final HttpClientRequest request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (staffDanger && AppConfig.staffDangerToken.isNotEmpty) {
        request.headers.set('X-Staff-Danger-Token', AppConfig.staffDangerToken);
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final HttpClientResponse response = await request.close();
      final String text = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> decoded = _decodeObject(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode,
          decoded['message'] as String? ?? text,
          code: decoded['code'] as String?,
        );
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeObject(String text) {
    if (text.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final dynamic decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((Object? key, Object? value) {
        return MapEntry<String, dynamic>(key.toString(), value);
      });
    }
    return <String, dynamic>{'data': decoded};
  }
}
