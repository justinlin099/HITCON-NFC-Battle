import 'dart:convert';

class CardBioData {
  const CardBioData({required this.bio, this.link = '', this.cardColor});

  final String bio;
  final String link;
  final int? cardColor;
}

class CardBioCodec {
  const CardBioCodec();

  static const String _prefix = '[[HITCON_CARD:v1:';
  static const String _suffix = ']]';

  String encode({
    required String bio,
    required String link,
    required Object? cardColor,
  }) {
    final CardBioData previous = decode(bio);
    final String cleanBio = previous.bio.trim();
    final String cleanLink = link.trim();
    final int? color = _parseColor(cardColor);
    final Map<String, dynamic> metadata = <String, dynamic>{
      if (_isUsefulLink(cleanLink)) 'l': cleanLink,
    };
    if (color != null) {
      metadata['c'] = color;
    }
    if (metadata.isEmpty) {
      return cleanBio;
    }

    final String payload = base64Url
        .encode(utf8.encode(jsonEncode(metadata)))
        .replaceAll('=', '');
    final String encodedMetadata = '$_prefix$payload$_suffix';
    return cleanBio.isEmpty ? encodedMetadata : '$cleanBio\n\n$encodedMetadata';
  }

  CardBioData decode(Object? rawBio) {
    final String value = rawBio is String ? rawBio : '';
    final int markerStart = value.lastIndexOf(_prefix);
    if (markerStart < 0 || !value.endsWith(_suffix)) {
      return CardBioData(bio: value);
    }

    final int payloadStart = markerStart + _prefix.length;
    final int payloadEnd = value.length - _suffix.length;
    if (payloadStart >= payloadEnd) {
      return CardBioData(bio: value);
    }

    try {
      final String payload = value.substring(payloadStart, payloadEnd);
      final String padded = payload.padRight(
        payload.length + ((4 - payload.length % 4) % 4),
        '=',
      );
      final Object? decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is! Map) {
        return CardBioData(bio: value);
      }
      final Map<String, dynamic> metadata = Map<String, dynamic>.from(decoded);
      final String bio = value.substring(0, markerStart).trimRight();
      return CardBioData(
        bio: bio,
        link: metadata['l'] is String ? metadata['l'] as String : '',
        cardColor: _parseColor(metadata['c']),
      );
    } on FormatException {
      return CardBioData(bio: value);
    }
  }

  bool _isUsefulLink(String link) {
    return link.isNotEmpty && link != 'https://' && link != 'http://';
  }

  int? _parseColor(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}
