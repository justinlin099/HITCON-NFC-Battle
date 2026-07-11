import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'strings_en.dart';
import 'strings_zh_tw.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  Map<String, String> get _strings {
    return locale.languageCode == 'zh' ? appStringsZhTw : appStringsEn;
  }

  String tr(String key, [Map<String, Object?> values = const {}]) {
    String result = _strings[key] ?? appStringsEn[key] ?? key;
    for (final MapEntry<String, Object?> entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == 'en' || locale.languageCode == 'zh';
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
