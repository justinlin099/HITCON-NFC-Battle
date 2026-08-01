import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalPrintOrder {
  const LocalPrintOrder({
    required this.id,
    required this.barcodeValue,
    required this.fileName,
    required this.format,
  });

  final String id;
  final String barcodeValue;
  final String fileName;
  final String format;

  Map<String, String> toJson() => <String, String>{
    'id': id,
    'barcode_value': barcodeValue,
    'file_name': fileName,
    'format': format,
  };

  static LocalPrintOrder? fromJson(Object? source) {
    if (source is! Map<String, dynamic>) {
      return null;
    }
    final String id = (source['id'] as String? ?? '').trim();
    final String barcodeValue = (source['barcode_value'] as String? ?? '')
        .trim();
    if (id.isEmpty || barcodeValue.isEmpty) {
      return null;
    }
    return LocalPrintOrder(
      id: id,
      barcodeValue: barcodeValue,
      fileName: (source['file_name'] as String? ?? 'hitcon-nfc-card-$id.png')
          .trim(),
      format: (source['format'] as String? ?? 'EVOLIS_PRIMACY_CR80_300DPI_PNG')
          .trim(),
    );
  }
}

class LocalPrintOrderStore {
  static const String _prefix = 'local_print_order_v1';

  Future<LocalPrintOrder?> load(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      return LocalPrintOrder.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<bool> save(String userId, LocalPrintOrder order) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.setString(_key(userId), jsonEncode(order.toJson()));
    } catch (_) {
      return false;
    }
  }

  String _key(String userId) => '$_prefix:$userId';
}
