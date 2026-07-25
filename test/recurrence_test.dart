// Тесты повторяющихся встреч (FR-E6): человекочитаемое описание RRULE в
// редакторе и конвертация RRULE → patternedRecurrence Microsoft Graph
// (Graph не принимает RRULE-строку).

import 'package:calenfi/data/providers/calendar/graph/graph_recurrence.dart';
import 'package:calenfi/features/event_editor/recurrence_editor.dart';
import 'package:calenfi/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // describeRecurrence теперь ЛОКАЛИЗОВАН (нужен BuildContext + L10n) — проверяем
  // через widget: не падает, не пусто, и незнакомое правило отдаёт как есть.
  group('describeRecurrence (localized)', () {
    Future<String> describe(WidgetTester tester, String? rule) async {
      late String result;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(builder: (context) {
          result = describeRecurrence(context, rule);
          return const SizedBox();
        }),
      ));
      return result;
    }

    testWidgets('null/пусто → непустая подпись «не повторять»', (t) async {
      expect(await describe(t, null), isNotEmpty);
      expect(await describe(t, ''), isNotEmpty);
    });

    testWidgets('известные правила отдают непустой текст без падения', (t) async {
      for (final r in [
        'FREQ=WEEKLY;BYDAY=MO,WE',
        'FREQ=WEEKLY;INTERVAL=2;BYDAY=SU;UNTIL=20270731T235959Z',
        'FREQ=MONTHLY;BYDAY=2TU;COUNT=10',
        'FREQ=MONTHLY;BYMONTHDAY=15',
      ]) {
        expect(await describe(t, r), isNotEmpty, reason: r);
      }
    });

    testWidgets('незнакомое правило показываем как есть', (t) async {
      expect(await describe(t, 'FREQ=SECONDLY'), 'FREQ=SECONDLY');
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
