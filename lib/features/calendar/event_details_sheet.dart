import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/attendee.dart';
import '../../domain/models/calendar_event.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/merged_event.dart';
import '../../domain/usecases/event_actions.dart';
import '../../services/maps_service.dart';
import '../event_editor/event_editor_screen.dart';
import 'calendar_state.dart';
import 'linkified_text.dart';
import 'pending_edits.dart';

/// Карточка события (FR-V10) со склейкой источников (FR-D3), джойном видеовстречи
/// (FR-M2), RSVP (FR-R2) и редактированием/удалением (FR-E3/E4).
void showEventDetails(BuildContext context, MergedEvent event) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Шорткаты (Esc — закрыть, Del — удалить) навешаны внутри _EventDetails,
    // где доступен ref для удаления через eventActions.
    builder: (ctx) => _EventDetails(event: event),
  );
}

class _EventDetails extends ConsumerWidget {
  const _EventDetails({required this.event});
  final MergedEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event.primary;
    final calInfo = ref.watch(calendarInfoProvider);
    final s = e.startUtc.toLocal();
    final en = e.endUtc.toLocal();
    // Ссылка на созвон: из распознанной конференции либо, если её нет, —
    // найденная онлайн-ссылка в месте/описании (чтобы копирование работало
    // и когда провайдер не разобрал конференцию, напр. на некоторых событиях).
    final meetingUrl = e.conference?.joinUrl ?? _detectMeetingUrl(e);
    final meetingType = e.conference?.type ??
        (meetingUrl != null ? _guessConfType(meetingUrl) : ConferenceType.unknown);
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    // Строка даты/времени с ДАТОЙ (не только время) — иначе непонятно, какого
    // числа событие (важно для результатов поиска).
    String schedule() {
      String two(int v) => v.toString().padLeft(2, '0');
      const wd = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
      String dmy(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';
      final sameDay =
          s.year == en.year && s.month == en.month && s.day == en.day;
      if (e.allDay) {
        return sameDay
            ? '${wd[s.weekday - 1]}, ${dmy(s)} · весь день'
            : '${dmy(s)} — ${dmy(en)} · весь день';
      }
      if (sameDay) {
        return '${wd[s.weekday - 1]}, ${dmy(s)} · ${hm(s)} — ${hm(en)}';
      }
      return '${wd[s.weekday - 1]} ${dmy(s)} ${hm(s)} — '
          '${wd[en.weekday - 1]} ${dmy(en)} ${hm(en)}';
    }

    // Горизонтальный отступ — ВНУТРИ ScrollView, чтобы десктопный скроллбар
    // рисовался у самого края окна и не накрывал контент (кнопку копирования id).
    final mq = MediaQuery.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        // Del/Backspace — удалить открытое событие (с подтверждением).
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _confirmAndDelete(context, ref, e),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _confirmAndDelete(context, ref, e),
      },
      child: Focus(
        autofocus: true,
        child: Padding(
      // Снизу: 20 базовый + системная навигация (жест-бар/кнопки на S23 и т.п.)
      // + 50 px запаса, чтобы кнопки футера не перекрывались меню телефона.
      padding: EdgeInsets.only(
          bottom: 20 + 50 + mq.viewPadding.bottom + mq.viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditableTitle(event: e),
            const SizedBox(height: 10),
            _row(Icons.schedule, schedule()),
            if (e.location != null && e.location!.trim().isNotEmpty)
              _Copyable(value: e.location!.trim(), child: _locationRow(e)),
            if (e.room != null)
              _row(Icons.meeting_room_outlined,
                  e.room!.displayName ?? e.room!.email),
            _row(Icons.event_available_outlined, _responseLabel(e.myResponse)),
            if (e.isCancelled) _row(Icons.cancel_outlined, 'Отменено / удалено'),

            // источник: из какого календаря вытянуто событие (FR-V10)
            if (!event.isMerged) _calendarRow(calInfo[e.calendarId]),

            // видеовстреча (FR-M2)
            if (meetingUrl != null) ...[
              const SizedBox(height: 12),
              _MeetingJoinRow(
                  url: meetingUrl, label: _confLabel(meetingType)),
            ],

            // источники склейки (FR-D3)
            if (event.isMerged) ...[
              const SizedBox(height: 14),
              Text('В нескольких календарях (${event.sources.length}):',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              for (final src in event.sources)
                _calendarRow(calInfo[src.calendarId],
                    fallback: src.calendarId,
                    trailing: _responseLabel(src.myResponse)),
            ],

            // участники-люди и их статусы подтверждения (FR-R3); переговорка
            // (ресурс) показана отдельной строкой выше.
            if (e.people.isNotEmpty) ...[
              const SizedBox(height: 14),
              Builder(builder: (_) {
                final acc = e.people.where((a) => a.response == ResponseStatus.accepted).length;
                return Row(children: [
                  const Icon(Icons.people_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('Участники: ${e.people.length}  ·  принял${acc == 1 ? '' : 'и'} $acc',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]);
              }),
              const SizedBox(height: 6),
              for (final a in _sortedAttendees(e.people)) _AttendeeRow(a),
            ],

            if (e.description != null && e.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              LinkifiedText(e.description!),
            ],

            // ссылка в облаке (кликабельна) + компактный id (для CLI --id)
            const SizedBox(height: 10),
            if (e.webUrl != null && e.webUrl!.isNotEmpty)
              _Copyable(
                value: e.webUrl!,
                child: InkWell(
                  onTap: () => _launch(e.webUrl!),
                  child:
                      _row(Icons.open_in_new, 'Открыть в облаке', link: true),
                ),
              ),
            _Copyable(value: e.id, child: _IdRow(label: 'ID', value: e.id)),

            const SizedBox(height: 16),

            // RSVP (FR-R2)
            if (e.myResponse != ResponseStatus.organizer)
              Wrap(spacing: 8, children: [
                _rsvpChip(context, ref, e, ResponseStatus.accepted, 'Принять'),
                _rsvpChip(context, ref, e, ResponseStatus.tentative, 'Под вопросом'),
                _rsvpChip(context, ref, e, ResponseStatus.declined, 'Отклонить'),
              ]),

            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () {
                  final nav = Navigator.of(context);
                  final rootContext = nav.context;
                  nav.pop();
                  EventEditor.open(rootContext, existing: e);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Изменить'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () => _confirmAndDelete(context, ref, e),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить'),
              ),
            ]),
          ],
          ),
        ),
      ),
        ),
      ),
    );
  }

  /// Подтвердить и удалить открытое событие (общий путь для кнопки и клавиши Del).
  Future<void> _confirmAndDelete(
      BuildContext context, WidgetRef ref, CalendarEvent e) async {
    final nav = Navigator.of(context);
    final scope = await _askDeleteScope(context, e.isRecurring);
    if (scope == null) return; // отмена
    await ref.read(eventActionsProvider).delete(e, scope: scope);
    nav.pop();
  }

  Widget _rsvpChip(BuildContext context, WidgetRef ref, CalendarEvent e,
      ResponseStatus r, String label) {
    final selected = e.myResponse == r;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) async {
        await ref.read(eventActionsProvider).rsvp(e, r);
        if (context.mounted) Navigator.pop(context);
      },
    );
  }

  static Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Строка «источник события»: цветной кружок календаря + «Имя · Аккаунт».
Widget _calendarRow(CalendarInfo? info, {String? fallback, String? trailing}) {
  final name = info?.name ?? fallback ?? 'Неизвестный календарь';
  final account = info?.accountName;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
            color: info != null ? Color(info.color) : Colors.grey,
            shape: BoxShape.circle),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text.rich(TextSpan(children: [
          TextSpan(text: name),
          if (account != null && account.isNotEmpty)
            TextSpan(
                text: '  ·  $account',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ])),
      ),
      if (trailing != null)
        Text(trailing, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ]),
  );
}

Widget _row(IconData icon, String text, {bool link = false, String? trailing}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: link ? Colors.lightBlueAccent : null,
                  decoration: link ? TextDecoration.underline : null)),
        ),
        if (trailing != null)
          Text(trailing, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ]),
    );

/// Спрашивает область удаления. Для повторяющегося события — 3 варианта
/// (это / это и последующие / вся серия), для одиночного — обычное
/// подтверждение. Возвращает null, если пользователь отменил.
Future<RecurrenceScope?> _askDeleteScope(BuildContext context, bool recurring) {
  if (!recurring) {
    return showDialog<RecurrenceScope?>(
      context: context,
      builder: (ctx) => CallbackShortcuts(
        bindings: {
          // Enter — подтвердить удаление, Esc — отменить (закрыть попап).
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              Navigator.pop(ctx, RecurrenceScope.all),
          const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
              Navigator.pop(ctx, RecurrenceScope.all),
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.pop(ctx),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: const Text('Удалить событие?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, RecurrenceScope.all),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<RecurrenceScope?>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => CallbackShortcuts(
      bindings: {
        // Esc — отменить выбор области удаления. Enter не биндим: 3 варианта,
        // однозначного действия по умолчанию нет.
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(ctx),
      },
      child: Focus(
        autofocus: true,
        child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Повторяющееся событие — что удалить?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event_busy_outlined),
            title: const Text('Только это событие'),
            onTap: () => Navigator.pop(ctx, RecurrenceScope.thisOnly),
          ),
          ListTile(
            leading: const Icon(Icons.arrow_forward),
            title: const Text('Это и последующие'),
            onTap: () => Navigator.pop(ctx, RecurrenceScope.thisAndFollowing),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Всю серию'),
            textColor: Colors.redAccent,
            iconColor: Colors.redAccent,
            onTap: () => Navigator.pop(ctx, RecurrenceScope.all),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Отмена'),
            onTap: () => Navigator.pop(ctx),
          ),
        ],
      ),
        ),
      ),
    ),
  );
}

/// Строка «место» с защитой от абсурда «URL / онлайн-встреча → Яндекс.Карты».
/// Правило: есть ссылка и она НЕ картовая → браузер; строка похожа на
/// онлайн-встречу (Teams/Zoom/Телемост…) → это не адрес, в карты не шлём;
/// иначе — настоящий адрес → карты.
Widget _locationRow(CalendarEvent e) {
  final loc = e.location!.trim();
  final url = _firstUrl(loc);
  final mapsUrl = url != null && _isMapsUrl(url);
  final online = url == null && _isOnlineMeetingName(loc);

  // Плейсхолдер онлайн-встречи ("Microsoft Teams Meeting") или ссылка, равная
  // join-url созвона — не дублируем: её закрывает кнопка «Присоединиться».
  final joinUrl = e.conference?.joinUrl ?? _detectMeetingUrl(e);
  if (joinUrl != null &&
      (online || (url != null && url == joinUrl))) {
    return const SizedBox.shrink();
  }
  // Любая НЕ-картовая ссылка в поле места → браузер, не карты.
  if (url != null && !mapsUrl) {
    return InkWell(
      onTap: () => _openUrl(url),
      child: _row(Icons.link, loc, link: true),
    );
  }
  // Онлайн-встреча без распознанной конференции — не адрес, в карты не шлём.
  if (online) {
    return _row(Icons.videocam_outlined, loc);
  }
  // Голое число/код без единой буквы (напр. Teams conference id «3986690») —
  // это не адрес: показываем обычным текстом, без кликабельной ссылки в карты.
  if (!RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(loc)) {
    return _row(Icons.tag, loc);
  }
  // Настоящий адрес (или картовая ссылка) → Яндекс.Карты.
  return InkWell(
    onTap: () => MapsService.openLocation(loc),
    child: _row(Icons.place_outlined, loc, link: true),
  );
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Первая http(s)-ссылка внутри произвольного текста (со срезанным хвостом).
String? _firstUrl(String text) {
  final m =
      RegExp(r'https?://[^\s<>()]+', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  var u = m.group(0)!;
  while (u.isNotEmpty && '>)].,;:"\'<'.contains(u[u.length - 1])) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

/// Ссылка на онлайн-встречу в поле «место» или в описании, когда провайдер
/// не разобрал конференцию в `e.conference`. Нужна, чтобы работало
/// копирование/джойн даже для «сырых» событий.
String? _detectMeetingUrl(CalendarEvent e) {
  for (final text in [e.location, e.description]) {
    if (text == null || text.trim().isEmpty) continue;
    final url = _firstUrl(text);
    if (url != null && _isMeetingUrl(url)) return url;
  }
  return null;
}

/// Похоже ли на ссылку видеовстречи (по хосту), чтобы не принять за созвон
/// произвольный URL из описания.
bool _isMeetingUrl(String url) {
  final u = url.toLowerCase();
  const hosts = [
    'teams.microsoft.com', 'teams.live.com', 'teams.microsoft.us',
    'zoom.us', 'zoom.com', 'meet.google.com', 'telemost.yandex',
    'telemost.360', 'ktalk.ru', 'ktalk.io', 'contour.talk', 'whereby.com',
    'webinar.ru', 'meet.jit.si', 'jazz.sber', 'sberjazz', 'dion.vc',
    'talk.contour', 'meet.dion', 'skype.com',
  ];
  return hosts.any(u.contains);
}

/// Тип конференции по ссылке — для подписи кнопки, когда `e.conference` пуст.
ConferenceType _guessConfType(String url) {
  final u = url.toLowerCase();
  if (u.contains('teams')) return ConferenceType.teams;
  if (u.contains('zoom')) return ConferenceType.zoom;
  if (u.contains('meet.google')) return ConferenceType.meet;
  if (u.contains('telemost')) return ConferenceType.telemost;
  return ConferenceType.unknown;
}

bool _isMapsUrl(String url) {
  final u = url.toLowerCase();
  return (u.contains('yandex.') && u.contains('/maps')) ||
      u.contains('maps.yandex') ||
      (u.contains('google.') && u.contains('/maps')) ||
      u.contains('goo.gl/maps') ||
      u.contains('maps.app.goo.gl') ||
      u.contains('2gis.');
}

bool _isOnlineMeetingName(String loc) {
  final s = loc.toLowerCase();
  const names = [
    'teams', 'zoom', 'google meet', 'meet.google', 'телемост', 'telemost',
    'webinar', 'вебинар', 'ktalk', 'контур.толк', 'skype', 'whereby',
    'jazz', 'dion', 'discord', 'hangout', 'видеоконференц', 'видеовстреч',
    'видеосвяз', 'созвон', 'online meeting', 'онлайн-встреч',
  ];
  return names.any(s.contains);
}

String _confLabel(ConferenceType t) => switch (t) {
      ConferenceType.meet => 'Google Meet',
      ConferenceType.teams => 'Teams',
      ConferenceType.zoom => 'Zoom',
      ConferenceType.telemost => 'Телемост',
      ConferenceType.unknown => 'видеовстреча',
    };

String _responseLabel(ResponseStatus r) => switch (r) {
      ResponseStatus.accepted => 'Принято',
      ResponseStatus.declined => 'Отклонено',
      ResponseStatus.tentative => 'Под вопросом',
      ResponseStatus.needsAction => 'Ожидает ответа',
      ResponseStatus.organizer => 'Вы организатор',
    };

/// Заголовок события: при наведении мыши справа (в ЗАРЕЗЕРВИРОВАННОМ месте, без
/// наложения на текст) появляются кнопки «скопировать» и «изменить название».
/// Правка — инлайн, уходит через отложенную отправку (как перенос/ресайз).
class _EditableTitle extends ConsumerStatefulWidget {
  const _EditableTitle({required this.event});
  final CalendarEvent event;
  @override
  ConsumerState<_EditableTitle> createState() => _EditableTitleState();
}

class _EditableTitleState extends ConsumerState<_EditableTitle> {
  static const _style = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  bool _hover = false;
  bool _editing = false;
  late String _title = widget.event.title;
  late final TextEditingController _ctl =
      TextEditingController(text: widget.event.title);
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    _ctl.text = _title;
    setState(() => _editing = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _cancel() => setState(() => _editing = false);

  Future<void> _save() async {
    final t = _ctl.text.trim();
    setState(() => _editing = false);
    if (t.isEmpty || t == _title) return;
    setState(() => _title = t);
    final delay = ref.read(commitDelayProvider);
    await ref.read(pendingEditsProvider.notifier).stage(
        widget.event.copyWith(title: t), delay,
        op: 'update', original: widget.event);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Название изменено'),
          duration: Duration(seconds: 1)));
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _title));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Скопировано'), duration: Duration(seconds: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Row(children: [
        Expanded(
          child: TextField(
            controller: _ctl,
            focusNode: _focus,
            style: _style,
            maxLines: 1,
            decoration: const InputDecoration(isDense: true),
            onSubmitted: (_) => _save(),
          ),
        ),
        IconButton(
            icon: const Icon(Icons.check, size: 20, color: Colors.green),
            tooltip: 'Сохранить',
            onPressed: _save),
        IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Отмена',
            onPressed: _cancel),
      ]);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: SelectableText(_title, style: _style)),
          const SizedBox(width: 4),
          // Кнопки в зарезервированном месте: opacity 0 (место занято, но не
          // ловят указатель), появляются при наведении — без наложения/сдвига.
          AnimatedOpacity(
            opacity: _hover ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: IgnorePointer(
              ignoring: !_hover,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _btn(Icons.copy, 'Скопировать', _copy),
                _btn(Icons.edit_outlined, 'Изменить название', _startEdit),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        iconSize: 16,
        tooltip: tip,
        icon: Icon(icon, color: Colors.grey),
        onPressed: onTap,
      );
}

/// Notion-подобная обёртка: при наведении мыши справа над строкой всплывает
/// кнопка «скопировать» (оверлей, layout не сдвигается). На тач-экране (нет
/// hover) не мешает — прежние тап-копирования остаются.
class _Copyable extends StatefulWidget {
  const _Copyable({required this.value, required this.child});
  final String value;
  final Widget child;
  @override
  State<_Copyable> createState() => _CopyableState();
}

class _CopyableState extends State<_Copyable> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        children: [
          widget.child,
          if (_hover)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: cs.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () async {
                      await Clipboard.setData(
                          ClipboardData(text: widget.value));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Скопировано'),
                                duration: Duration(seconds: 1)));
                      }
                    },
                    child: Tooltip(
                      message: 'Скопировать',
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(Icons.copy, size: 15, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Строка «Присоединиться» к видеовстрече. Иконка копирования ссылки скрыта и
/// появляется только при наведении на строку (FR-M2).
class _MeetingJoinRow extends StatefulWidget {
  const _MeetingJoinRow({required this.url, required this.label});
  final String url;
  final String label;
  @override
  State<_MeetingJoinRow> createState() => _MeetingJoinRowState();
}

class _MeetingJoinRowState extends State<_MeetingJoinRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(children: [
        Flexible(
          child: FilledButton.icon(
            onPressed: () => _EventDetails._launch(widget.url),
            icon: const Icon(Icons.videocam),
            label: Text('Присоединиться · ${widget.label}',
                overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 8),
        _hoverCopyIcon(context, _hover, widget.url,
            message: 'Ссылка на встречу скопирована', size: 18),
      ]),
    );
  }
}

/// Копирование в буфер + короткий тост. Общий путь для всех copy-иконок карточки.
Future<void> _copyToClipboard(BuildContext context, String value,
    {String message = 'Скопировано'}) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), duration: const Duration(seconds: 1)));
  }
}

/// Иконка копирования, занимающая место постоянно, но видимая только на ховере
/// (`visible`). Постоянный размер — чтобы соседний контент не прыгал.
Widget _hoverCopyIcon(BuildContext context, bool visible, String value,
    {String message = 'Скопировано', double size = 14}) {
  return AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 120),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: visible ? () => _copyToClipboard(context, value, message: message) : null,
      child: Tooltip(
        message: 'Скопировать',
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.copy, size: size, color: Colors.grey),
        ),
      ),
    ),
  );
}

/// Копируемая строка идентификатора (для агентского CLI: `--id`).
class _IdRow extends StatelessWidget {
  const _IdRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label скопирован'), duration: const Duration(seconds: 1)));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text('$label: ',
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 11, fontFamily: 'monospace')),
          ),
          const Icon(Icons.copy, size: 13, color: Colors.grey),
        ]),
      ),
    );
  }
}

/// Сортировка участников: организатор → принял → под вопросом → без ответа → отклонил.
List<Attendee> _sortedAttendees(List<Attendee> a) {
  int rank(ResponseStatus r) => switch (r) {
        ResponseStatus.organizer => 0,
        ResponseStatus.accepted => 1,
        ResponseStatus.tentative => 2,
        ResponseStatus.needsAction => 3,
        ResponseStatus.declined => 4,
      };
  final sorted = [...a];
  sorted.sort((x, y) {
    final byOrg = (y.isOrganizer ? 1 : 0) - (x.isOrganizer ? 1 : 0);
    if (byOrg != 0) return byOrg;
    return rank(x.response).compareTo(rank(y.response));
  });
  return sorted;
}

/// Строка участника: иконка статуса + имя/почта + (организатор) + ярлык ответа.
/// Иконка копирования появляется на ховере ВПЛОТНУЮ к имени (а не у правого
/// края строки — тянуться в другой конец неудобно).
class _AttendeeRow extends StatefulWidget {
  const _AttendeeRow(this.attendee);
  final Attendee attendee;
  @override
  State<_AttendeeRow> createState() => _AttendeeRowState();
}

class _AttendeeRowState extends State<_AttendeeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.attendee;
    final (icon, color) = switch (a.response) {
      ResponseStatus.accepted => (Icons.check_circle, Colors.green),
      ResponseStatus.declined => (Icons.cancel, Colors.redAccent),
      ResponseStatus.tentative => (Icons.help, Colors.orange),
      ResponseStatus.organizer => (Icons.stars, Colors.amber),
      ResponseStatus.needsAction => (Icons.schedule, Colors.grey),
    };
    final name = (a.displayName != null && a.displayName!.isNotEmpty)
        ? a.displayName!
        : a.email;
    final copyValue = name != a.email ? '$name <${a.email}>' : a.email;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                      child: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  // copy-иконка сразу за именем
                  _hoverCopyIcon(context, _hover, copyValue,
                      message: 'Участник скопирован'),
                  if (a.isOrganizer)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('организатор',
                          style: TextStyle(color: Colors.amber, fontSize: 10)),
                    ),
                  if (a.optional)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('необязателен',
                          style: TextStyle(color: Colors.grey, fontSize: 10)),
                    ),
                ]),
                if (name != a.email)
                  Text(a.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Text(_responseLabel(a.response),
              style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 11)),
        ]),
      ),
    );
  }
}
