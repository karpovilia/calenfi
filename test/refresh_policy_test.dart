import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/domain/models/refresh_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RefreshPolicy (FR-A10)', () {
    test('frequent → частый опрос (1 мин), не серверный push', () {
      const p = RefreshPolicy(mode: RefreshMode.frequent);
      expect(p.effectiveInterval, const Duration(minutes: 1));
    });

    test('interval → заданный интервал', () {
      const p = RefreshPolicy(
          mode: RefreshMode.interval, interval: Duration(minutes: 30));
      expect(p.effectiveInterval, const Duration(minutes: 30));
    });

    test('manual → нулевой интервал (только вручную/при старте)', () {
      const p = RefreshPolicy(mode: RefreshMode.manual);
      expect(p.effectiveInterval, Duration.zero);
    });
  });
}
