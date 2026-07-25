import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'connect_account.dart';

/// Полноэкранный экран подключения учётной записи. Раньше был тесный
/// bottom-sheet — на телефоне он занимал пол-экрана и выглядел куце; плюс
/// диалоги показывались на уже закрытом контексте шита и коннект «молчал».
Future<void> openAddAccount(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const AddAccountScreen()),
  );
}

class AddAccountScreen extends ConsumerWidget {
  const AddAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accConnectAccount)),
      body: ListView(
        children: [
          _SectionHeader(l10n.accSectionCalendars),
          _tile(Icons.event, 'Google', l10n.accSignInBrowser,
              () => _oauth(context, ref, 'Google',
                  () => ref.read(connectAccountServiceProvider).connectGoogle())),
          _tile(Icons.business, 'Microsoft 365 / Outlook', l10n.accSignInBrowser,
              () => _oauth(context, ref, 'Microsoft',
                  () => ref.read(connectAccountServiceProvider).connectMicrosoft())),
          _tile(Icons.cloud_outlined, 'Yandex (CalDAV)', l10n.accAppPassword,
              () => _openForm(context, _ProviderKind.caldav)),
          _tile(Icons.dns_outlined, 'Exchange (EWS)', l10n.accLoginPassword,
              () => _openForm(context, _ProviderKind.ews)),
          const Divider(height: 32),
          _SectionHeader(l10n.accSectionVideoMeetings),
          _tile(Icons.videocam_outlined, 'Yandex Telemost', l10n.accSignInBrowser,
              () => _oauth(context, ref, 'Telemost',
                  () => ref
                      .read(connectAccountServiceProvider)
                      .connectTelemost()
                      .then((_) => 'Telemost'))),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap) =>
      ListTile(
        leading: CircleAvatar(child: Icon(icon, size: 18)),
        title: Text(title),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  /// OAuth-провайдеры (Google/Microsoft/Telemost): открываем браузер, ждём вход.
  Future<void> _oauth(BuildContext context, WidgetRef ref, String name,
      Future<String> Function() connect) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text(l10n.accCompleteSignIn(name)),
        duration: const Duration(seconds: 10)));
    try {
      final who = await connect();
      messenger.showSnackBar(SnackBar(content: Text(l10n.accConnected(who))));
      if (nav.canPop()) nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.accFailed(e.toString()))));
    }
  }

  Future<void> _openForm(BuildContext context, _ProviderKind kind) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _CredentialFormScreen(kind: kind)),
    );
  }
}

enum _ProviderKind { caldav, ews }

/// Полноэкранная форма ввода реквизитов для парольных провайдеров.
class _CredentialFormScreen extends ConsumerStatefulWidget {
  const _CredentialFormScreen({required this.kind});
  final _ProviderKind kind;

  @override
  ConsumerState<_CredentialFormScreen> createState() =>
      _CredentialFormScreenState();
}

class _CredentialFormScreenState extends ConsumerState<_CredentialFormScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _host = TextEditingController(text: 'caldav.yandex.ru');
  final _port = TextEditingController(text: '8443');
  final _ewsUrl = TextEditingController();
  final _user = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  bool get _isCaldav => widget.kind == _ProviderKind.caldav;

  @override
  void dispose() {
    for (final c in [_email, _pass, _host, _port, _ewsUrl, _user]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = L10n.of(context);
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.accFillEmailPassword)));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final svc = ref.read(connectAccountServiceProvider);
      if (_isCaldav) {
        await svc.connectCaldav(
          email: _email.text.trim(),
          appPassword: _pass.text,
          host: _host.text.trim().isEmpty ? 'caldav.yandex.ru' : _host.text.trim(),
          port: int.tryParse(_port.text) ?? 8443,
        );
      } else {
        await svc.connectEws(
          email: _email.text.trim(),
          password: _pass.text,
          ewsUrl: _ewsUrl.text.trim().isEmpty ? null : _ewsUrl.text.trim(),
          user: _user.text.trim().isEmpty ? null : _user.text.trim(),
        );
      }
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.accConnected(_email.text.trim()))));
      nav.pop(); // форма
      if (nav.canPop()) nav.pop(); // экран выбора провайдера
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.accFailed(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(_isCaldav ? 'Yandex / CalDAV' : 'Exchange (EWS)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: InputDecoration(
                labelText: l10n.accEmail,
                prefixIcon: const Icon(Icons.alternate_email)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: _isCaldav ? l10n.accAppPassword : l10n.accPassword,
              prefixIcon: const Icon(Icons.key_outlined),
              helperText: _isCaldav ? l10n.accAppPasswordHelper : null,
              helperMaxLines: 2,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_isCaldav)
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                    controller: _host,
                    decoration: InputDecoration(labelText: l10n.accHost)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.accPort)),
              ),
            ])
          else ...[
            TextField(
              controller: _ewsUrl,
              decoration: InputDecoration(
                  labelText: l10n.accEwsUrlLabel,
                  hintText: 'https://mail.example.org/EWS/Exchange.asmx'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: InputDecoration(
                  labelText: l10n.accLoginIfDifferent,
                  hintText: r'DOMAIN\user'),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link),
            label: Text(_busy ? l10n.accConnecting : l10n.accConnect),
          ),
        ],
      ),
    );
  }
}

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
