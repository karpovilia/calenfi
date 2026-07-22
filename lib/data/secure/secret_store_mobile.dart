import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secret_store.dart';

/// Бэкенд [SecretStore] для Android/iOS: там нет `secret-tool`/`security`,
/// поэтому используем flutter_secure_storage (EncryptedSharedPreferences /
/// Keychain). Файл импортируется только из UI-слоя — CLI остаётся чистым Dart.
class MobileSecureStorageBackend extends KeyringBackend {
  const MobileSecureStorageBackend();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _key = '${KeyringBackend.service}.${KeyringBackend.account}';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}
