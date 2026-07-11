import 'dart:convert';
import 'dart:typed_data';

import '../config/app_config.dart';

class StagingJwtService {
  const StagingJwtService();

  String createToken({required String userId, required String role}) {
    if (AppConfig.jwtSecret.isEmpty) {
      throw StateError('JWT_SECRET is required for staging API login.');
    }

    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final Map<String, Object> header = <String, Object>{
      'alg': 'HS256',
      'typ': 'JWT',
    };
    final Map<String, Object> payload = <String, Object>{
      'sub': userId,
      'role': role,
      'iss': AppConfig.jwtIssuer,
      'aud': AppConfig.jwtAudience,
      'iat': now,
      'exp': now + 60 * 60 * 24 * 7,
    };

    final String encodedHeader = _base64UrlJson(header);
    final String encodedPayload = _base64UrlJson(payload);
    final String signingInput = '$encodedHeader.$encodedPayload';
    final List<int> signature = _hmacSha256(
      utf8.encode(AppConfig.jwtSecret),
      utf8.encode(signingInput),
    );
    return '$signingInput.${base64Url.encode(signature).replaceAll('=', '')}';
  }

  String _base64UrlJson(Map<String, Object> data) {
    return base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  }

  List<int> _hmacSha256(List<int> key, List<int> message) {
    const int blockSize = 64;
    List<int> normalizedKey = key;
    if (normalizedKey.length > blockSize) {
      normalizedKey = _sha256(normalizedKey);
    }
    if (normalizedKey.length < blockSize) {
      normalizedKey = <int>[
        ...normalizedKey,
        ...List<int>.filled(blockSize - normalizedKey.length, 0),
      ];
    }

    final List<int> outer = List<int>.filled(blockSize, 0);
    final List<int> inner = List<int>.filled(blockSize, 0);
    for (int i = 0; i < blockSize; i += 1) {
      outer[i] = normalizedKey[i] ^ 0x5C;
      inner[i] = normalizedKey[i] ^ 0x36;
    }

    return _sha256(<int>[
      ...outer,
      ..._sha256(<int>[...inner, ...message]),
    ]);
  }

  List<int> _sha256(List<int> input) {
    final List<int> bytes = <int>[...input, 0x80];
    while ((bytes.length % 64) != 56) {
      bytes.add(0);
    }

    final int bitLengthHigh = input.length ~/ 0x20000000;
    final int bitLengthLow = (input.length * 8) & 0xFFFFFFFF;
    bytes.addAll(<int>[
      (bitLengthHigh >> 24) & 0xFF,
      (bitLengthHigh >> 16) & 0xFF,
      (bitLengthHigh >> 8) & 0xFF,
      bitLengthHigh & 0xFF,
      (bitLengthLow >> 24) & 0xFF,
      (bitLengthLow >> 16) & 0xFF,
      (bitLengthLow >> 8) & 0xFF,
      bitLengthLow & 0xFF,
    ]);

    int h0 = 0x6A09E667;
    int h1 = 0xBB67AE85;
    int h2 = 0x3C6EF372;
    int h3 = 0xA54FF53A;
    int h4 = 0x510E527F;
    int h5 = 0x9B05688C;
    int h6 = 0x1F83D9AB;
    int h7 = 0x5BE0CD19;

    for (int chunk = 0; chunk < bytes.length; chunk += 64) {
      final List<int> w = List<int>.filled(64, 0);
      for (int i = 0; i < 16; i += 1) {
        final int j = chunk + i * 4;
        w[i] =
            (bytes[j] << 24) |
            (bytes[j + 1] << 16) |
            (bytes[j + 2] << 8) |
            bytes[j + 3];
      }
      for (int i = 16; i < 64; i += 1) {
        final int s0 =
            _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final int s1 =
            _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = _u32(w[i - 16] + s0 + w[i - 7] + s1);
      }

      int a = h0;
      int b = h1;
      int c = h2;
      int d = h3;
      int e = h4;
      int f = h5;
      int g = h6;
      int h = h7;

      for (int i = 0; i < 64; i += 1) {
        final int s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final int ch = (e & f) ^ ((~e) & g);
        final int temp1 = _u32(h + s1 + ch + _k[i] + w[i]);
        final int s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final int maj = (a & b) ^ (a & c) ^ (b & c);
        final int temp2 = _u32(s0 + maj);

        h = g;
        g = f;
        f = e;
        e = _u32(d + temp1);
        d = c;
        c = b;
        b = a;
        a = _u32(temp1 + temp2);
      }

      h0 = _u32(h0 + a);
      h1 = _u32(h1 + b);
      h2 = _u32(h2 + c);
      h3 = _u32(h3 + d);
      h4 = _u32(h4 + e);
      h5 = _u32(h5 + f);
      h6 = _u32(h6 + g);
      h7 = _u32(h7 + h);
    }

    final Uint8List digest = Uint8List(32);
    final List<int> words = <int>[h0, h1, h2, h3, h4, h5, h6, h7];
    for (int i = 0; i < words.length; i += 1) {
      digest[i * 4] = (words[i] >> 24) & 0xFF;
      digest[i * 4 + 1] = (words[i] >> 16) & 0xFF;
      digest[i * 4 + 2] = (words[i] >> 8) & 0xFF;
      digest[i * 4 + 3] = words[i] & 0xFF;
    }
    return digest;
  }

  int _rotr(int value, int shift) {
    return _u32((value >> shift) | (value << (32 - shift)));
  }

  int _u32(int value) => value & 0xFFFFFFFF;

  static final List<int> _k = List<int>.unmodifiable(<int>[
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA2BFE8A1,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
  ]);
}
