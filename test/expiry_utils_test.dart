import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/expiry_utils.dart';

void main() {
  test('classifies expired and expiring batches relative to today', () {
    final reference = DateTime(2026, 4, 25);

    expect(
      ExpiryUtils.statusFor('2026-04-24', referenceDate: reference),
      ExpiryStatus.expired,
    );
    expect(
      ExpiryUtils.statusFor('2026-04-25', referenceDate: reference),
      ExpiryStatus.expiringSoon,
    );
    expect(
      ExpiryUtils.statusFor('2026-05-10', referenceDate: reference),
      ExpiryStatus.expiringSoon,
    );
    expect(
      ExpiryUtils.statusFor('2026-07-01', referenceDate: reference),
      ExpiryStatus.ok,
    );
  });

  test('normalizes storage dates and status labels', () {
    final date = DateTime(2026, 6, 1, 14, 30);

    expect(ExpiryUtils.toStorageString(date), '2026-06-01');
    expect(
      ExpiryUtils.statusLabel(
        '2026-04-26',
        referenceDate: DateTime(2026, 4, 25),
      ),
      'Expires tomorrow',
    );
    expect(ExpiryUtils.format('2026-06-01'), '01 Jun 2026');
  });
}
