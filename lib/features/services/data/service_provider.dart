import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'service_repository.dart';

final serviceSearchProvider = StateProvider<String>((ref) => '');
final serviceOrderFilterProvider = StateProvider<String>((ref) => 'active');

final servicesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final query = ref.watch(serviceSearchProvider);
  return ServiceRepository.getServices(query: query);
});

final activeServicesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ServiceRepository.getServices(activeOnly: true);
});

final serviceFieldsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      serviceId,
    ) async {
      return ServiceRepository.getFieldsForService(serviceId);
    });

final serviceOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final filter = ref.watch(serviceOrderFilterProvider);
  return ServiceRepository.getOrders(filter: filter);
});

/// Used by ServicePosPanel to reactively watch today's queue.
/// Invalidated after new orders are created or statuses are advanced.
final serviceTodayOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) {
  return ServiceRepository.getOrders(filter: 'today');
});

final serviceStatsProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ServiceRepository.getServiceStats();
});

final serviceSalesDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final serviceSalesByDateProvider = FutureProvider<Map<String, dynamic>>((ref) {
  final date = ref.watch(serviceSalesDateProvider);
  final key =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return ServiceRepository.getServiceSalesByDate(key);
});
