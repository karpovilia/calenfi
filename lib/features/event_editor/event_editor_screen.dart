import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../data/local/db/database.dart' show ContactRow;
import '../../domain/models/attendee.dart';
import '../../domain/models/calendar.dart';
import '../../domain/models/calendar_event.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../calendar/calendar_state.dart';
import '../calendar/pending_edits.dart';
import 'recurrence_editor.dart';

/// Открытие редактора события как **диалога** (не на весь экран).
class EventEditor {
  static Future<void> open(
    BuildContext context, {
    CalendarEvent? existing,
    DateTime? initialDay,
    DateTime? initialStart,
    DateTime? initialEnd,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final narrow = MediaQuery.of(ctx).size.width < 520;
        final content = EventEditorScreen(
          existing: existing,
          initialDay: initialDay,
          initialStart: initialStart,
          initialEnd: initialEnd,
        );
        final body = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(ctx).pop(),
          },
          child: Focus(autofocus: true, child: content),
        );
        // На телефоне — полноэкранный диалог (надёжный layout); на десктопе —
        // компактное окно фиксированного размера.
        if (narrow) return Dialog.fullscreen(child: body);
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: 480, height: 660, child: body),
        );
      },
    );
  }
}

/// Содержимое редактора создания/редактирования события (FR-E1–E4, FR-E9),
/// поля по `docs/images/image.png`.
class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({
    super.key,
    this.existing,
    this.initialDay,
    this.initialStart,
    this.initialEnd,
  });

  final CalendarEvent? existing;
  final DateTime? initialDay;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _notes;
  late final TextEditingController _room;

  late bool _allDay;
  late DateTime _start;
  late DateTime _end;
  String? _calendarId;
  late ShowAs _showAs;
  late EventVisibility _visibility;
  ConferenceType? _conference;
  late List<Attendee> _attendees;

  /// Правило повторения (RRULE без префикса, FR-E6). null — не повторять.
  String? _recurrenceRule;

  /// Контроллер поля ввода участника (из Autocomplete.fieldViewBuilder) —
  /// нужен, чтобы очистить строку после выбора из выпадающего списка.
  TextEditingController? _inviteeCtl;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _notes = TextEditingController(text: e?.description ?? '');
    _allDay = e?.allDay ?? false;
    final base = widget.initialDay ?? DateTime.now();
    _start = e?.startUtc.toLocal() ??
        widget.initialStart ??
        DateTime(base.year, base.month, base.day, 12, 0);
    _end = e?.endUtc.toLocal() ??
        widget.initialEnd ??
        _start.add(const Duration(hours: 1));
    _calendarId = e?.calendarId;
    _showAs = e?.showAs ?? ShowAs.busy;
    _visibility = e?.visibility ?? EventVisibility.defaultVis;
    _conference = e?.conference?.type;
    _recurrenceRule = e?.recurrenceRule;
    // Переговорка (ресурс) — отдельная категория; из общего списка исключаем.
    _room = TextEditingController(text: e?.room?.email ?? '');
    _attendees = List.of(e?.people ?? const []);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(calendarsListProvider).value ?? const <Calendar>[];
    // Только видимые и доступные для записи календари: в скрытый или read-only
    // календарь событие создать нельзя (FR-A8).
    var cals = all.where((c) => c.visible && !c.readOnly).toList();
    if (cals.isEmpty) cals = all.where((c) => c.visible).toList();
    if (cals.isEmpty) cals = all;
    if (_calendarId == null || cals.every((c) => c.id != _calendarId)) {
      _calendarId = cals.isNotEmpty ? cals.first.id : null;
    }

    return Column(
      children: [
        // шапка диалога
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Text(_isNew ? 'Новое событие' : 'Изменить событие',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
              FilledButton(
                onPressed: cals.isEmpty ? null : () => _save(cals),
                child: const Text('Готово'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              TextField(
                controller: _title,
                autofocus: _isNew,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitByEnter(cals),
                decoration: const InputDecoration(hintText: 'Название'),
                style: const TextStyle(fontSize: 18),
              ),
              TextField(
                controller: _location,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitByEnter(cals),
                decoration: const InputDecoration(
                    hintText: 'Место', icon: Icon(Icons.place_outlined)),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Весь день'),
                value: _allDay,
                onChanged: (v) => setState(() => _allDay = v),
              ),
              _dateTimeRow('Начало', _start, (d) => setState(() {
                    _start = d;
                    if (_end.isBefore(_start)) {
                      _end = _start.add(const Duration(hours: 1));
                    }
                  })),
              _dateTimeRow('Конец', _end, (d) => setState(() => _end = d)),
              _recurrenceRow(),
              const Divider(height: 24),
              _calendarPicker(cals),
              _showAsRow(),
              _visibilityRow(),
              _conferenceRow(),
              _roomRow(),
              const Divider(height: 24),
              _inviteesSection(),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText: 'Заметки', icon: Icon(Icons.notes_outlined)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- invitees (FR-E9, FR-K3) ---
  Widget _inviteesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: const [
          Icon(Icons.people_outline, size: 18, color: Colors.grey),
          SizedBox(width: 8),
          Text('Участники'),
        ]),
        const SizedBox(height: 6),
        if (_attendees.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final a in _attendees)
                InputChip(
                  label: Text(a.displayName ?? a.email,
                      style: const TextStyle(fontSize: 12)),
                  avatar: _responseAvatar(a.response),
                  onDeleted: () => setState(() => _attendees.remove(a)),
                ),
            ],
          ),
        // автодополнение из справочника (FR-K3) + ручной ввод email
        Autocomplete<ContactRow>(
          optionsBuilder: (value) => _matchingContacts(value.text),
          displayStringForOption: (c) => '${c.displayName} <${c.email}>',
          onSelected: (c) {
            _addInviteeEmail(c.email, c.displayName);
            // Autocomplete проставляет в поле displayString ПОСЛЕ onSelected —
            // поэтому чистим на следующем кадре, иначе строка не очищается.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _inviteeCtl?.clear();
            });
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            _inviteeCtl = controller;
            return Row(children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                      hintText: 'Имя из справочника или email',
                      isDense: true),
                  onSubmitted: (v) {
                    // Есть подсказки → Enter выбирает выделенную (onSubmit →
                    // onSelected добавит участника), затем чистим поле. Иначе,
                    // если введён «сырой» email — добавляем его вручную.
                    if (_matchingContacts(v).isNotEmpty) {
                      onSubmit();
                      controller.clear();
                    } else if (v.trim().contains('@')) {
                      _addInviteeEmail(v.trim(), null);
                      controller.clear();
                    }
                  },
                ),
              ),
              IconButton(
                onPressed: () {
                  if (controller.text.trim().contains('@')) {
                    _addInviteeEmail(controller.text.trim(), null);
                    controller.clear();
                  }
                },
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]);
          },
        ),
      ],
    );
  }

  /// Контакты справочника, подходящие под запрос (по имени или почте).
  /// Общий источник для подсказок Autocomplete и для выбора по Enter.
  Iterable<ContactRow> _matchingContacts(String value) {
    final q = value.trim().toLowerCase();
    if (q.isEmpty) return const <ContactRow>[];
    final contacts = ref.read(contactsStreamProvider).value ?? const [];
    return contacts.where((c) =>
        c.displayName.toLowerCase().contains(q) ||
        c.email.toLowerCase().contains(q));
  }

  void _addInviteeEmail(String email, String? name) {
    if (email.isEmpty || !email.contains('@')) return;
    if (_attendees.any((a) => a.email == email)) return;
    setState(() => _attendees.add(Attendee(email: email, displayName: name)));
  }

  Widget? _responseAvatar(ResponseStatus r) {
    final (icon, color) = switch (r) {
      ResponseStatus.accepted => (Icons.check, Colors.green),
      ResponseStatus.declined => (Icons.close, Colors.red),
      ResponseStatus.tentative => (Icons.help_outline, Colors.orange),
      _ => (Icons.schedule, Colors.grey),
    };
    return CircleAvatar(
        backgroundColor: Colors.transparent,
        child: Icon(icon, size: 14, color: color));
  }

  /// Повторение (FR-E6): диалог в стиле Outlook (см. recurrence_editor.dart).
  /// У экземпляра серии правило меняется только у мастера — строка заблокирована.
  Widget _recurrenceRow() {
    final isInstance = widget.existing?.recurrenceId != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.repeat),
      title: const Text('Повторять'),
      subtitle: Text(isInstance
          ? 'Экземпляр серии — правило у всей серии'
          : describeRecurrence(_recurrenceRule)),
      enabled: !isInstance,
      onTap: isInstance
          ? null
          : () async {
              final r = await showRecurrenceDialog(context,
                  initial: _recurrenceRule, start: _start);
              if (r == null) return; // отмена
              setState(() => _recurrenceRule = r.isEmpty ? null : r);
            },
    );
  }

  Widget _showAsRow() => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.work_outline),
        title: const Text('Показывать как'),
        trailing: SegmentedButton<ShowAs>(
          segments: const [
            ButtonSegment(value: ShowAs.busy, label: Text('Занят')),
            ButtonSegment(value: ShowAs.free, label: Text('Свободен')),
          ],
          selected: {_showAs},
          onSelectionChanged: (s) => setState(() => _showAs = s.first),
        ),
      );

  Widget _visibilityRow() => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.visibility_outlined),
        title: const Text('Видимость'),
        trailing: DropdownButton<EventVisibility>(
          value: _visibility,
          onChanged: (v) => setState(() => _visibility = v!),
          items: const [
            DropdownMenuItem(value: EventVisibility.defaultVis, child: Text('По умолчанию')),
            DropdownMenuItem(value: EventVisibility.private, child: Text('Приватно')),
            DropdownMenuItem(value: EventVisibility.public, child: Text('Публично')),
          ],
        ),
      );

  Widget _conferenceRow() => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.videocam_outlined),
        title: const Text('Видеовстреча'),
        trailing: DropdownButton<ConferenceType?>(
          value: _conference,
          hint: const Text('Нет'),
          onChanged: (v) => setState(() => _conference = v),
          items: const [
            DropdownMenuItem(value: null, child: Text('Нет')),
            DropdownMenuItem(value: ConferenceType.meet, child: Text('Google Meet')),
            DropdownMenuItem(value: ConferenceType.teams, child: Text('Teams')),
            DropdownMenuItem(value: ConferenceType.zoom, child: Text('Zoom')),
            DropdownMenuItem(value: ConferenceType.telemost, child: Text('Telemost')),
          ],
        ),
      );

  /// Переговорка — отдельная категория (email ресурс-комнаты). Сосуществует с
  /// видеовстречей; при создании уходит resource-участником, комната сама
  /// подтверждает бронь.
  Widget _roomRow() => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.meeting_room_outlined),
        title: TextField(
          controller: _room,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Переговорка (email комнаты)',
            hintText: 'room@…',
            border: InputBorder.none,
          ),
        ),
      );

  Widget _calendarPicker(List<Calendar> cals) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_today_outlined),
        title: const Text('Календарь'),
        trailing: DropdownButton<String>(
          value: _calendarId,
          onChanged: (v) => setState(() => _calendarId = v),
          items: [
            for (final c in cals)
              DropdownMenuItem(
                value: c.id,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: Color(c.effectiveColor), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(c.effectiveName),
                ]),
              ),
          ],
        ),
      );

  Widget _dateTimeRow(
      String label, DateTime value, ValueChanged<DateTime> onChange) {
    String two(int v) => v.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
              width: 64,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (d != null) {
                onChange(DateTime(
                    d.year, d.month, d.day, value.hour, value.minute));
              }
            },
            child: Text('${two(value.day)}.${two(value.month)}.${value.year}'),
          ),
          if (!_allDay)
            TextButton(
              onPressed: () async {
                final t = await showTimePicker(
                    context: context,
                    initialTime:
                        TimeOfDay(hour: value.hour, minute: value.minute));
                if (t != null) {
                  onChange(DateTime(value.year, value.month, value.day,
                      t.hour, t.minute));
                }
              },
              child: Text('${two(value.hour)}:${two(value.minute)}'),
            ),
        ],
      ),
    );
  }

  /// Enter в однострочном поле → создать/применить (как кнопка «Готово»).
  /// В многострочных «Заметках» и поле участников Enter не сюда — там свой смысл.
  void _submitByEnter(List<Calendar> cals) {
    if (cals.isNotEmpty) _save(cals);
  }

  Future<void> _save(List<Calendar> cals) async {
    final cal =
        cals.firstWhere((c) => c.id == _calendarId, orElse: () => cals.first);
    final existing = widget.existing;

    Conference? conf = existing?.conference;
    if (_conference == null) {
      conf = null;
    } else if (conf?.type != _conference) {
      // «Ожидающая» — реальную встречу заведёт ConferenceProvisioner при пуше
      // Outbox (сходит в нужную УЗ: Teams/Meet/Zoom/Telemost).
      conf = Conference.pending(_conference!);
    }

    // Переговорка (если задана) — ресурс-участник, добавляем к людям.
    final roomEmail = _room.text.trim();
    final attendees = [
      ..._attendees,
      if (roomEmail.isNotEmpty)
        Attendee(email: roomEmail, isResource: true),
    ];

    final event = CalendarEvent(
      id: existing?.id ?? '',
      calendarId: cal.id,
      title: _title.text.trim().isEmpty ? 'Без названия' : _title.text.trim(),
      startUtc: _start.toUtc(),
      endUtc: _end.toUtc(),
      timeZoneId: existing?.timeZoneId ?? 'Europe/Moscow',
      allDay: _allDay,
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      description: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      attendees: attendees,
      recurrenceRule: _recurrenceRule,
      recurrenceId: existing?.recurrenceId,
      myResponse: existing?.myResponse ?? ResponseStatus.organizer,
      showAs: _showAs,
      visibility: _visibility,
      reminders: existing?.reminders ?? const [],
      conference: conf,
      source: EventSource(
        accountId: cal.accountId,
        calendarId: cal.id,
        providerEventId: existing?.source.providerEventId,
        etag: existing?.source.etag,
      ),
    );

    // Как перенос/ресайз — через отложенную отправку: правка видна сразу, в
    // облако уходит по таймеру (commitDelay) или по кнопке «В облако» сверху;
    // «Отменить» вернёт исходное (для нового — удалит).
    final delay = ref.read(commitDelayProvider);
    final pending = ref.read(pendingEditsProvider.notifier);
    if (_isNew) {
      await pending.stage(event.withId(const Uuid().v4()), delay, op: 'create');
    } else {
      await pending.stage(event, delay, op: 'update', original: existing);
    }
    if (mounted) Navigator.pop(context);
  }

}
