import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

bool isNetworkConnectionError(Object error) {
  return error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error is HttpException;
}

class NfcBattleApiClient {
  const NfcBattleApiClient();

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const int _maxResponseBytes = 5 * 1024 * 1024;

  Future<Map<String, dynamic>> get(
    String path, {
    required String token,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) {
    return _request('GET', path, token: token, query: query, headers: headers);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    String? apiBaseUrl,
  }) {
    return _request(
      'POST',
      path,
      token: token,
      body: body,
      query: query,
      headers: headers,
      apiBaseUrl: apiBaseUrl,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    return _request('PATCH', path, token: token, body: body, headers: headers);
  }

  Future<Uint8List> getBytes(
    String path, {
    required String token,
    Map<String, String>? headers,
    int maxBytes = 10 * 1024 * 1024,
  }) async {
    final Uri uri = _buildUri(path);
    final HttpClient client = HttpClient();
    client.connectionTimeout = _requestTimeout;

    try {
      final HttpClientRequest request = await client
          .getUrl(uri)
          .timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'image/png');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      _setHeaders(request, headers);
      final HttpClientResponse response = await request.close().timeout(
        _requestTimeout,
      );
      final Uint8List bytes = await _readResponseBytes(
        response,
        maxBytes: maxBytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String text = utf8.decode(bytes, allowMalformed: true);
        final Map<String, dynamic> decoded = _decodeObject(text);
        throw ApiException(
          response.statusCode,
          decoded['message'] as String? ?? text,
          code: decoded['code'] as String?,
        );
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> postMultipartFile(
    String path, {
    required String token,
    required String fieldName,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final Uri uri = _buildUri(path);
    final HttpClient client = HttpClient();
    client.connectionTimeout = _requestTimeout;
    final String boundary =
        '----hitcon-nfc-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final List<int> prefix = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="${_escapeHeader(fieldName)}"; '
      'filename="${_escapeHeader(fileName)}"\r\n'
      'Content-Type: $contentType\r\n\r\n',
    );
    final List<int> suffix = utf8.encode('\r\n--$boundary--\r\n');

    try {
      final HttpClientRequest request = await client
          .postUrl(uri)
          .timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.contentLength = prefix.length + bytes.length + suffix.length;
      request.add(prefix);
      request.add(bytes);
      request.add(suffix);

      final HttpClientResponse response = await request.close().timeout(
        _requestTimeout,
      );
      final Map<String, dynamic> decoded = await _decodeJsonResponse(response);
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    String? apiBaseUrl,
  }) async {
    final Uri uri = _buildUri(path, query: query, apiBaseUrl: apiBaseUrl);
    final HttpClient client = HttpClient();
    client.connectionTimeout = _requestTimeout;

    try {
      final HttpClientRequest request = await client
          .openUrl(method, uri)
          .timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      _setHeaders(request, headers);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final HttpClientResponse response = await request.close().timeout(
        _requestTimeout,
      );
      final Map<String, dynamic> decoded = await _decodeJsonResponse(response);
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  Uri _buildUri(String path, {Map<String, String>? query, String? apiBaseUrl}) {
    final Uri base = Uri.parse(apiBaseUrl ?? AppConfig.apiBaseUrl);
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        base.userInfo.isNotEmpty) {
      throw const FormatException('API_BASE_URL must be a valid HTTPS origin.');
    }
    final String normalizedPath =
        '${base.path.replaceFirst(RegExp(r'/$'), '')}/${path.replaceFirst(RegExp(r'^/'), '')}';
    return base.replace(path: normalizedPath, queryParameters: query);
  }

  Future<Map<String, dynamic>> _decodeJsonResponse(
    HttpClientResponse response,
  ) async {
    final Uint8List responseBytes = await _readResponseBytes(
      response,
      maxBytes: _maxResponseBytes,
    );
    final String text = utf8.decode(responseBytes);
    final Map<String, dynamic> decoded = _decodeObject(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        decoded['message'] as String? ?? text,
        code: decoded['code'] as String?,
      );
    }
    return decoded;
  }

  Future<Uint8List> _readResponseBytes(
    HttpClientResponse response, {
    required int maxBytes,
  }) async {
    final BytesBuilder responseBytes = BytesBuilder(copy: false);
    await for (final List<int> chunk in response.timeout(_requestTimeout)) {
      if (responseBytes.length + chunk.length > maxBytes) {
        throw const FormatException('API response exceeds the size limit.');
      }
      responseBytes.add(chunk);
    }
    return responseBytes.takeBytes();
  }

  void _setHeaders(HttpClientRequest request, Map<String, String>? headers) {
    headers?.forEach((String name, String value) {
      if (name.trim().isNotEmpty && value.trim().isNotEmpty) {
        request.headers.set(name, value);
      }
    });
  }

  String _escapeHeader(String value) {
    return value.replaceAll(RegExp(r'[\r\n"]'), '_');
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
