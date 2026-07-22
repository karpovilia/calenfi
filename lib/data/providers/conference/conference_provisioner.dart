import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../domain/models/account.dart';
import '../../../domain/models/calendar_event.dart';
import '../../../domain/models/conference.dart';
import '../../../domain/models/enums.dart';
import '../../repositories/event_repository.dart';
import '../../secure/credential_source.dart';
import '../calendar/google/google_token.dart';
import '../calendar/graph/graph_token.dart';

/// Конференцию нужного типа завести негде (нет УЗ / кредов / прав). Сообщение —
/// человекочитаемое, показывается пользователю/агенту.
class ConferenceUnavailableException implements Exception {
  ConferenceUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'ConferenceUnavailableException: $message';
}

/// Развязка провижининга видеовстреч от календаря (FR-M1/M3).
///
/// Пользователь выбирает тип (Teams/Meet/Zoom/Telemost) для события в ЛЮБОМ
/// календаре — система идёт в соответствующую УЗ и заводит реальную встречу.
///
/// Гибрид:
///  • тот же аккаунт умеет нативно (Teams↔O365 Graph, Meet↔Google) — отдаём
///    «нативный» маркер (пустой joinUrl), встречу создаёт сам провайдер
///    календаря при createEvent, без отдельных прав;
///  • иначе (кросс-аккаунт) — заводим отдельным API нужной УЗ.
class ConferenceProvisioner {
  ConferenceProvisioner({Dio? dio, CredentialSource? credentials})
      : _dio = dio ?? Dio(),
        _creds = credentials ?? CredentialSource.load();

  final Dio _dio;
  final CredentialSource _creds;

  /// Умеет ли провайдер календаря [target] завести конференцию [type] нативно
  /// в самом событии (без отдельного API/прав): Graph→Teams, Google→Meet.
  static bool nativeCapable(ConferenceType type, Account? target) {
    if (target == null) return false;
    return (type == ConferenceType.teams &&
            target.provider == ProviderType.graph) ||
        (type == ConferenceType.meet && target.provider == ProviderType.google);
  }

  /// Если у [e] «ожидающая» конференция (пустой joinUrl) — заводит её и, для
  /// кросс-аккаунтного случая, возвращает событие с реальной ссылкой (и
  /// сохраняет его локально). Нативный случай возвращает [e] как есть (встречу
  /// заведёт провайдер календаря). Бросает [ConferenceUnavailableException].
  Future<CalendarEvent> ensure(
    CalendarEvent e, {
    required Account target,
    required List<Account> allAccounts,
    required EventRepository events,
  }) async {
    final conf = e.conference;
    if (conf == null || conf.isReady) return e; // нечего заводить / уже готова
    final resolved = await resolve(
      conf.type,
      target: target,
      allAccounts: allAccounts,
      start: e.startUtc,
      end: e.endUtc,
      subject: e.title,
    );
    if (!resolved.isReady) return e; // нативно — пусть провайдер календаря
    final updated = e.copyWith(conference: resolved);
    await events.putLocalDirty(updated);
    return updated;
  }

  /// Готовит конференцию [type] для события в календаре [target].
  Future<Conference> resolve(
    ConferenceType type, {
    required Account? target,
    required List<Account> allAccounts,
    required DateTime start,
    required DateTime end,
    required String subject,
  }) async {
    if (nativeCapable(type, target)) {
      return Conference.pending(type); // маркер «завести нативно»
    }
    switch (type) {
      case ConferenceType.teams:
        return _teams(allAccounts, start, end, subject);
      case ConferenceType.meet:
        return _meet(allAccounts);
      case ConferenceType.zoom:
        return _zoom(start, end, subject);
      case ConferenceType.telemost:
        return _telemost();
      case ConferenceType.unknown:
        throw ConferenceUnavailableException('Неизвестный тип конференции');
    }
  }

  Account? _firstOf(List<Account> accounts, ProviderType p) {
    for (final a in accounts) {
      if (a.provider == p) return a;
    }
    return null;
  }

  /// Teams standalone: POST /me/onlineMeetings (scope OnlineMeetings.ReadWrite).
  Future<Conference> _teams(
      List<Account> accounts, DateTime start, DateTime end, String subject) async {
    final acc = _firstOf(accounts, ProviderType.graph);
    if (acc == null) {
      throw ConferenceUnavailableException(
          'Нет подключённого O365-аккаунта для встречи Teams');
    }
    final token = GraphToken.loadFor(acc.email);
    if (token == null) {
      throw ConferenceUnavailableException(
          'Нет токена Teams для ${acc.email} — переподключи аккаунт');
    }
    final at = await token.accessTokenValid(_dio);
    try {
      final resp = await _dio.post(
        'https://graph.microsoft.com/v1.0/me/onlineMeetings',
        data: {
          'startDateTime': start.toUtc().toIso8601String(),
          'endDateTime': end.toUtc().toIso8601String(),
          'subject': subject,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $at'},
          contentType: Headers.jsonContentType,
        ),
      );
      final m = resp.data as Map<String, dynamic>;
      final url = m['joinWebUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw ConferenceUnavailableException('Teams не вернул ссылку встречи');
      }
      return Conference(
          type: ConferenceType.teams, joinUrl: url, meetingId: m['id'] as String?);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw ConferenceUnavailableException(
            'Teams: нет прав OnlineMeetings.ReadWrite — переавторизуй O365 (${acc.email})');
      }
      rethrow;
    }
  }

  /// Google Meet standalone: POST meet/v2/spaces (scope meetings.space.created).
  Future<Conference> _meet(List<Account> accounts) async {
    final acc = _firstOf(accounts, ProviderType.google);
    if (acc == null) {
      throw ConferenceUnavailableException(
          'Нет подключённого Google-аккаунта для Meet');
    }
    final token = GoogleToken.loadFor(acc.email);
    if (token == null) {
      throw ConferenceUnavailableException(
          'Нет токена Google для ${acc.email} — переподключи аккаунт');
    }
    final at = await token.accessTokenValid(_dio);
    try {
      final resp = await _dio.post(
        'https://meet.googleapis.com/v2/spaces',
        data: const <String, dynamic>{},
        options: Options(
          headers: {'Authorization': 'Bearer $at'},
          contentType: Headers.jsonContentType,
        ),
      );
      final m = resp.data as Map<String, dynamic>;
      final url = m['meetingUri'] as String?;
      if (url == null || url.isEmpty) {
        throw ConferenceUnavailableException('Meet не вернул ссылку');
      }
      return Conference(
          type: ConferenceType.meet,
          joinUrl: url,
          meetingId: m['meetingCode'] as String?);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw ConferenceUnavailableException(
            'Meet: нет scope meetings.space.created — переавторизуй Google (${acc.email})');
      }
      rethrow;
    }
  }

  /// Zoom через Server-to-Server OAuth: получаем access-токен по
  /// account_credentials, затем создаём запланированную встречу.
  Future<Conference> _zoom(
      DateTime start, DateTime end, String subject) async {
    final accountId = _creds.zoomAccountId;
    final clientId = _creds.zoomClientId;
    final clientSecret = _creds.zoomClientSecret;
    if (accountId == null || clientId == null || clientSecret == null) {
      throw ConferenceUnavailableException(
          'Zoom не настроен: добавь ZOOM_ACCOUNT_ID / ZOOM_CLIENT_ID / '
          'ZOOM_CLIENT_SECRET (Server-to-Server OAuth) в tools/secrets.env');
    }
    // 1) access-токен (grant account_credentials, Basic client_id:secret).
    final String at;
    try {
      final basic = base64Encode(utf8.encode('$clientId:$clientSecret'));
      final tok = await _dio.post(
        'https://zoom.us/oauth/token',
        queryParameters: {
          'grant_type': 'account_credentials',
          'account_id': accountId,
        },
        options: Options(
          headers: {'Authorization': 'Basic $basic'},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      final token = (tok.data as Map)['access_token'] as String?;
      if (token == null || token.isEmpty) {
        throw ConferenceUnavailableException(
            'Zoom не выдал токен — проверь Account ID / Client ID / Secret');
      }
      at = token;
    } on DioException catch (e) {
      throw ConferenceUnavailableException(
          'Zoom OAuth не прошёл (${e.response?.statusCode}) — проверь '
          'ZOOM_ACCOUNT_ID / ZOOM_CLIENT_ID / ZOOM_CLIENT_SECRET');
    }
    // 2) создаём встречу (type 2 — scheduled).
    try {
      final duration = end.difference(start).inMinutes.clamp(1, 1440);
      final resp = await _dio.post(
        'https://api.zoom.us/v2/users/me/meetings',
        data: {
          'topic': subject,
          'type': 2,
          'start_time': start.toUtc().toIso8601String(),
          'duration': duration,
          'timezone': 'UTC',
        },
        options: Options(
          headers: {'Authorization': 'Bearer $at'},
          contentType: Headers.jsonContentType,
        ),
      );
      final m = resp.data as Map<String, dynamic>;
      final url = m['join_url'] as String?;
      if (url == null || url.isEmpty) {
        throw ConferenceUnavailableException('Zoom не вернул join_url');
      }
      return Conference(
        type: ConferenceType.zoom,
        joinUrl: url,
        meetingId: m['id']?.toString(),
        password: m['password'] as String?,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw ConferenceUnavailableException(
            'Zoom: нет прав на создание встреч — добавь scope meeting:write в '
            'Server-to-Server OAuth app');
      }
      rethrow;
    }
  }

  Future<Conference> _telemost() async {
    throw ConferenceUnavailableException(
        'Telemost пока не настроен: нужен Yandex OAuth '
        'со scope telemost-api:conferences.create');
  }
}
