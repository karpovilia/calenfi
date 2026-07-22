// PoC: реальный Office 365 через GraphProvider.
// Запуск: dart run calenfi:graph_probe [email] [--days N]

import 'dart:io';

import 'package:calenfi/data/providers/calendar/graph/graph_provider.dart';
import 'package:calenfi/data/providers/calendar/graph/graph_token.dart';
import 'package:calenfi/domain/models/account.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/data/secure/secret_store.dart';
import 'package:calenfi/domain/providers/calendar_provider.dart';

Future<void> main(List<String> args) async {
  final email = args.firstWhere((a) => a.contains('@'), orElse: () => '');
  if (email.isEmpty) {
    stderr.writeln('использование: graph_probe <email> [--days N]');
    exit(2);
  }
  final di = args.indexOf('--days');
  final days = (di >= 0 && di + 1 < args.length) ? int.parse(args[di + 1]) : 10;

  await SecretStore.instance.warmUp();
  final token = GraphToken.loadFor(email);
  if (token == null) {
    stderr.writeln('нет graph-токена для $email в keyring '
        '(сначала: tools/graph_calendar_auth.py $email)');
    exit(1);
  }
  final account = Account(
      id: 'acc-o365', provider: ProviderType.graph,
      displayName: 'O365', email: email);
  final p = GraphProvider(account: account, token: token);

  final auth = await p.authenticate(account.config);
  stdout.writeln('auth: ${auth.success ? "OK" : auth.error}');

  final cals = await p.listCalendars(account);
  stdout.writeln('календарей: ${cals.length}');
  final primary = cals.firstWhere((c) => c.isPrimary, orElse: () => cals.first);

  final now = DateTime.now().toUtc();
  final events = await p.fetchEvents(
      account, primary, DateRange(now, now.add(Duration(days: days))));
  events.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  stdout.writeln('событий из «${primary.name}» за $days дней: ${events.length}');
  for (final e in events) {
    final c = e.conference != null ? '  📹teams' : '';
    stdout.writeln('  ${e.startUtc.toLocal()}  ${e.title}  [${e.myResponse.name}]$c');
  }
  exit(0);
}
