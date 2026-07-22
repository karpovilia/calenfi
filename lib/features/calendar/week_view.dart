import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/merged_event.dart';
import 'calendar_state.dart';
import 'time_grid.dart';

/// Недельный вид (FR-V1).
class WeekView extends ConsumerWidget {
  const WeekView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focused = ref.watch(focusedDateProvider);
    final start = weekStart(focused);
    final days = List.generate(7, (i) => start.add(Duration(days: i)));
    final eventsAsync = ref.watch(mergedEventsProvider);
    final colorsAsync = ref.watch(calendarColorsProvider);

    return Column(
      children: [
        _WeekHeader(days: days),
        const Divider(height: 1),
        Expanded(
          child: eventsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Ошибка: $e')),
            data: (events) => TimeGrid(
              days: days,
              events: events,
              colors: colorsAsync.value ?? const {},
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.days});
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    const ru = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: kGutterWidth),
          for (final d in days)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(ru[d.weekday - 1],
                      style: TextStyle(
                          fontSize: 11,
                          color: isToday(d)
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey)),
                  const SizedBox(height: 2),
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: isToday(d)
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    child: Text('${d.day}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isToday(d) ? Colors.white : null)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Утилита: события, начинающиеся в указанный день (по локальному времени).
List<MergedEvent> eventsForDay(List<MergedEvent> all, DateTime day) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  return all.where((e) {
    final s = e.primary.startUtc.toLocal();
    return !s.isBefore(dayStart) && s.isBefore(dayEnd);
  }).toList()
    ..sort((a, b) => a.primary.startUtc.compareTo(b.primary.startUtc));
}
