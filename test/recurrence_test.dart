// Тесты повторяющихся встреч (FR-E6): человекочитаемое описание RRULE в
// редакторе и конвертация RRULE → patternedRecurrence Microsoft Graph
// (Graph не принимает RRULE-строку).

import 'package:calenfi/data/providers/calendar/graph/graph_recurrence.dart';
import 'package:calenfi/features/event_editor/recurrence_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('describeRecurrence', () {
    test('null/пусто → «Не повторять»', () {
      expect(describeRecurrence(null), 'Не повторять');
      expect(describeRecurrence(''), 'Не повторять');
    });

    test('еженедельно с днями', () {
      expect(describeRecurrence('FREQ=WEEKLY;BYDAY=MO,WE'),
          'Еженедельно: Пн, Ср');
    });

    test('каждые 2 недели с UNTIL', () {
      final s = describeRecurrence(
          'FREQ=WEEKLY;INTERVAL=2;BYDAY=SU;UNTIL=20270731T235959Z');
      expect(s, contains('Каждые 2 нед.'));
      expect(s, contains('Вс'));
      expect(s, contains('до 31.07.2027'));
    });

    test('ежемесячно во 2-й вторник, 10 повторений', () {
      final s = describeRecurrence('FREQ=MONTHLY;BYDAY=2TU;COUNT=10');
      expect(s, contains('Ежемесячно'));
      expect(s, contains('во 2-й вторник'));
      expect(s, contains('10 повторений'));
    });

    test('ежемесячно N-го числа', () {
      expect(describeRecurrence('FREQ=MONTHLY;BYMONTHDAY=15'),
          contains('15-го числа'));
    });

    test('незнакомое правило показываем как есть, не падаем', () {
      expect(describeRecurrence('FREQ=SECONDLY'), 'FREQ=SECONDLY');
    });
  });

  group('rruleToGraphRecurrence', () {
    final start = DateTime.utc(2026, 7, 29, 19); // среда

    test('еженедельно по средам до даты', () {
      final g = rruleToGraphRecurrence(
          'FREQ=WEEKLY;BYDAY=WE;UNTIL=20270731T235959Z', start)!;
      expect(g['pattern'], {
        'type': 'weekly',
        'interval': 1,
        'daysOfWeek': ['wednesday'],
        'firstDayOfWeek': 'monday',
      });
      expect(g['range'], {
        'type': 'endDate',
        'startDate': '2026-07-29',
        'endDate': '2027-07-31',
      });
    });

    test('WEEKLY без BYDAY берёт день недели из старта', () {
      final g = rruleToGraphRecurrence('FREQ=WEEKLY', start)!;
      expect((g['pattern'] as Map)['daysOfWeek'], ['wednesday']);
      expect((g['range'] as Map)['type'], 'noEnd');
    });

    test('каждые 3 дня, 5 повторений', () {
      final g = rruleToGraphRecurrence('FREQ=DAILY;INTERVAL=3;COUNT=5', start)!;
      expect(g['pattern'], {'type': 'daily', 'interval': 3});
      expect((g['range'] as Map)['numberOfOccurrences'], 5);
      expect((g['range'] as Map)['type'], 'numbered');
    });

    test('ежемесячно в последнюю пятницу', () {
      final g = rruleToGraphRecurrence('FREQ=MONTHLY;BYDAY=-1FR', start)!;
      expect(g['pattern'], {
        'type': 'relativeMonthly',
        'interval': 1,
        'daysOfWeek': ['friday'],
        'index': 'last',
      });
    });

    test('ежегодно 29 июля', () {
      final g = rruleToGraphRecurrence(
          'FREQ=YEARLY;BYMONTH=7;BYMONTHDAY=29', start)!;
      expect(g['pattern'], {
        'type': 'absoluteYearly',
        'interval': 1,
        'dayOfMonth': 29,
        'month': 7,
      });
    });

    test('BYSETPOS-вариант эквивалентен позиционному BYDAY', () {
      final a = rruleToGraphRecurrence('FREQ=MONTHLY;BYDAY=TU;BYSETPOS=2', start);
      final b = rruleToGraphRecurrence('FREQ=MONTHLY;BYDAY=2TU', start);
      expect(a, b);
    });

    test('незнакомый FREQ → null (событие создаётся без повторения)', () {
      expect(rruleToGraphRecurrence('FREQ=HOURLY', start), isNull);
    });
  });
}
