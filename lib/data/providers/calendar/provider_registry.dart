import '../../../domain/models/account.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/providers/calendar_provider.dart';
import '../../secure/credential_source.dart';
import 'caldav/caldav_provider.dart';
import 'empty_provider.dart';
import 'ews/ews_provider.dart';
import 'google/google_provider.dart';
import 'google/google_token.dart';
import 'graph/graph_provider.dart';
import 'graph/graph_token.dart';

/// Сопоставляет учётную запись с адаптером (docs/architecture.md §6).
///
/// Реальные адаптеры подключаются, когда для аккаунта есть креды; иначе —
/// [EmptyProvider]. Инстансы кэшируются по accountId.
class ProviderRegistry {
  ProviderRegistry({CredentialSource? credentials, this.overrideFactory})
      : _credentials = credentials ?? CredentialSource.load();

  final CredentialSource _credentials;

  /// Тест-инъекция: если задано — используется вместо реального резолва.
  final CalendarProvider Function(Account)? overrideFactory;

  final Map<String, CalendarProvider> _cache = {};

  CalendarProvider forAccount(Account acc) {
    final override = overrideFactory;
    if (override != null) return override(acc);
    return _cache.putIfAbsent(acc.id, () => _create(acc));
  }

  CalendarProvider _create(Account acc) {
    switch (acc.provider) {
      case ProviderType.caldav:
        final pass = _credentials.caldavPassword(acc.email);
        if (pass != null) {
          return CalDavProvider(account: acc, password: pass);
        }
      case ProviderType.google:
        final token = GoogleToken.loadFor(acc.email);
        if (token != null) {
          return GoogleProvider(account: acc, token: token);
        }
      case ProviderType.ews:
        // EWS теперь через НАТИВНЫЙ NTLM (NtlmHttp), без curl — работает и на
        // мобиле. Спец-заглушки больше не нужно.
        final pass = _credentials.ewsPassword(acc.email);
        if (pass != null) {
          return EwsProvider(
            account: acc,
            password: pass,
            user: _credentials.ewsUser(acc.email),
            ewsUrlOverride: _credentials.ewsUrl(acc.email) ?? acc.config.ewsUrl,
          );
        }
      case ProviderType.graph:
        final token = GraphToken.loadFor(acc.email);
        if (token != null) {
          return GraphProvider(account: acc, token: token);
        }
    }
    // Реальный аккаунт без кредов (напр. O365 до авторизации) — пустой провайдер,
    // без мок-шума. Аккаунт виден, события появятся после подключения.
    return EmptyProvider(acc.provider);
  }
}
