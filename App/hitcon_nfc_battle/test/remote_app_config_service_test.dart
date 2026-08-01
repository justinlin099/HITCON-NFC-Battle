import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/config/app_config.dart';
import 'package:hitcon_nfc_battle/services/remote_app_config_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppConfig.resetApiBaseUrlForTesting();
  });

  tearDown(AppConfig.resetApiBaseUrlForTesting);

  test('applies and caches a trusted remote API URL', () async {
    Uri? requestedUri;
    final RemoteAppConfigService service = RemoteAppConfigService(
      configUri: Uri.parse(
        'https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json',
      ),
      loader: (Uri uri) async {
        requestedUri = uri;
        return '{"schema":1,"api_base_url":"https://nfc-battle.hitcon2026.online/v1/","allow_user_tag_unlock":false,"show_panasonic_logo":false,"show_panasonic_logo_on_print":true}';
      },
    );

    expect(await service.refresh(force: true), isTrue);
    expect(requestedUri, service.configUri);
    expect(AppConfig.apiBaseUrl, 'https://nfc-battle.hitcon2026.online/v1');
    expect(AppConfig.allowUserTagUnlock, isFalse);
    expect(AppConfig.allowUserTagUnlockListenable.value, isFalse);
    expect(AppConfig.showPanasonicLogo, isFalse);
    expect(AppConfig.showPanasonicLogoListenable.value, isFalse);
    expect(AppConfig.showPanasonicLogoOnPrint, isTrue);
    expect(AppConfig.showPanasonicLogoOnPrintListenable.value, isTrue);

    AppConfig.resetApiBaseUrlForTesting();
    final RemoteAppConfigService offlineService = RemoteAppConfigService(
      loader: (_) async => throw StateError('offline'),
    );
    expect(await offlineService.refresh(force: true), isFalse);
    expect(AppConfig.apiBaseUrl, 'https://nfc-battle.hitcon2026.online/v1');
    expect(AppConfig.allowUserTagUnlock, isFalse);
    expect(AppConfig.showPanasonicLogo, isFalse);
    expect(AppConfig.showPanasonicLogoOnPrint, isTrue);
  });

  test('rejects a non-boolean Panasonic logo flag', () async {
    final RemoteAppConfigService service = RemoteAppConfigService(
      loader: (_) async =>
          '{"schema":1,"api_base_url":"https://nfc-battle.hitcon2026.online","show_panasonic_logo":"yes"}',
    );

    expect(await service.refresh(force: true), isFalse);
    expect(AppConfig.showPanasonicLogo, isTrue);
    expect(AppConfig.showPanasonicLogoOnPrint, isTrue);
  });

  test('rejects a non-boolean print Panasonic logo flag', () async {
    final RemoteAppConfigService service = RemoteAppConfigService(
      loader: (_) async =>
          '{"schema":1,"api_base_url":"https://nfc-battle.hitcon2026.online","show_panasonic_logo_on_print":"yes"}',
    );

    expect(await service.refresh(force: true), isFalse);
    expect(AppConfig.showPanasonicLogo, isTrue);
    expect(AppConfig.showPanasonicLogoOnPrint, isTrue);
  });

  test(
    'legacy Panasonic flag also controls print when new flag is absent',
    () async {
      final RemoteAppConfigService service = RemoteAppConfigService(
        loader: (_) async =>
            '{"schema":1,"api_base_url":"https://nfc-battle.hitcon2026.online","show_panasonic_logo":false}',
      );

      expect(await service.refresh(force: true), isTrue);
      expect(AppConfig.showPanasonicLogo, isFalse);
      expect(AppConfig.showPanasonicLogoOnPrint, isFalse);
    },
  );

  test('rejects an API URL outside the trusted HITCON domain', () async {
    final RemoteAppConfigService service = RemoteAppConfigService(
      loader: (_) async =>
          '{"schema":1,"api_base_url":"https://hitcon2026.online.attacker.example"}',
    );

    expect(await service.refresh(force: true), isFalse);
    expect(AppConfig.apiBaseUrl, AppConfig.bundledApiBaseUrl);
  });

  test('rejects unsupported config schemas', () async {
    final RemoteAppConfigService service = RemoteAppConfigService(
      loader: (_) async =>
          '{"schema":2,"api_base_url":"https://nfc-battle.hitcon2026.online"}',
    );

    expect(await service.refresh(force: true), isFalse);
    expect(AppConfig.apiBaseUrl, AppConfig.bundledApiBaseUrl);
  });
}
