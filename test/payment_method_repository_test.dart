import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/settings/data/payment_method_repository.dart';

void main() {
  group('PaymentMethodRepository provider keys', () {
    test('prefers explicit provider_key over the visible payment name', () {
      expect(
        PaymentMethodRepository.providerKeyFor({
          'name': 'Till 123456',
          'provider_key': 'mpesa',
          'is_cash_drawer': 0,
          'is_credit': 0,
        }),
        PaymentMethodRepository.providerMpesa,
      );
    });

    test('falls back to legacy flags and names for older payment methods', () {
      expect(
        PaymentMethodRepository.providerKeyFor({
          'name': 'Main Till Cash',
          'is_cash_drawer': 1,
          'is_credit': 0,
        }),
        PaymentMethodRepository.providerCash,
      );
      expect(
        PaymentMethodRepository.providerKeyFor({
          'name': 'Customer Kopesha',
          'is_cash_drawer': 0,
          'is_credit': 1,
        }),
        PaymentMethodRepository.providerKopesha,
      );
      expect(
        PaymentMethodRepository.providerKeyFor({
          'name': 'M-Pesa Paybill',
          'is_cash_drawer': 0,
          'is_credit': 0,
        }),
        PaymentMethodRepository.providerMpesa,
      );
    });
  });
}
