import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

class NtagLockSecret {
  const NtagLockSecret({required this.password, required this.pack});

  final List<int> password;
  final List<int> pack;

  bool get isValid => password.length == 4 && pack.length == 2;
}

class NtagSecurityResult {
  const NtagSecurityResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class NtagSecurityService {
  const NtagSecurityService();

  String readTagId(NfcTag tag) {
    final Map<String, dynamic> data = tag.data;
    final dynamic idBytes =
        data['nfca']?['identifier'] ??
        data['mifareclassic']?['identifier'] ??
        data['mifareultralight']?['identifier'] ??
        data['mifare']?['identifier'];

    if (idBytes is! List) {
      return '';
    }
    return idBytes
        .whereType<int>()
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }

  Future<NtagSecurityResult> protectForRewrite(
    NfcTag tag,
    NtagLockSecret secret,
  ) async {
    if (!secret.isValid) {
      return const NtagSecurityResult(
        success: false,
        message: 'Server 回傳的 NTAG 鎖定密碼格式不正確',
      );
    }

    try {
      final _NtagAccess? access = await _loadAccess(tag);
      if (access == null) {
        return const NtagSecurityResult(
          success: false,
          message: '無法辨識 NTAG，請確認是 NTAG213/215/216',
        );
      }

      access.configPage[3] = 0x04; // Protect user memory from page 4 onward.
      access.accessPage[0] = access.accessPage[0] & 0x7F; // Write only.

      await _writePage(tag, access.pages.password, secret.password);
      await _writePage(tag, access.pages.pack, <int>[
        secret.pack[0],
        secret.pack[1],
        0x00,
        0x00,
      ]);
      await _writePage(tag, access.pages.access, access.accessPage);
      await _writePage(tag, access.pages.config, access.configPage);
      return const NtagSecurityResult(success: true, message: '已完成 NTAG 鎖定');
    } catch (error) {
      return NtagSecurityResult(success: false, message: 'NTAG 鎖定失敗：$error');
    }
  }

  Future<NtagSecurityResult> unlockForRewrite(
    NfcTag tag,
    NtagLockSecret secret,
  ) async {
    if (!secret.isValid) {
      return const NtagSecurityResult(
        success: false,
        message: 'Server 回傳的 NTAG 解鎖密碼格式不正確',
      );
    }

    try {
      final _NtagAccess? access = await _loadAccess(tag);
      if (access == null) {
        return const NtagSecurityResult(
          success: false,
          message: '無法辨識 NTAG，請確認是 NTAG213/215/216',
        );
      }

      final Uint8List? authResponse = await _transceive(tag, <int>[
        0x1B,
        ...secret.password,
      ]);
      if (authResponse == null ||
          authResponse.length < 2 ||
          authResponse[0] != secret.pack[0] ||
          authResponse[1] != secret.pack[1]) {
        return const NtagSecurityResult(
          success: false,
          message: '解鎖驗證失敗，Server 回傳的密碼可能不屬於這張 Tag',
        );
      }

      access.configPage[3] = 0xFF; // Disable password protection.
      access.accessPage[0] = access.accessPage[0] & 0x7F;

      await _writePage(tag, access.pages.config, access.configPage);
      await _writePage(tag, access.pages.access, access.accessPage);
      await _writePage(tag, access.pages.password, <int>[
        0xFF,
        0xFF,
        0xFF,
        0xFF,
      ]);
      await _writePage(tag, access.pages.pack, <int>[0x00, 0x00, 0x00, 0x00]);
      return const NtagSecurityResult(success: true, message: '已解鎖，可以重新寫入 Tag');
    } catch (error) {
      return NtagSecurityResult(success: false, message: 'NTAG 解鎖失敗：$error');
    }
  }

  Future<_NtagAccess?> _loadAccess(NfcTag tag) async {
    final Uint8List? version = await _transceive(tag, <int>[0x60]);
    if (version == null || version.length < 7) {
      return null;
    }

    final _NtagConfigPages? pages = _NtagConfigPages.fromStorageSize(
      version[6],
    );
    if (pages == null) {
      return null;
    }

    final Uint8List? configBytes = await _transceive(tag, <int>[
      0x30,
      pages.config,
    ]);
    if (configBytes == null || configBytes.length < 8) {
      return null;
    }

    return _NtagAccess(
      pages: pages,
      configPage: Uint8List.fromList(configBytes.sublist(0, 4)),
      accessPage: Uint8List.fromList(configBytes.sublist(4, 8)),
    );
  }

  Future<Uint8List?> _transceive(NfcTag tag, List<int> command) async {
    if (Platform.isIOS) {
      final MiFare? miFare = MiFare.from(tag);
      if (miFare == null || miFare.mifareFamily != MiFareFamily.ultralight) {
        return null;
      }
      return miFare.sendMiFareCommand(Uint8List.fromList(command));
    }

    if (Platform.isAndroid) {
      final MifareUltralight? ultralight = MifareUltralight.from(tag);
      if (ultralight != null) {
        return ultralight.transceive(data: Uint8List.fromList(command));
      }

      final NfcA? nfcA = NfcA.from(tag);
      if (nfcA != null) {
        return nfcA.transceive(data: Uint8List.fromList(command));
      }
    }

    return null;
  }

  Future<void> _writePage(NfcTag tag, int page, List<int> data) async {
    if (data.length != 4) {
      throw ArgumentError.value(data.length, 'data.length', 'must be 4');
    }

    final Uint8List? response = await _transceive(tag, <int>[
      0xA2,
      page,
      ...data,
    ]);
    if (Platform.isIOS) {
      return;
    }
    if (response == null || response.isEmpty || response.first != 0x0A) {
      throw StateError('NTAG write rejected page $page');
    }
  }
}

class _NtagAccess {
  const _NtagAccess({
    required this.pages,
    required this.configPage,
    required this.accessPage,
  });

  final _NtagConfigPages pages;
  final Uint8List configPage;
  final Uint8List accessPage;
}

class _NtagConfigPages {
  const _NtagConfigPages({
    required this.config,
    required this.access,
    required this.password,
    required this.pack,
  });

  final int config;
  final int access;
  final int password;
  final int pack;

  static _NtagConfigPages? fromStorageSize(int storageSize) {
    return switch (storageSize) {
      0x0F => const _NtagConfigPages(
        config: 0x29,
        access: 0x2A,
        password: 0x2B,
        pack: 0x2C,
      ),
      0x11 => const _NtagConfigPages(
        config: 0x83,
        access: 0x84,
        password: 0x85,
        pack: 0x86,
      ),
      0x13 => const _NtagConfigPages(
        config: 0xE3,
        access: 0xE4,
        password: 0xE5,
        pack: 0xE6,
      ),
      _ => null,
    };
  }
}
