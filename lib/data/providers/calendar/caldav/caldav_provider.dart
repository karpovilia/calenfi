import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';
import 'package:rrule/rrule.dart';
import 'package:xml/xml.dart';

import '../../../../domain/models/account.dart';
import '../../../../domain/models/attendee.dart';
import '../../../../domain/models/calendar.dart';
import '../../../../domain/models/calendar_event.dart';
import '../../../../domain/models/conference.dart';
import '../../../../domain/models/enums.dart';
import '../../../../domain/providers/calendar_provider.dart';
import '../../../../domain/providers/provider_capabilities.dart';
import 'ics.dart';

/// Реальный адаптер CalDAV (Yandex и совместимые). App-password + Basic auth.
/// Параметры host/port/principal — из [Account.config] (FR-A3).
class CalDavProvider implements CalendarProvider {
  CalDavProvider({required this.account, required this.password, Dio? dio})
      : _dio = dio ?? Dio() {
    _dio.options
      ..validateStatus = ((s) => s != null && s < 500)
      ..connectTimeout = const Duration(seconds: 20)
      ..sendTimeout = const Duration(seconds: 30)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers['Authorization'] = _basic
      ..headers['Content-Type'] = 'application/xml; charset=utf-8';
  }

  final Account account;
  final String password;
  final Dio _dio;

  String get _basic =>
      'Basic ${base64.encode(utf8.encode('${account.email}:$password'))}';

  String get _base {
    final host = account.config.caldavHost ?? 'caldav.yandex.ru';
    final port = account.config.caldavPort ?? 443;
    return 'https://$host:$port';
  }

  String _url(String href) => href.startsWith('http') ? href : '$_base$href';

  @override
  ProviderType get type => ProviderType.caldav;

  @override
  ProviderCapabilities get caps => ProviderCapabilities.caldav;

  @override
  Future<AuthResult> authenticate(AccountConfig cfg) async {
    try {
      await _propfind('/', 0,
          '<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>');
      return AuthResult(success: true);
    } catch (e) {
      return AuthResult(success: false, error: '$e');
    }
  }

  @override
  Future<void> refreshAuth(Account acc) async {}

  // ───────── структура ─────────

  Future<String> _calendarHome() async {
    final principal = account.config.caldavPrincipalPath ??
        '/principals/users/${Uri.encodeComponent(account.email)}/';
    final doc = await _propfind(principal, 0,
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set/></d:prop></d:propfind>');
    final href = doc
        .findAllElements('calendar-home-set',
            namespace: 'urn:ietf:params:xml:ns:caldav')
        .expand((e) => e.findElements('href', namespace: 'DAV:'))
        .map((e) => e.innerText.trim())
        .firstOrNull;
    return href ?? '/calendars/${Uri.encodeComponent(account.email)}/';
  }

  @override
  Future<List<Calendar>> listCalendars(Account acc) async {
    final home = await _calendarHome();
    final doc = await _propfind(home, 1,
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:ic="http://apple.com/ns/ical/"><d:prop><d:displayname/><d:resourcetype/><cs:getctag/><ic:calendar-color/></d:prop></d:propfind>');

    final calendars = <Calendar>[];
    for (final resp in doc.findAllElements('response', namespace: 'DAV:')) {
      final href = resp.findElements('href', namespace: 'DAV:').firstOrNull?.innerText.trim();
      if (href == null) continue;
      final isCalendar = resp
          .findAllElements('calendar', namespace: 'urn:ietf:params:xml:ns:caldav')
          .isNotEmpty;
      if (!isCalendar) continue;
      if (href.endsWith('/inbox/') || href.endsWith('/outbox/')) continue;
      if (href.contains('/todos-')) continue; // списки задач — пропускаем

      final name = resp.findAllElements('displayname', namespace: 'DAV:').firstOrNull?.innerText.trim();
      final colorHex = resp.findAllElements('calendar-color', namespace: 'http://apple.com/ns/ical/').firstOrNull?.innerText.trim();

      calendars.add(Calendar(
        id: '${acc.id}|$href',
        accountId: acc.id,
        name: (name == null || name.isEmpty) ? href : name,
        color: _parseColor(colorHex),
        // syncState НЕ ставим здесь — иначе incrementalSync решит, что менять
        // нечего, и не подтянет события на первом синке. Его выставит синк.
      ));
    }
    return calendars;
  }

  // ───────── чтение ─────────

  String _calHref(Calendar cal) => cal.id.split('|').last;

  @override
  Future<List<CalendarEvent>> fetchEvents(
      Account acc, Calendar cal, DateRange range) async {
    final body =
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '<d:prop><d:getetag/><c:calendar-data/></d:prop>'
        '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">'
        '<c:time-range start="${_z(range.startUtc)}" end="${_z(range.endUtc)}"/>'
        '</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>';

    final resp = await _dio.requestUri(
      Uri.parse(_url(_calHref(cal))),
      data: body,
      options: Options(method: 'REPORT', headers: {'Depth': '1'}),
    );
    final doc = XmlDocument.parse(resp.data.toString());
    final out = <CalendarEvent>[];
    for (final r in doc.findAllElements('response', namespace: 'DAV:')) {
      final href = r.findElements('href', namespace: 'DAV:').firstOrNull?.innerText.trim();
      final etag = r.findAllElements('getetag', namespace: 'DAV:').firstOrNull?.innerText.trim();
      final ics = r.findAllElements('calendar-data', namespace: 'urn:ietf:params:xml:ns:caldav').firstOrNull?.innerText;
      if (href == null || ics == null) continue;
      for (final v in parseIcs(ics)) {
        out.addAll(_expand(acc, cal, v, href, etag, range));
      }
    }
    return out;
  }

  @override
  Future<SyncResult> incrementalSync(
      Account acc, Calendar cal, String? syncState) async {
    // CTag: если коллекция не менялась — ничего не тянем.
    final doc = await _propfind(_calHref(cal), 0,
        '<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/"><d:prop><cs:getctag/></d:prop></d:propfind>');
    final ctag = doc.findAllElements('getctag', namespace: 'http://calendarserver.org/ns/').firstOrNull?.innerText.trim();
    if (ctag != null && ctag == syncState) {
      return SyncResult(upserts: const [], deletedIds: const [], newSyncState: ctag);
    }
    final now = DateTime.now().toUtc();
    final range = DateRange(now.subtract(const Duration(days: 90)),
        now.add(const Duration(days: 365)));
    final events = await fetchEvents(acc, cal, range);
    return SyncResult(
        upserts: events, deletedIds: const [], newSyncState: ctag, fullWindow: range);
  }

  // ───────── запись (CRUD) ─────────

  /// Путь ресурса .ics для события. providerEventId используем, только если это
  /// реальный путь/URL (а не локальный uuid); иначе строим `${calHref}${id}.ics`.
  String _resourceHref(Calendar cal, CalendarEvent e) {
    final pid = e.source.providerEventId;
    if (pid != null && (pid.startsWith('/') || pid.startsWith('http'))) {
      return pid;
    }
    return '${_calHref(cal)}${e.id}.ics';
  }

  @override
  Future<CalendarEvent> createEvent(
      Account acc, Calendar cal, CalendarEvent e) async {
    final href = _resourceHref(cal, e);
    await _dio.requestUri(
      Uri.parse(_url(href)),
      data: _toIcs(e, e.id),
      options: Options(
          method: 'PUT',
          headers: {'Content-Type': 'text/calendar; charset=utf-8'}),
    );
    // запоминаем href ресурса, чтобы update/delete били точно в него
    return e.copyWith(
        source: EventSource(
            accountId: acc.id, calendarId: cal.id, providerEventId: href));
  }

  @override
  Future<CalendarEvent> updateEvent(Account acc, CalendarEvent e) async {
    final href = _resourceHref(_calOf(e), e);
    await _dio.requestUri(
      Uri.parse(_url(href)),
      data: _toIcs(e, e.id),
      options: Options(
          method: 'PUT',
          headers: {'Content-Type': 'text/calendar; charset=utf-8'}),
    );
    return e.copyWith(
        source: EventSource(
            accountId: e.source.accountId,
            calendarId: e.calendarId,
            providerEventId: href,
            etag: e.source.etag));
  }

  @override
  Future<void> deleteEvent(
      Account acc, CalendarEvent e, RecurrenceScope scope) async {
    final url = _url(_resourceHref(_calOf(e), e));
    // Вся серия или не повтор → просто удаляем ресурс .ics.
    if (scope == RecurrenceScope.all || e.recurrenceRule == null) {
      await _dio.requestUri(Uri.parse(url), options: Options(method: 'DELETE'));
      return;
    }
    // Один экземпляр / это-и-последующие → правим мастер-VEVENT и кладём назад.
    final resp =
        await _dio.requestUri(Uri.parse(url), options: Options(method: 'GET'));
    var ics = resp.data.toString();
    final occ = e.startUtc.toUtc();
    ics = scope == RecurrenceScope.thisOnly
        ? _addExdate(ics, occ) // исключаем один экземпляр
        : _setRruleUntil(ics, occ.subtract(const Duration(seconds: 1)));
    await _dio.requestUri(Uri.parse(url),
        data: ics,
        options: Options(method: 'PUT', headers: {
          'Content-Type': 'text/calendar; charset=utf-8',
        }));
  }

  static String _icsStamp(DateTime d) {
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    final u = d.toUtc();
    return '${p(u.year, 4)}${p(u.month)}${p(u.day)}T${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
  }

  /// Добавляет EXDATE сразу после строки RRULE (внутри мастер-VEVENT).
  static String _addExdate(String ics, DateTime occ) {
    final m = RegExp(r'^RRULE:.*$', multiLine: true).firstMatch(ics);
    if (m == null) return ics;
    return '${ics.substring(0, m.end)}\r\nEXDATE:${_icsStamp(occ)}${ics.substring(m.end)}';
  }

  /// Ставит UNTIL в RRULE (убирая конфликтующие UNTIL/COUNT).
  static String _setRruleUntil(String ics, DateTime until) {
    final u = _icsStamp(until);
    return ics.replaceAllMapped(RegExp(r'^RRULE:(.*)$', multiLine: true), (m) {
      final parts = m
          .group(1)!
          .split(';')
          .where((p) =>
              p.isNotEmpty &&
              !p.toUpperCase().startsWith('UNTIL') &&
              !p.toUpperCase().startsWith('COUNT'))
          .toList()
        ..add('UNTIL=$u');
      return 'RRULE:${parts.join(';')}';
    });
  }

  @override
  Future<void> respondToInvite(
      Account acc, CalendarEvent e, ResponseStatus r) async {
    throw UnsupportedError('RSVP по CalDAV не поддержан в MVP (FR-R4)');
  }

  // ───────── helpers ─────────

  Calendar _calOf(CalendarEvent e) => Calendar(
      id: e.calendarId, accountId: e.source.accountId, name: '', color: 0);

  Future<XmlDocument> _propfind(String path, int depth, String body) async {
    final resp = await _dio.requestUri(
      Uri.parse(_url(path)),
      data: body,
      options: Options(method: 'PROPFIND', headers: {'Depth': '$depth'}),
    );
    return XmlDocument.parse(resp.data.toString());
  }

  /// Разворачивает VEVENT в экземпляры внутри [range] (повторы RRULE, FR-E6).
  List<CalendarEvent> _expand(Account acc, Calendar cal, VEvent v, String href,
      String? etag, DateRange range) {
    if (v.rrule == null || v.rrule!.isEmpty) {
      return [_build(acc, cal, v, href, etag, v.startUtc, v.endUtc, null)];
    }
    try {
      final duration = v.endUtc.difference(v.startUtc);
      final rule = RecurrenceRule.fromString('RRULE:${v.rrule}');
      final start = v.startUtc.isUtc ? v.startUtc : v.startUtc.toUtc();
      final result = <CalendarEvent>[];
      for (final occ in rule.getInstances(start: start)) {
        if (occ.isAfter(range.endUtc)) break;
        final occEnd = occ.add(duration);
        if (occEnd.isBefore(range.startUtc)) continue;
        result.add(_build(acc, cal, v, href, etag, occ, occEnd,
            occ.millisecondsSinceEpoch.toString()));
        if (result.length > 500) break;
      }
      return result.isEmpty
          ? [_build(acc, cal, v, href, etag, v.startUtc, v.endUtc, null)]
          : result;
    } catch (_) {
      return [_build(acc, cal, v, href, etag, v.startUtc, v.endUtc, null)];
    }
  }

  /// Короткий стабильный токен календаря для id события: последний непустой
  /// сегмент пути (напр. `events-10922764`). Нужен, чтобы id был УНИКАЛЕН per
  /// календарь: CalDAV-сервер (Яндекс) кладёт одно приглашение с одним UID в
  /// НЕСКОЛЬКО коллекций (основной календарь + календарь переговорки). Раньше
  /// id был `acc:UID` — одна строка на все копии, и copy из скрытого календаря
  /// перезаписывала копию из видимого → событие «пропадало» из сетки.
  /// Теперь копии сосуществуют (склейка дублей объединяет их в UI), а
  /// видимость календаря фильтрует каждую копию отдельно.
  static String _calToken(Calendar cal) {
    final segs = cal.id.split('/').where((s) => s.isNotEmpty);
    return segs.isEmpty ? cal.id : segs.last;
  }

  /// Открытая обёртка [_build] для тестов (регресс календарно-скоупных id).
  @visibleForTesting
  CalendarEvent buildEventForTest(Account acc, Calendar cal, VEvent v) =>
      _build(acc, cal, v, 'href', null, v.startUtc, v.endUtc, null);

  CalendarEvent _build(Account acc, Calendar cal, VEvent v, String href,
      String? etag, DateTime start, DateTime end, String? recurrenceId) {
    final myEmail = acc.email.toLowerCase();
    final mine =
        v.attendees.where((a) => a.email.toLowerCase() == myEmail).firstOrNull;
    final response = v.organizerEmail?.toLowerCase() == myEmail
        ? ResponseStatus.organizer
        : _partstat(mine?.partstat);
    final status = switch (v.status) {
      'CANCELLED' => EventStatus.cancelled,
      'TENTATIVE' => EventStatus.tentative,
      _ => EventStatus.confirmed,
    };
    return CalendarEvent(
      id: '${acc.id}:${_calToken(cal)}:${v.uid}'
          '${recurrenceId != null ? ':$recurrenceId' : ''}',
      calendarId: cal.id,
      title: v.summary,
      startUtc: start,
      endUtc: end,
      timeZoneId: v.timeZoneId,
      allDay: v.allDay,
      location: v.location,
      description: v.description,
      recurrenceRule: v.rrule,
      recurrenceId: recurrenceId,
      attendees: v.attendees
          .map((a) => Attendee(
                email: a.email,
                response: _partstat(a.partstat),
                isOrganizer:
                    a.email.toLowerCase() == v.organizerEmail?.toLowerCase(),
                isResource: a.cutype == 'ROOM' || a.cutype == 'RESOURCE',
              ))
          .toList(),
      myResponse: response,
      status: status,
      webUrl: v.url,
      source: EventSource(
          accountId: acc.id, calendarId: cal.id, providerEventId: href, etag: etag),
    );
  }

  static String _partstatIcs(ResponseStatus r) => switch (r) {
        ResponseStatus.accepted => 'ACCEPTED',
        ResponseStatus.declined => 'DECLINED',
        ResponseStatus.tentative => 'TENTATIVE',
        _ => 'NEEDS-ACTION',
      };

  static ResponseStatus _partstat(String? p) => switch (p) {
        'ACCEPTED' => ResponseStatus.accepted,
        'DECLINED' => ResponseStatus.declined,
        'TENTATIVE' => ResponseStatus.tentative,
        _ => ResponseStatus.needsAction,
      };

  String _toIcs(CalendarEvent e, String uid) {
    String dt(DateTime d) =>
        '${d.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';
    // SEQUENCE должен расти при каждом PUT, иначе Yandex игнорирует изменения.
    final seq = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final buf = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Calenfi//EN')
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:$uid')
      ..writeln('DTSTAMP:${dt(DateTime.now())}')
      ..writeln('SEQUENCE:$seq')
      ..writeln('DTSTART:${dt(e.startUtc)}')
      ..writeln('DTEND:${dt(e.endUtc)}')
      ..writeln('SUMMARY:${_esc(e.title)}');
    // Повторяющаяся серия (FR-E6). RRULE только у мастера, не у экземпляров.
    if (e.recurrenceRule != null && e.recurrenceId == null) {
      buf.writeln('RRULE:${e.recurrenceRule}');
    }
    if (e.location != null) buf.writeln('LOCATION:${_esc(e.location!)}');
    // Кросс-аккаунтная конференция (Teams/Meet/Zoom/Telemost) встраивается в
    // описание — CalDAV сам конференции не заводит.
    final description = descriptionWithConference(e.description, e.conference);
    if (description != null) buf.writeln('DESCRIPTION:${_esc(description)}');
    // Yandex принимает участников только с ORGANIZER и полными параметрами ATTENDEE.
    if (e.attendees.isNotEmpty) {
      buf.writeln('ORGANIZER;CN=${_esc(account.email)}:mailto:${account.email}');
      for (final a in e.attendees) {
        final cn = a.displayName != null ? ';CN=${_esc(a.displayName!)}' : '';
        if (a.isResource) {
          // Переговорка: ресурс-участник, комната сама подтверждает бронь.
          buf.writeln(
              'ATTENDEE;ROLE=NON-PARTICIPANT;CUTYPE=ROOM;PARTSTAT=${_partstatIcs(a.response)};RSVP=FALSE$cn:mailto:${a.email}');
        } else {
          buf.writeln(
              'ATTENDEE;ROLE=REQ-PARTICIPANT;CUTYPE=INDIVIDUAL;PARTSTAT=${_partstatIcs(a.response)};RSVP=TRUE$cn:mailto:${a.email}');
        }
      }
    }
    buf
      ..writeln('END:VEVENT')
      ..writeln('END:VCALENDAR');
    return buf.toString();
  }

  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');

  static String _z(DateTime d) =>
      '${d.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';

  static int _parseColor(String? hex) {
    if (hex == null || !hex.startsWith('#')) return 0xFF7E57C2;
    var h = hex.substring(1);
    if (h.length == 8) h = h.substring(6) + h.substring(0, 6); // RRGGBBAA→AARRGGBB? нет
    if (h.length >= 6) {
      final rgb = int.tryParse(h.substring(0, 6), radix: 16);
      if (rgb != null) return 0xFF000000 | rgb;
    }
    return 0xFF7E57C2;
  }
}
