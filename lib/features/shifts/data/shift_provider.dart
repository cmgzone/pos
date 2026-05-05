import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/session_service.dart';
import 'shift_repository.dart';

String currentShiftActorId() {
  return ShiftRepository.normalizeActorUserId(SessionService.currentUserId);
}

final currentShiftAccessProvider = FutureProvider<ShiftAccessResult>((ref) {
  return ShiftRepository.resolveCurrentShift(userId: currentShiftActorId());
});

final currentShiftProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final access = await ref.watch(currentShiftAccessProvider.future);
  return access.currentShift;
});

final currentShiftSummaryProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final shift = await ref.watch(currentShiftProvider.future);
  if (shift == null) {
    return ShiftRepository.emptySummary();
  }

  return ShiftRepository.getShiftSummary(shift['id'] as String);
});

final currentShiftMovementsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      final shift = await ref.watch(currentShiftProvider.future);
      if (shift == null) {
        return const <Map<String, dynamic>>[];
      }

      return ShiftRepository.getCashMovements(shift['id'] as String);
    });

final shiftHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final role = RolePermissions.normalizeRole(SessionService.currentUserRole);
  return ShiftRepository.getRecentShifts(
    userId: role == RolePermissions.cashier ? currentShiftActorId() : null,
  );
});

void invalidateShiftProviders(WidgetRef ref) {
  ref.invalidate(currentShiftAccessProvider);
  ref.invalidate(currentShiftProvider);
  ref.invalidate(currentShiftSummaryProvider);
  ref.invalidate(currentShiftMovementsProvider);
  ref.invalidate(shiftHistoryProvider);
}
