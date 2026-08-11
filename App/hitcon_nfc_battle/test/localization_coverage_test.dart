import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/l10n/strings_en.dart';
import 'package:hitcon_nfc_battle/l10n/strings_ja.dart';
import 'package:hitcon_nfc_battle/l10n/strings_ko.dart';
import 'package:hitcon_nfc_battle/l10n/strings_zh_tw.dart';
import 'package:hitcon_nfc_battle/main.dart';

final RegExp _placeholderPattern = RegExp(r'\{[^}]+\}');

void main() {
  test(
    'Japanese and Korean are supported and selected from device locales',
    () {
      expect(
        AppLocalizations.supportedLocales,
        containsAll(<Locale>[const Locale('ja'), const Locale('ko')]),
      );
      expect(
        AppLocalizations.delegate.isSupported(const Locale('ja', 'JP')),
        isTrue,
      );
      expect(
        AppLocalizations.delegate.isSupported(const Locale('ko', 'KR')),
        isTrue,
      );
      expect(
        resolveAppLocale(const <Locale>[
          Locale('ja', 'JP'),
        ], AppLocalizations.supportedLocales),
        const Locale('ja'),
      );
      expect(
        resolveAppLocale(const <Locale>[
          Locale('ko', 'KR'),
        ], AppLocalizations.supportedLocales),
        const Locale('ko'),
      );
    },
  );

  test('every locale covers all keys and preserves dynamic placeholders', () {
    final Set<String> englishKeys = appStringsEn.keys.toSet();
    for (final Map<String, String> strings in <Map<String, String>>[
      appStringsZhTw,
      appStringsJa,
      appStringsKo,
    ]) {
      expect(strings.keys.toSet(), englishKeys);
      for (final String key in englishKeys) {
        final String value = strings[key]!;
        expect(value.trim(), isNotEmpty, reason: key);
        expect(value, isNot(contains('ZXQ')), reason: key);
        expect(
          _placeholders(value),
          _placeholders(appStringsEn[key]!),
          reason: key,
        );
      }
    }
  });

  test('Japanese and Korean use localized attendee navigation', () {
    expect(const AppLocalizations(Locale('ja')).tr('collectionTab'), 'カード');
    expect(const AppLocalizations(Locale('ko')).tr('collectionTab'), '카드');
    expect(
      const AppLocalizations(Locale('ja')).tr('appTitle'),
      'HITCON NFC Battle',
    );
    expect(
      const AppLocalizations(Locale('ko')).tr('appTitle'),
      'HITCON NFC Battle',
    );
  });

  test('native platforms declare Japanese and Korean support', () {
    final String androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final String androidLocales = File(
      'android/app/src/main/res/xml/locales_config.xml',
    ).readAsStringSync();
    final String iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(
      androidManifest,
      contains('android:localeConfig="@xml/locales_config"'),
    );
    expect(androidLocales, contains('android:name="ja"'));
    expect(androidLocales, contains('android:name="ko"'));
    expect(iosProject, contains('ja.lproj/InfoPlist.strings'));
    expect(iosProject, contains('ko.lproj/InfoPlist.strings'));
  });
}

List<String> _placeholders(String value) {
  final List<String> placeholders = _placeholderPattern
      .allMatches(value)
      .map((Match match) => match.group(0)!)
      .toList();
  placeholders.sort();
  return placeholders;
}
