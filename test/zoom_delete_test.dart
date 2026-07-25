// deleteConference (удаление внешней видеовстречи при удалении события):
// для не-Zoom и при отсутствии ключей — тихий no-op без сети (Teams/Meet
// уходят вместе с событием, Telemost без delete-API).

import 'package:calenfi/data/providers/conference/conference_provisioner.dart';
import 'package:calenfi/data/secure/credential_source.dart';
import 'package:calenfi/domain/models/conference.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final prov =
      ConferenceProvisioner(credentials: CredentialSource.fromMap(const {}));

  test('null / не-Zoom → no-op без исключения', () async {
    await prov.deleteConference(null);
    await prov.deleteConference(const Conference(
        type: ConferenceType.teams, joinUrl: 'x', meetingId: 'm'));
    await prov.deleteConference(const Conference(
        type: ConferenceType.meet, joinUrl: 'x', meetingId: 'm'));
  });

  test('Zoom без ключей → no-op (не лезет в сеть, не бросает)', () async {
    await prov.deleteConference(const Conference(
        type: ConferenceType.zoom, joinUrl: 'x', meetingId: '123'));
  });
}
