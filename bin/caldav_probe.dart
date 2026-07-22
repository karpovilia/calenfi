// PoC: подключение CalDAV-аккаунта (Yandex и совместимые) и вывод событий.
// Запуск (из корня): dart run calenfi:caldav_probe <email> [--host H] [--port P]
//                    [--days N] [--all]
// Пароль приложения берётся из системного keyring (ключ <EMAIL>_CALDAV_PASSWORD),
// см. lib/data/secure/secret_store.dart.

import 'dart:io';

import 'package:calenfi/data/providers/calendar/caldav/caldav_provider.dart';
import 'package:calenfi/data/secure/credential_source.dart';
import 'package:calenfi/data/secure/secret_store.dart';
import 'package:calenfi/domain/models/account.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/domain/providers/calendar_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Future<void> main(List<String> args) async {
  tzdata.initializeTimeZones();
  final email = args.firstWhere((a) => a.contains('@'), orElse: () => '');
  if (email.isEmpty) {
    stderr.writeln('использование: caldav_probe <email> [--host H] [--port P] '
        '[--days N] [--all]');
    exit(2);
  }
  final days = _flag(args, 'days', '14');
  final host = _flag(args, 'host', 'caldav.yandex.ru');
  final port = int.parse(_flag(args, 'port', '8443'));
  final showAll = args.contains('--all');

  await SecretStore.instance.warmUp();
  final password = CredentialSource.load().caldavPassword(email);
  if (password == null) {
    stderr.writeln('нет пароля в keyring: ключ '
        '${CredentialSource.caldavPasswordVar(email)}');
    exit(1);
  }

  final account = Account(
    id: 'probe-caldav',
    provider: ProviderType.caldav,
    displayName: 'CalDAV',
    email: email,
    config: AccountConfig(
      caldavHost: host,
      caldavPort: port,
      caldavPrincipalPath: '/principals/users/$email/',
    ),
  );

  final provider = CalDavProvider(account: account, password: password);

  final auth = await provider.authenticate(account.config);
  stdout.writeln('auth: ${auth.success ? "OK" : auth.error}');

  final cals = await provider.listCalendars(account);
  stdout.writeln('календарей: ${cals.length}');
  for (final c in cals) {
    stdout.writeln('  • ${c.name}');
  }

  final now = DateTime.now().toUtc();
  final range = DateRange(now, now.add(Duration(days: int.parse(days))));

  // основной календарь — где displayname == email
  final main = cals.firstWhere(
    (c) => c.name == account.email,
    orElse: () => cals.first,
  );
  stdout.writeln('\nсобытия из «${main.name}» за $days дней:');
  final events = await provider.fetchEvents(account, main, range);
  events.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  for (final e in events) {
    stdout.writeln(
        '  ${e.startUtc.toLocal()}  ${e.title}  [${e.myResponse.name}]');
  }
  stdout.writeln('итого событий: ${events.length}');

  if (showAll) {
    var total = 0;
    for (final c in cals) {
      final es = await provider.fetchEvents(account, c, range);
      total += es.length;
      stdout.writeln('  ${c.name}: ${es.length}');
    }
    stdout.writeln('по всем календарям: $total');
  }

  exit(0);
}

String _flag(List<String> args, String name, String def) {
  final i = args.indexOf('--$name');
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : def;
}
