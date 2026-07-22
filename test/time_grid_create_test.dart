import 'package:calenfi/domain/models/calendar_event.dart';
import 'package:calenfi/domain/models/merged_event.dart';
import 'package:calenfi/features/calendar/calendar_state.dart';
import 'package:calenfi/features/calendar/time_grid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rec extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

bool _hasDialog(_Rec o) =>
    o.pushed.any((r) => r.runtimeType.toString().contains('Dialog'));
bool _hasSheet(_Rec o) =>
    o.pushed.any((r) => r.runtimeType.toString().contains('ModalBottomSheet'));

void main() {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  final start = DateTime(today.year, today.month, today.day, 10); // 10:00 local
  final ev = CalendarEvent(
    id: 'e1',
    calendarId: 'c1',
    title: 'Существующая',
    startUtc: start.toUtc(),
    endUtc: start.add(const Duration(hours: 1)).toUtc(),
    source: const EventSource(accountId: 'a1', calendarId: 'c1'),
  );
  final me = MergedEvent(groupId: 'g1', primary: ev, sources: [ev]);

  Widget harness(_Rec obs, {bool moveMode = false}) => ProviderScope(
        overrides: [
          if (moveMode) moveModeProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          navigatorObservers: [obs],
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: TimeGrid(days: [day], events: [me], colors: const {}),
            ),
          ),
        ),
      );

  Future<void> dragMouse(WidgetTester tester, Offset from) async {
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(0, 14));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
  }

  testWidgets('drag over EMPTY space creates (control)', (tester) async {
    final obs = _Rec();
    await tester.pumpWidget(harness(obs));
    await tester.pump();
    // ~15:00 — ниже события, пустое место в видимой области.
    await dragMouse(tester, const Offset(400, 360));
    tester.takeException();
    expect(_hasDialog(obs), isTrue, reason: 'редактор создания должен открыться');
    expect(_hasSheet(obs), isFalse);
  });

  testWidgets('drag over EXISTING event creates (pinned)', (tester) async {
    final obs = _Rec();
    await tester.pumpWidget(harness(obs));
    await tester.pump();
    final onEvent = tester.getCenter(find.text('Существующая'));
    await dragMouse(tester, onEvent);
    tester.takeException();
    expect(_hasDialog(obs), isTrue, reason: 'создание поверх события');
    expect(_hasSheet(obs), isFalse, reason: 'не должны открыться детали');
  });

  testWidgets('tap on event opens details (pinned)', (tester) async {
    final obs = _Rec();
    await tester.pumpWidget(harness(obs));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.text('Существующая')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    tester.takeException();
    expect(_hasSheet(obs), isTrue, reason: 'тап → детали (bottom sheet)');
  });
}
