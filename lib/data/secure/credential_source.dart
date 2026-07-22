import 'secret_store.dart';

/// Источник секретов (паролей приложений, ключей API) поверх системного keyring.
///
/// Значения берутся из синхронного кеша [SecretStore], который наполняется один
/// раз на старте (`await SecretStore.instance.warmUp()` в `main()` и в CLI).
/// Имена ключей — как раньше: email в ВЕРХНЕМ регистре, не-алфанум → '_'
/// (совпадает с `tools/extract_contacts.py`), поэтому старый `secrets.env`
/// импортируется в keyring один-в-один.
class CredentialSource {
  CredentialSource._(this._values);

  /// Пустой источник (для тестов / когда секретов заведомо нет).
  factory CredentialSource.empty() => CredentialSource._({});

  /// Источник с явными значениями (тесты).
  factory CredentialSource.fromMap(Map<String, String> values) =>
      CredentialSource._(Map.of(values));

  final Map<String, String> _values;

  /// Снимок секретов из keyring-кеша.
  static CredentialSource load() =>
      CredentialSource._(Map.of(SecretStore.instance.all));

  /// Нормализованный префикс переменных для e-mail (ВЕРХНИЙ регистр,
  /// не-алфанум → '_'). Совпадает с `tools/extract_contacts.py`.
  static String keyFor(String email) =>
      email.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');

  /// Имена ключей пароля — используются и на запись.
  static String caldavPasswordVar(String email) => '${keyFor(email)}_CALDAV_PASSWORD';
  static String ewsPasswordVar(String email) => '${keyFor(email)}_EWS_PASSWORD';

  String _key(String email) => keyFor(email);

  /// Пароль приложения для CalDAV/CardDAV (Yandex и т.п.).
  String? caldavPassword(String email) {
    final k = _key(email);
    return _nonEmpty(_values['${k}_CALDAV_PASSWORD']) ??
        _nonEmpty(_values['${k}_APP_PASSWORD']);
  }

  /// Пароль для Exchange EWS.
  String? ewsPassword(String email) => _nonEmpty(_values['${_key(email)}_EWS_PASSWORD']);
  String? ewsUrl(String email) => _nonEmpty(_values['${_key(email)}_EWS_URL']);
  String? ewsUser(String email) => _nonEmpty(_values['${_key(email)}_EWS_USER']);

  /// Zoom Server-to-Server OAuth (создание видеовстреч). Глобальные ключи —
  /// один Zoom-app на всё приложение (не per-email).
  String? get zoomAccountId => _nonEmpty(_values['ZOOM_ACCOUNT_ID']);
  String? get zoomClientId => _nonEmpty(_values['ZOOM_CLIENT_ID']);
  String? get zoomClientSecret => _nonEmpty(_values['ZOOM_CLIENT_SECRET']);

  static String? _nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;
}

/// Запись/обновление одного секрета в системном keyring.
///
/// После записи нужно пере-создать провайдеры (invalidate
/// `providerRegistryProvider`), чтобы новый пароль подхватился.
Future<void> writeSecret(String key, String value) =>
    SecretStore.instance.write(key, value);
