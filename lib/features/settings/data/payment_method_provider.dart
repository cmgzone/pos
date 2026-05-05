import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'payment_method_repository.dart';

final paymentMethodsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return PaymentMethodRepository.getAll();
});

final activePaymentMethodsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return PaymentMethodRepository.getAll(activeOnly: true);
});
