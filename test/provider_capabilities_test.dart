// Фиксирует контракт возможностей провайдеров (FR §6), по которому UI гейтит
// операции: RSVP в CalDAV не поддержан (чипы прячутся), в EWS/Google/Graph —
// поддержан. Раньше caps были «мёртвыми» метаданными и не соблюдались.

import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/domain/providers/provider_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forProvider отдаёт правильные caps', () {
    expect(ProviderCapabilities.forProvider(ProviderType.google).rsvp, isTrue);
    expect(ProviderCapabilities.forProvider(ProviderType.graph).rsvp, isTrue);
    expect(ProviderCapabilities.forProvider(ProviderType.ews).rsvp, isTrue);
    // CalDAV RSVP не реализован — UI должен прятать чипы, иначе тихий провал.
    expect(ProviderCapabilities.forProvider(ProviderType.caldav).rsvp, isFalse);
  });

  test('crud есть у всех подключаемых провайдеров', () {
    for (final p in ProviderType.values) {
      expect(ProviderCapabilities.forProvider(p).crud, isTrue, reason: '$p');
    }
  });
}
