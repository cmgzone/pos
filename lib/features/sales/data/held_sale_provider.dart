import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'held_sale_repository.dart';

final heldSalesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return HeldSaleRepository.getAll();
});
