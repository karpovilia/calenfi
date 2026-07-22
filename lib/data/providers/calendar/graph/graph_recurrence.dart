/// Конвертация RRULE (RFC 5545, подмножество из редактора повторов) в
/// `patternedRecurrence` Microsoft Graph — он не принимает RRULE-строку.
///
/// Поддержано: FREQ=DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, BYDAY (список дней
/// или `2TU`/`-1FR`), BYMONTHDAY, BYMONTH, BYSETPOS, COUNT, UNTIL.
/// Незнакомое правило → null (событие создаётся без повторения, RRULE не
/// теряем локально).
Map<String, dynamic>? rruleToGraphRecurrence(String rrule, DateTime startUtc) {
  final p = <String, String>{};
  for (final part in rrule.trim().split(';')) {
    final eq = part.indexOf('=');
    if (eq > 0) p[part.substring(0, eq).toUpperCase()] = part.substring(eq + 1);
  }

  const dayNames = {
    'MO': 'monday',
    'TU': 'tuesday',
    'WE': 'wednesday',
    'TH': 'thursday',
    'FR': 'friday',
    'SA': 'saturday',
    'SU': 'sunday',
  };
  const indexNames = {1: 'first', 2: 'second', 3: 'third', 4: 'fourth', -1: 'last'};

  final interval = int.tryParse(p['INTERVAL'] ?? '') ?? 1;

  // BYDAY: либо список дней (weekly), либо позиционный `2TU` (relative monthly).
  final days = <String>[];
  int? setPos;
  String? setDay;
  for (final d in (p['BYDAY'] ?? '').split(',')) {
    final m = RegExp(r'^(-?\d+)?([A-Z]{2})$').firstMatch(d.trim().toUpperCase());
    if (m == null) continue;
    final name = dayNames[m.group(2)];
    if (name == null) return null;
    final pos = m.group(1);
    if (pos != null && pos.isNotEmpty) {
      setPos = int.tryParse(pos);
      setDay = name;
    } else {
      days.add(name);
    }
  }
  final bySetPos = int.tryParse(p['BYSETPOS'] ?? '');
  if (bySetPos != null && days.length == 1) {
    setPos = bySetPos;
    setDay = days.removeAt(0);
  }
  final monthDay = int.tryParse(p['BYMONTHDAY'] ?? '');
  final month = int.tryParse(p['BYMONTH'] ?? '') ?? startUtc.month;

  Map<String, dynamic>? pattern;
  switch (p['FREQ']?.toUpperCase()) {
    case 'DAILY':
      pattern = {'type': 'daily', 'interval': interval};
    case 'WEEKLY':
      pattern = {
        'type': 'weekly',
        'interval': interval,
        'daysOfWeek':
            days.isNotEmpty ? days : [_weekdayName(startUtc.weekday)],
        'firstDayOfWeek': 'monday',
      };
    case 'MONTHLY':
      pattern = (setPos != null && setDay != null)
          ? {
              'type': 'relativeMonthly',
              'interval': interval,
              'daysOfWeek': [setDay],
              'index': indexNames[setPos] ?? 'first',
            }
          : {
              'type': 'absoluteMonthly',
              'interval': interval,
              'dayOfMonth': monthDay ?? startUtc.day,
            };
    case 'YEARLY':
      pattern = (setPos != null && setDay != null)
          ? {
              'type': 'relativeYearly',
              'interval': interval,
              'daysOfWeek': [setDay],
              'index': indexNames[setPos] ?? 'first',
              'month': month,
            }
          : {
              'type': 'absoluteYearly',
              'interval': interval,
              'dayOfMonth': monthDay ?? startUtc.day,
              'month': month,
            };
    default:
      return null;
  }

  String date(DateTime d) => d.toIso8601String().substring(0, 10);
  final count = int.tryParse(p['COUNT'] ?? '');
  final untilRaw = p['UNTIL'];
  DateTime? until;
  if (untilRaw != null) {
    until = DateTime.tryParse(untilRaw) ??
        DateTime.tryParse(untilRaw.substring(0, 8));
  }
  final range = count != null
      ? {
          'type': 'numbered',
          'startDate': date(startUtc),
          'numberOfOccurrences': count,
        }
      : until != null
          ? {'type': 'endDate', 'startDate': date(startUtc), 'endDate': date(until)}
          : {'type': 'noEnd', 'startDate': date(startUtc)};

  return {'pattern': pattern, 'range': range};
}

String _weekdayName(int weekday) => const [
      'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday',
      'sunday'
    ][weekday - 1];
