// PoC: Exchange on-prem через EwsProvider (curl --ntlm + SOAP).
// Запуск: dart run calenfi:ews_probe <email> [--days N]
// Пароль/URL/логин берутся из системного keyring (ключи <EMAIL>_EWS_PASSWORD,
// <EMAIL>_EWS_URL, <EMAIL>_EWS_USER) — см. lib/data/secure/secret_store.dart.

import 'dart:io';

import 'package:calenfi/data/providers/calendar/ews/ews_provider.dart';
import 'package:calenfi/data/secure/credential_source.dart';
import 'package:calenfi/data/secure/secret_store.dart';
import 'package:calenfi/domain/models/account.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/domain/providers/calendar_provider.dart';

Future<void> main(List<String> args) async {
  final email = args.firstWhere((a) => a.contains('@'), orElse: () => '');
  if (email.isEmpty) {
    stderr.writeln('использование: ews_probe <email> [--days N]');
    exit(2);
  }
  final di = args.indexOf('--days');
  final days = (di >= 0 && di + 1 < args.length) ? int.parse(args[di + 1]) : 10;

  await SecretStore.instance.warmUp();
  final creds = CredentialSource.load();
  final password = creds.ewsPassword(email);
  if (password == null) {
    stderr.writeln('нет пароля в keyring: ключ '
        '${CredentialSource.ewsPasswordVar(email)}');
    exit(1);
  }
  final account = Account(
      id: 'probe-ews', provider: ProviderType.ews,
      displayName: 'Exchange', email: email);

  final p = EwsProvider(
    account: account,
    password: password,
    user: creds.ewsUser(email),
    ewsUrlOverride: creds.ewsUrl(email),
  );

  final auth = await p.authenticate(account.config);
  stdout.writeln('auth/autodiscover: ${auth.success ? "OK" : auth.error}');

  final cals = await p.listCalendars(account);
  final now = DateTime.now().toUtc();
  final events = await p.fetchEvents(
      account, cals.first, DateRange(now, now.add(Duration(days: days))));
  events.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  stdout.writeln('событий за $days дней: ${events.length}');
  for (final e in events) {
    stdout.writeln('  ${e.startUtc.toLocal()}  ${e.title}  [${e.myResponse.name}]');
  }
  exit(0);
}
