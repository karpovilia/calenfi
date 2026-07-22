import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/account_repository.dart';
import '../../domain/models/account.dart';
import '../../domain/models/calendar.dart';
import '../../domain/models/enums.dart';
import '../../services/maps_service.dart';
import '../accounts/accounts_screen.dart';
import '../calendar/calendar_state.dart';

/// Экран всех настроек (FR-C). Подмножество настроек Fantastical
/// (см. docs/fantastical-settings-reference.md), включая выбор активных
/// календарей («Calendars & Lists»).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: const SettingsPanel(),
      );
}

/// Тело настроек без Scaffold — переиспользуется как полный экран и как боковая
/// панель (endDrawer) на десктопе, чтобы не закрывать календарь целиком.
class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final combine = ref.watch(combineProvider);
    final showCancelled = ref.watch(showCancelledProvider);
    final showMonth = ref.watch(showMonthViewProvider);
    final accounts = ref.watch(accountsStreamProvider).value ?? const <Account>[];
    final calendars =
        ref.watch(calendarsStreamProvider).value ?? const <Calendar>[];

    return ListView(
        children: [
          // ───────── Активные календари (Fantastical «Calendars & Lists») ──────
          const _SectionHeader('Календари'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Какие календари показывать в сетке',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          for (final acc in accounts)
            _AccountCalendars(
              account: acc,
              calendars: calendars.where((c) => c.accountId == acc.id).toList(),
            ),
          if (accounts.isEmpty)
            const ListTile(dense: true, title: Text('Нет аккаунтов')),

          const Divider(),
          const _SectionHeader('Вид'),
          SwitchListTile(
            title: const Text('Показывать месячный вид'),
            subtitle: const Text('На телефоне месяц тесный — можно убрать'),
            value: showMonth,
            onChanged: (v) =>
                ref.read(showMonthViewProvider.notifier).state = v,
          ),
          const Divider(),
          const _SectionHeader('События'),
          SwitchListTile(
            secondary:
                Icon(combine ? Icons.layers : Icons.layers_clear_outlined),
            title: const Text('Объединять встречи'),
            subtitle: const Text(
                'Склеивать одинаковые события из разных календарей. Отжать — '
                'каждая встреча отдельно, можно работать с каждой копией (FR-D)'),
            value: combine,
            onChanged: (v) => ref.read(combineProvider.notifier).state = v,
          ),
          SwitchListTile(
            secondary: Icon(showCancelled
                ? Icons.event_busy
                : Icons.event_busy_outlined),
            title: const Text('Показывать удалённые/отменённые'),
            subtitle: const Text('Зачёркнутым стилем (FR-V12)'),
            value: showCancelled,
            onChanged: (v) =>
                ref.read(showCancelledProvider.notifier).state = v,
          ),
          ListTile(
            title: const Text('Задержка перед отправкой изменений'),
            subtitle: const Text(
                'Перенос/ресайз ждут перед уходом в облако: пунктир + отсчёт + '
                '«применить сейчас». 0 — сразу.'),
            trailing: DropdownButton<int>(
              value: ref.watch(commitDelayProvider).inMinutes,
              onChanged: (m) => ref.read(commitDelayProvider.notifier).state =
                  Duration(minutes: m ?? 0),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Сразу')),
                DropdownMenuItem(value: 1, child: Text('1 мин')),
                DropdownMenuItem(value: 2, child: Text('2 мин')),
                DropdownMenuItem(value: 5, child: Text('5 мин')),
              ],
            ),
          ),

          const Divider(),
          const _SectionHeader('Карты'),
          const ListTile(
            title: Text('Открывать места в'),
            subtitle: Text('По умолчанию — Yandex Maps (FR-L2)'),
            trailing: _MapsDropdown(),
          ),

          const Divider(),
          const _SectionHeader('Учётные записи'),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Учётные записи и подключения'),
            subtitle: Text('${accounts.length} подключено'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountsScreen())),
          ),

          const Divider(),
          const _SectionHeader('О приложении'),
          const ListTile(
            title: Text('Calenfi'),
            subtitle: Text('Local-first агрегатор календарей · MVP'),
          ),
        ],
      );
  }
}

/// Группа «аккаунт + его календари» с чекбоксами видимости и «выбрать все».
class _AccountCalendars extends ConsumerWidget {
  const _AccountCalendars({required this.account, required this.calendars});
  final Account account;
  final List<Calendar> calendars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(accountRepositoryProvider);
    final visibleCount = calendars.where((c) => c.visible).length;
    final bool? groupValue = calendars.isEmpty
        ? false
        : visibleCount == calendars.length
            ? true
            : visibleCount == 0
                ? false
                : null;

    Future<void> setAll(bool v) async {
      for (final c in calendars) {
        await repo.setCalendarVisible(c.id, v);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // заголовок аккаунта + tristate «выбрать все»
        InkWell(
          onTap: calendars.isEmpty ? null : () => setAll(!(groupValue ?? false)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  value: groupValue,
                  onChanged: calendars.isEmpty
                      ? null
                      : (_) => setAll(!(groupValue ?? false)),
                ),
                Icon(_providerIcon(account.provider),
                    size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(account.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
              ],
            ),
          ),
        ),
        for (final c in calendars)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.only(left: 24, right: 8),
            value: c.visible,
            onChanged: (v) => repo.setCalendarVisible(c.id, v ?? false),
            secondary: TextButton.icon(
              onPressed: () => _pickReminder(context, repo, c),
              icon: Icon(
                  c.defaultReminderMinutes == null
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                  size: 16),
              label: Text(_reminderLabel(c.defaultReminderMinutes),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6)),
            ),
            title: Row(
              children: [
                _ColorSwatch(
                  color: Color(c.effectiveColor),
                  custom: c.colorOverride != null,
                  onTap: () => _pickColor(context, repo, c),
                ),
                const SizedBox(width: 10),
                // тап по имени → переименовать
                Flexible(
                  child: InkWell(
                    onTap: () => _pickName(context, repo, c),
                    child: Text(c.effectiveName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontStyle: c.nameOverride != null
                                ? FontStyle.italic
                                : null)),
                  ),
                ),
                if (c.nameOverride != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.edit, size: 11, color: Colors.grey),
                  ),
                if (c.readOnly)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child:
                        Icon(Icons.lock_outline, size: 13, color: Colors.grey),
                  ),
              ],
            ),
          ),
        if (calendars.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(40, 0, 16, 8),
            child:
                Text('нет календарей', style: TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }
}

class _MapsDropdown extends StatefulWidget {
  const _MapsDropdown();
  @override
  State<_MapsDropdown> createState() => _MapsDropdownState();
}

class _MapsDropdownState extends State<_MapsDropdown> {
  @override
  Widget build(BuildContext context) => DropdownButton<MapProvider>(
        value: MapsService.provider,
        onChanged: (v) => setState(() => MapsService.provider = v!),
        items: const [
          DropdownMenuItem(value: MapProvider.yandex, child: Text('Yandex Maps')),
          DropdownMenuItem(value: MapProvider.google, child: Text('Google Maps')),
          DropdownMenuItem(value: MapProvider.apple, child: Text('Apple Maps')),
        ],
      );
}

/// Кружок-цвет календаря; обводка, если цвет переопределён пользователем.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch(
      {required this.color, required this.custom, required this.onTap});
  final Color color;
  final bool custom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: custom
                ? Border.all(color: Colors.white70, width: 2)
                : Border.all(color: Colors.white24, width: 1),
          ),
        ),
      );
}

/// Палитра выбора цвета календаря (FR-A9) + сброс к цвету источника.
const _palette = <int>[
  0xFFE53935, 0xFFD81B60, 0xFF8E24AA, 0xFF5E35B1, 0xFF3949AB,
  0xFF1E88E5, 0xFF039BE5, 0xFF00ACC1, 0xFF00897B, 0xFF43A047,
  0xFF7CB342, 0xFFC0CA33, 0xFFFDD835, 0xFFFFB300, 0xFFFB8C00,
  0xFFF4511E, 0xFF6D4C41, 0xFF757575, 0xFF546E7A, 0xFF7719AA,
];

Future<void> _pickName(
    BuildContext context, AccountRepository repo, Calendar c) async {
  final ctrl = TextEditingController(text: c.effectiveName);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Переименовать календарь'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Имя календаря'),
            onSubmitted: (v) {
              repo.setCalendarName(c.id, v);
              Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 6),
          Text('Из источника: ${c.name}',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
      actions: [
        if (c.nameOverride != null)
          TextButton(
            onPressed: () {
              repo.setCalendarName(c.id, null); // сброс к имени источника
              Navigator.pop(ctx);
            },
            child: const Text('Сбросить'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            repo.setCalendarName(c.id, ctrl.text);
            Navigator.pop(ctx);
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

Future<void> _pickColor(
    BuildContext context, AccountRepository repo, Calendar c) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Цвет: ${c.effectiveName}'),
      content: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final argb in _palette)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  repo.setCalendarColor(c.id, argb);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(argb),
                    shape: BoxShape.circle,
                    border: c.effectiveColor == argb
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (c.colorOverride != null)
          TextButton(
            onPressed: () {
              repo.setCalendarColor(c.id, null);
              Navigator.pop(ctx);
            },
            child: const Text('Сбросить к цвету источника'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
      ],
    ),
  );
}

// ───────── напоминания по умолчанию (FR-N) ─────────

/// Варианты дефолтного напоминания календаря: null = нет, 0 = в момент начала.
const _reminderOptions = <int?>[null, 0, 5, 10, 15, 30, 60];

String _reminderLabel(int? minutes) {
  if (minutes == null) return 'без';
  if (minutes == 0) return 'в начале';
  if (minutes % 60 == 0) return 'за ${minutes ~/ 60} ч';
  return 'за $minutes мин';
}

Future<void> _pickReminder(
    BuildContext context, AccountRepository repo, Calendar c) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Напоминание: ${c.effectiveName}'),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('По умолчанию для событий этого календаря',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        RadioGroup<int?>(
          groupValue: c.defaultReminderMinutes,
          onChanged: (v) {
            repo.setCalendarDefaultReminder(c.id, v);
            Navigator.pop(ctx);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final opt in _reminderOptions)
                RadioListTile<int?>(
                  dense: true,
                  value: opt,
                  title: Text(opt == null
                      ? 'Без напоминания'
                      : opt == 0
                          ? 'В момент начала'
                          : _reminderLabel(opt)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

IconData _providerIcon(ProviderType p) => switch (p) {
      ProviderType.google => Icons.event,
      ProviderType.graph => Icons.business,
      ProviderType.caldav => Icons.cloud_outlined,
      ProviderType.ews => Icons.dns_outlined,
    };

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
      );
}
