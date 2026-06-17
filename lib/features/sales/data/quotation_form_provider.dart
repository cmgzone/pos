import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/shop_settings.dart';
import '../data/quotation_repository.dart';

/// Which POS flow is active. Sale is always the default so the normal retail
/// flow is never changed unless the cashier explicitly switches.
enum PosMode { sale, quotation }

final posModeProvider = StateProvider<PosMode>((ref) => PosMode.sale);

/// The quotation currently being converted into a sale. Set when the cashier
/// chooses "Convert to Sale" and cleared only after the linked sale is paid
/// (and the quotation marked converted) or the checkout is cancelled/fails.
final activeQuotationIdProvider = StateProvider<String?>((ref) => null);

final quotationCustomerProvider = StateProvider<Map<String, dynamic>?>(
  (ref) => null,
);

final quotationExpiryProvider = StateProvider<String?>((ref) => null);

final quotationNotesProvider = StateProvider<String>((ref) => '');

final quotationsListProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  if (!ShopSettings.quotationsEnabled) {
    return [];
  }
  final result = await QuotationRepository.getAll();
  // Refresh whenever local data changes (save/convert/delete).
  ref.watch(_quotationRefreshTriggerProvider);
  return result;
});

/// A counter bumped whenever a quotation mutation happens locally so the list
/// provider rebuilds without waiting for the stream.
final _quotationRefreshTriggerProvider = StateProvider<int>((ref) => 0);

void bumpQuotationsList(WidgetRef ref) {
  ref.read(_quotationRefreshTriggerProvider.notifier).state =
      ref.read(_quotationRefreshTriggerProvider) + 1;
}
