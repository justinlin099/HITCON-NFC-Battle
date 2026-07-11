import 'package:flutter/services.dart';

const String httpsLinkPrefix = 'https://';

enum HttpsLinkValidationError { malformed, unsafe }

String httpsLinkBody(String value) {
  return value.trim().replaceFirst(
    RegExp(r'^(?:https?://)+', caseSensitive: false),
    '',
  );
}

String buildHttpsLink(String body) {
  final String normalized = httpsLinkBody(body);
  return normalized.isEmpty ? '' : '$httpsLinkPrefix$normalized';
}

HttpsLinkValidationError? validateHttpsLink(String value) {
  final String body = httpsLinkBody(value);
  if (body.isEmpty) {
    return null;
  }

  final String fullUrl = buildHttpsLink(body);
  if (fullUrl.length > 2048 || fullUrl.contains('\\')) {
    return HttpsLinkValidationError.malformed;
  }

  final Uri? uri = Uri.tryParse(fullUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return HttpsLinkValidationError.malformed;
  }

  try {
    final String decoded = Uri.decodeFull(fullUrl);
    if (RegExp(r'[\u0000-\u001F\u007F]').hasMatch(decoded)) {
      return HttpsLinkValidationError.malformed;
    }
  } on FormatException {
    return HttpsLinkValidationError.malformed;
  }

  final String host = uri.host.toLowerCase();
  final List<String> labels = host.split('.');
  final RegExp validLabel = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
    caseSensitive: false,
  );
  final bool isIpAddress =
      host.contains(':') ||
      labels.every((String label) => int.tryParse(label) != null);
  final bool isLocalHost =
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local');
  final bool hasInvalidDomain =
      host.length > 253 ||
      labels.length < 2 ||
      labels.any((String label) => !validLabel.hasMatch(label));
  final bool hasUnsafePort = uri.hasPort && uri.port != 443;
  if (isIpAddress || isLocalHost || hasInvalidDomain || hasUnsafePort) {
    return HttpsLinkValidationError.unsafe;
  }
  return null;
}

class HttpsLinkInputFormatter extends TextInputFormatter {
  const HttpsLinkInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String normalized = httpsLinkBody(newValue.text);
    if (normalized == newValue.text) {
      return newValue;
    }
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}
