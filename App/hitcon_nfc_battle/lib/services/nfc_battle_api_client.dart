import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const int _maxResponseBytes = 5 * 1024 * 1024;

  Future<Map<String, dynamic>> get(
    String path, {
    required String token,
    Map<String, String>? query,
  }) {
    return _request('GET', path, token: token, query: query);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) {
    return _request('POST', path, token: token, body: body, query: query);
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
  }) async {
    final Uri base = Uri.parse(AppConfig.apiBaseUrl);
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.userInfo.isNotEmpty) {
      throw const FormatException('API_BASE_URL must be a valid HTTPS origin.');
    }
    final String normalizedPath =
        '${base.path.replaceFirst(RegExp(r'/$'), '')}/${path.replaceFirst(RegExp(r'^/'), '')}';
    final Uri uri = base.replace(path: normalizedPath, queryParameters: query);
    final HttpClient client = HttpClient();
    client.connectionTimeout = _requestTimeout;

    try {
      final HttpClientRequest request = await client
          .openUrl(method, uri)
          .timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final HttpClientResponse response = await request.close().timeout(
        _requestTimeout,
      );
      final BytesBuilder responseBytes = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.timeout(_requestTimeout)) {
        if (responseBytes.length + chunk.length > _maxResponseBytes) {
          throw const FormatException('API response exceeds the size limit.');
        }
        responseBytes.add(chunk);
      }
      final String text = utf8.decode(responseBytes.takeBytes());
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
