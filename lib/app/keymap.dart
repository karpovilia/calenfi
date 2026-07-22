import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/calendar/calendar_state.dart';
import '../features/event_editor/event_editor_screen.dart';
import 'providers.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Клавиатурные привязки Calenfi — единый файл (по аналогии с keymap в mc).
/// Чтобы перепривязать клавишу — правьте только карту [kCalenfiKeymap] ниже.
/// ─────────────────────────────────────────────────────────────────────────

// --- Намерения (intents) ---
class NewEventIntent extends Intent {
  const NewEventIntent();
}

class TodayIntent extends Intent {
  const TodayIntent();
}

class PrevPeriodIntent extends Intent {
  const PrevPeriodIntent();
}

class NextPeriodIntent extends Intent {
  const NextPeriodIntent();
}

class SetViewIntent extends Intent {
  const SetViewIntent(this.mode);
  final CalendarViewMode mode;
}

class SyncIntent extends Intent {
  const SyncIntent();
}

class ToggleCancelledIntent extends Intent {
  const ToggleCancelledIntent();
}

/// Единая карта привязок. Здесь и только здесь меняются горячие клавиши.
const Map<ShortcutActivator, Intent> kCalenfiKeymap = {
  SingleActivator(LogicalKeyboardKey.keyN): NewEventIntent(),
  SingleActivator(LogicalKeyboardKey.keyT): TodayIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft): PrevPeriodIntent(),
  SingleActivator(LogicalKeyboardKey.arrowRight): NextPeriodIntent(),
  SingleActivator(LogicalKeyboardKey.digit1): SetViewIntent(CalendarViewMode.day),
  SingleActivator(LogicalKeyboardKey.digit2): SetViewIntent(CalendarViewMode.week),
  SingleActivator(LogicalKeyboardKey.digit3): SetViewIntent(CalendarViewMode.month),
  SingleActivator(LogicalKeyboardKey.keyR): SyncIntent(),
  SingleActivator(LogicalKeyboardKey.keyR, control: true): SyncIntent(),
  SingleActivator(LogicalKeyboardKey.keyH): ToggleCancelledIntent(),
};

/// Подсказки для UI (например, тултипы) — описание привязок одним местом.
const Map<String, String> kKeymapHints = {
  'N': 'Новое событие',
  'T': 'Сегодня',
  '← / →': 'Предыдущий / следующий период',
  '1 / 2 / 3': 'День / Неделя / Месяц',
  'R': 'Синхронизировать',
  'H': 'Показать удалённые',
  'Esc': 'Закрыть модалку',
};

/// Оборачивает дерево виджетов глобальными привязками + действиями.
class CalenfiKeymap extends ConsumerWidget {
  const CalenfiKeymap({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: kCalenfiKeymap,
      child: Actions(
        actions: <Type, Action<Intent>>{
          NewEventIntent: CallbackAction<NewEventIntent>(onInvoke: (_) {
            EventEditor.open(context,
                initialDay: ref.read(focusedDateProvider));
            return null;
          }),
          TodayIntent: CallbackAction<TodayIntent>(onInvoke: (_) {
            goToday(ref);
            return null;
          }),
          PrevPeriodIntent: CallbackAction<PrevPeriodIntent>(onInvoke: (_) {
            shiftFocused(ref, -1);
            return null;
          }),
          NextPeriodIntent: CallbackAction<NextPeriodIntent>(onInvoke: (_) {
            shiftFocused(ref, 1);
            return null;
          }),
          SetViewIntent: CallbackAction<SetViewIntent>(onInvoke: (i) {
            ref.read(viewModeProvider.notifier).state = i.mode;
            return null;
          }),
          SyncIntent: CallbackAction<SyncIntent>(onInvoke: (_) {
            ref.read(syncTriggerProvider)();
            return null;
          }),
          ToggleCancelledIntent:
              CallbackAction<ToggleCancelledIntent>(onInvoke: (_) {
            final cur = ref.read(showCancelledProvider);
            ref.read(showCancelledProvider.notifier).state = !cur;
            return null;
          }),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
