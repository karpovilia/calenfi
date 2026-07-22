import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/secure/credential_source.dart';
import '../../domain/models/account.dart';
import '../../domain/models/calendar.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/refresh_policy.dart';

/// Экран учётных записей (FR-A): список УЗ, статусы, календари с тумблерами
/// видимости, удаление, добавление.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final calendarsAsync = ref.watch(calendarsStreamProvider);
    final calendars = calendarsAsync.value ?? const <Calendar>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Учётные записи')),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (accounts) => ListView(
          children: [
            for (final acc in accounts)
              _AccountTile(
                account: acc,
                calendars:
                    calendars.where((c) => c.accountId == acc.id).toList(),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Добавить учётную запись'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить учётную запись'),
        content: const Text(
          'Подключение реальных провайдеров (Google, O365, Yandex CalDAV, '
          'Exchange) появится на Этапе 2 — после регистрации OAuth-клиентов '
          'и ввода кредов. Сейчас работают демо-аккаунты на моках.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Ок')),
        ],
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account, required this.calendars});
  final Account account;
  final List<Calendar> calendars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      leading: _providerIcon(account.provider),
      title: Text(account.displayName),
      subtitle: Text('${account.email} · ${_statusLabel(account.status)}'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'delete') {
            await ref.read(accountRepositoryProvider).deleteAccount(account.id);
          } else if (v == 'password') {
            await _changePassword(context, ref);
          }
        },
        itemBuilder: (_) => [
          if (_usesPassword(account.provider))
            const PopupMenuItem(
                value: 'password', child: Text('Изменить пароль')),
          const PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ],
      ),
      children: [
        // Расписание автообновления этого аккаунта (FR-A10).
        ListTile(
          dense: true,
          leading: const Icon(Icons.sync, size: 20),
          title: const Text('Автообновление'),
          trailing: DropdownButton<int?>(
            value: account.refresh.mode == RefreshMode.manual
                ? null
                : account.refresh.interval.inMinutes,
            onChanged: (m) {
              final policy = m == null
                  ? const RefreshPolicy(mode: RefreshMode.manual)
                  : RefreshPolicy(
                      mode: RefreshMode.interval,
                      interval: Duration(minutes: m));
              ref.read(accountRepositoryProvider).setRefresh(account.id, policy);
            },
            items: const [
              DropdownMenuItem(value: null, child: Text('Вручную')),
              DropdownMenuItem(value: 1, child: Text('1 мин')),
              DropdownMenuItem(value: 5, child: Text('5 мин')),
              DropdownMenuItem(value: 10, child: Text('10 мин')),
              DropdownMenuItem(value: 15, child: Text('15 мин')),
              DropdownMenuItem(value: 30, child: Text('30 мин')),
              DropdownMenuItem(value: 60, child: Text('1 час')),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final c in calendars)
          ListTile(
            dense: true,
            leading: Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                    color: Color(c.color), shape: BoxShape.circle)),
            title: Text(c.name),
            trailing: c.visible
                ? null
                : const Text('скрыт',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        if (calendars.isEmpty)
          const ListTile(dense: true, title: Text('Нет календарей')),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Видимость календарей — в Настройки → Календари',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ],
    );
  }

  /// Провайдеры, работающие по паролю (в отличие от OAuth-токенов).
  static bool _usesPassword(ProviderType p) =>
      p == ProviderType.caldav || p == ProviderType.ews;

  /// Диалог ввода нового пароля → запись в secrets.env → пересоздание
  /// провайдеров и немедленный синк, чтобы аккаунт снова подключился.
  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) => _PasswordDialog(email: account.email),
    );
    if (pass == null || pass.isEmpty) return;

    final varName = account.provider == ProviderType.ews
        ? CredentialSource.ewsPasswordVar(account.email)
        : CredentialSource.caldavPasswordVar(account.email);
    await writeSecret(varName, pass);
    // Сбрасываем кэш провайдеров, чтобы новый пароль подхватился, и синкаем.
    ref.invalidate(providerRegistryProvider);
    messenger.showSnackBar(const SnackBar(
        content: Text('Пароль сохранён, синхронизирую…'),
        duration: Duration(seconds: 2)));
    await ref.read(syncTriggerProvider)();
  }

  Widget _providerIcon(ProviderType p) {
    final icon = switch (p) {
      ProviderType.google => Icons.event,
      ProviderType.graph => Icons.business,
      ProviderType.caldav => Icons.cloud_outlined,
      ProviderType.ews => Icons.dns_outlined,
    };
    return CircleAvatar(child: Icon(icon, size: 18));
  }

  String _statusLabel(AccountStatus s) => switch (s) {
        AccountStatus.ok => 'подключён',
        AccountStatus.authError => 'ошибка авторизации',
        AccountStatus.needsReconnect => 'требуется переподключение',
        AccountStatus.syncError => 'сбой синхронизации',
        AccountStatus.offline => 'нет сети',
      };
}

/// Диалог ввода нового пароля учётной записи (CalDAV app-password / EWS).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.email});
  final String email;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый пароль'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.email,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _obscure,
            onSubmitted: (v) => Navigator.pop(context, v),
            decoration: InputDecoration(
              labelText: 'Пароль',
              helperText:
                  'Для CalDAV — пароль приложения, не основной пароль почты',
              helperMaxLines: 2,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
