int? readPhishingCount(Map<String, dynamic>? profile) {
  final Object? value = profile?['phishing_count'];
  if (value is! num || !value.isFinite || value < 0) {
    return null;
  }

  final int count = value.toInt();
  return value == count ? count : null;
}
