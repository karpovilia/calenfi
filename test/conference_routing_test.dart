// Маршрутизация видеовстречи по ВЫБРАННОЙ УЗ (поле «Видеовстреча»):
// если хост-УЗ совпадает с УЗ календаря и умеет нативно (Graph→Teams,
// Google→Meet) — «ожидающая» нативная (встречу заведёт провайдер календаря),
// иначе — кросс-аккаунт по токену выбранной УЗ.

import 'package:calenfi/data/providers/conference/conference_provisioner.dart';
import 'package:calenfi/data/secure/credential_source.dart';
import 'package:calenfi/domain/models/account.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const graph = Account(
      id: 'acc-o365', provider: ProviderType.graph, displayName: 'O', email: 'me@company.com');
  const google = Account(
      id: 'acc-g', provider: ProviderType.google, displayName: 'G', email: 'me@gmail.com');

  final prov =
      ConferenceProvisioner(credentials: CredentialSource.fromMap(const {}));

  DateTime t(int h) => DateTime.utc(2030, 1, 1, h);

  test('Teams в СВОЁм Graph-календаре → нативная (пустой joinUrl)', () async {
    final c = await prov.resolve(ConferenceType.teams,
        accountId: 'acc-o365',
        target: graph,
        allAccounts: const [graph, google],
        start: t(10), end: t(11), subject: 'X');
    expect(c.type, ConferenceType.teams);
    expect(c.isReady, isFalse, reason: 'нативную заведёт провайдер календаря');
    expect(c.accountId, 'acc-o365');
  });

  test('Meet в СВОЁм Google-календаре → нативная', () async {
    final c = await prov.resolve(ConferenceType.meet,
        accountId: 'acc-g',
        target: google,
        allAccounts: const [graph, google],
        start: t(10), end: t(11), subject: 'X');
    expect(c.isReady, isFalse);
    expect(c.accountId, 'acc-g');
  });

  test('Teams-хост ≠ УЗ календаря → НЕ нативная (пойдёт кросс-аккаунт)',
      () async {
    // target — Google-календарь, хост Teams — Graph-УЗ: нативно нельзя, пойдёт
    // в _teams (там уже сетевой вызов/токен — проверяем, что это НЕ ранний
    // нативный возврат, т.е. бросит из-за отсутствия токена, а не вернёт pending).
    await expectLater(
      prov.resolve(ConferenceType.teams,
          accountId: 'acc-o365',
          target: google, // календарь другой УЗ
          allAccounts: const [graph, google],
          start: t(10), end: t(11), subject: 'X'),
      throwsA(anything),
    );
  });
}
