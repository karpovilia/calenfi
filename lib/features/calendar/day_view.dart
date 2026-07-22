import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_state.dart';
import 'time_grid.dart';

/// Дневной вид (FR-V1) с плавным листанием свайпом: каждый день — отдельная
/// страница [PageView], сдвигается анимированно, не рывком.
class DayView extends ConsumerStatefulWidget {
  const DayView({super.key});

  @override
  ConsumerState<DayView> createState() => _DayViewState();
}

class _DayViewState extends ConsumerState<DayView> {
  static const _center = 100000;
  late final DateTime _anchor;
  late final PageController _controller;
  bool _suppress = false;

  @override
  void initState() {
    super.initState();
    final f = ref.read(focusedDateProvider);
    _anchor = DateTime(f.year, f.month, f.day);
    _controller = PageController(initialPage: _center);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime _dateForPage(int page) => _anchor.add(Duration(days: page - _center));
  int _pageForDate(DateTime d) =>
      _center + DateTime(d.year, d.month, d.day).difference(_anchor).inDays;

  @override
  Widget build(BuildContext context) {
    // Внешние смены даты (кнопка «Сегодня») — листаем контроллер к нужной странице.
    ref.listen(focusedDateProvider, (_, next) {
      if (_suppress || !_controller.hasClients) return;
      final target = _pageForDate(next);
      if ((_controller.page?.round() ?? _center) != target) {
        _controller.jumpToPage(target);
      }
    });

    return PageView.builder(
      controller: _controller,
      onPageChanged: (page) {
        _suppress = true;
        ref.read(focusedDateProvider.notifier).state = _dateForPage(page);
        _suppress = false;
      },
      itemBuilder: (_, page) => _DayPage(day: _dateForPage(page)),
    );
  }
}

/// Одна страница дневного вида: компактная шапка + сетка событий этого дня.
class _DayPage extends ConsumerWidget {
  const _DayPage({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Дату показывает верхняя панель (тап = «Сегодня»), поэтому здесь без шапки.
    final eventsAsync = ref.watch(dayEventsProvider(day));
    final colorsAsync = ref.watch(calendarColorsProvider);

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Ошибка: $e')),
      data: (events) => TimeGrid(
        days: [day],
        events: events,
        colors: colorsAsync.value ?? const {},
      ),
    );
  }
}
