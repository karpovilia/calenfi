import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connect_account.dart';

/// Экран/лист выбора провайдера для подключения реальной учётной записи.
/// Google/Microsoft — вход через браузер (OAuth), Yandex/Exchange — по паролю.
Future<void> showAddAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _AddAccountSheet(),
  );
}

class _AddAccountSheet extends ConsumerWidget {
  const _AddAccountSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Подключить учётную запись',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          _tile(context, Icons.event, 'Google',
              'Вход через браузер', () => _google(context, ref)),
          _tile(context, Icons.business, 'Microsoft 365 / Outlook',
              'Вход через браузер', () => _microsoft(context, ref)),
          _tile(context, Icons.cloud_outlined, 'Yandex (CalDAV)',
              'Пароль приложения', () => _caldav(context, ref)),
          _tile(context, Icons.dns_outlined, 'Exchange (EWS)',
              'Логин и пароль', () => _ews(context, ref)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _tile(BuildContext ctx, IconData icon, String title, String sub,
          VoidCallback onTap) =>
      ListTile(
        leading: CircleAvatar(child: Icon(icon, size: 18)),
        title: Text(title),
        subtitle: Text(sub),
        onTap: onTap,
      );

  Future<void> _google(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    await _runOAuth(context, ref, 'Google',
        () => ref.read(connectAccountServiceProvider).connectGoogle());
  }

  Future<void> _microsoft(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    await _runOAuth(context, ref, 'Microsoft',
        () => ref.read(connectAccountServiceProvider).connectMicrosoft());
  }

  Future<void> _caldav(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    final r = await showDialog<_CaldavInput>(
        context: context, builder: (_) => const _CaldavDialog());
    if (r == null) return;
    await _guard(messenger, 'Подключаю ${r.email}…', () async {
      await ref.read(connectAccountServiceProvider).connectCaldav(
          email: r.email, appPassword: r.password, host: r.host, port: r.port);
    });
  }

  Future<void> _ews(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    final r = await showDialog<_EwsInput>(
        context: context, builder: (_) => const _EwsDialog());
    if (r == null) return;
    await _guard(messenger, 'Подключаю ${r.email}…', () async {
      await ref.read(connectAccountServiceProvider).connectEws(
          email: r.email,
          password: r.password,
          ewsUrl: r.ewsUrl,
          user: r.user);
    });
  }

  /// OAuth: показываем «ожидаем вход в браузере», ждём результат.
  Future<void> _runOAuth(BuildContext context, WidgetRef ref, String name,
      Future<String> Function() connect) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text('$name: завершите вход в открывшемся браузере…'),
        duration: const Duration(seconds: 8)));
    try {
      final email = await connect();
      messenger.showSnackBar(SnackBar(content: Text('Подключено: $email')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: $e')));
    }
  }

  Future<void> _guard(ScaffoldMessengerState messenger, String progress,
      Future<void> Function() run) async {
    messenger.showSnackBar(SnackBar(content: Text(progress)));
    try {
      await run();
      messenger.showSnackBar(const SnackBar(content: Text('Подключено')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось: $e')));
    }
  }
}

// ───────────────────────── CalDAV форма ─────────────────────────

class _CaldavInput {
  _CaldavInput(this.email, this.password, this.host, this.port);
  final String email, password, host;
  final int port;
}

class _CaldavDialog extends StatefulWidget {
  const _CaldavDialog();
  @override
  State<_CaldavDialog> createState() => _CaldavDialogState();
}

class _CaldavDialogState extends State<_CaldavDialog> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _host = TextEditingController(text: 'caldav.yandex.ru');
  final _port = TextEditingController(text: '8443');
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Yandex / CalDAV'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail')),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Пароль приложения',
                helperText: 'НЕ основной пароль — создайте пароль приложения',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure)),
              ),
            ),
            Row(children: [
              Expanded(
                  flex: 3,
                  child: TextField(
                      controller: _host,
                      decoration: const InputDecoration(labelText: 'Хост'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Порт'))),
            ]),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (_email.text.trim().isEmpty || _pass.text.isEmpty) return;
              Navigator.pop(
                  context,
                  _CaldavInput(_email.text.trim(), _pass.text,
                      _host.text.trim(), int.tryParse(_port.text) ?? 8443));
            },
            child: const Text('Подключить'),
          ),
        ],
      );
}

// ───────────────────────── EWS форма ─────────────────────────

class _EwsInput {
  _EwsInput(this.email, this.password, this.ewsUrl, this.user);
  final String email, password;
  final String? ewsUrl, user;
}

class _EwsDialog extends StatefulWidget {
  const _EwsDialog();
  @override
  State<_EwsDialog> createState() => _EwsDialogState();
}

class _EwsDialogState extends State<_EwsDialog> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _url.dispose();
    _user.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Exchange (EWS)'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail')),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Пароль',
                suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure)),
              ),
            ),
            TextField(
                controller: _url,
                decoration: const InputDecoration(
                    labelText: 'EWS URL (необязательно)',
                    hintText: 'https://mail.example.org/EWS/Exchange.asmx')),
            TextField(
                controller: _user,
                decoration: const InputDecoration(
                    labelText: 'Логин (если отличается)',
                    hintText: r'DOMAIN\user')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (_email.text.trim().isEmpty || _pass.text.isEmpty) return;
              Navigator.pop(
                  context,
                  _EwsInput(_email.text.trim(), _pass.text,
                      _url.text.trim().isEmpty ? null : _url.text.trim(),
                      _user.text.trim().isEmpty ? null : _user.text.trim()));
            },
            child: const Text('Подключить'),
          ),
        ],
      );
}
