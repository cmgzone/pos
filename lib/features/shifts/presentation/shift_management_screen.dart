import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/stitch_kit.dart';
import '../../../core/utils/error_messages.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/shift_provider.dart';
import '../data/shift_preferences_service.dart';
import '../data/shift_repository.dart';

class ShiftManagementScreen extends ConsumerWidget {
  const ShiftManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(currentShiftAccessProvider);
    final currentShiftAsync = ref.watch(currentShiftProvider);
    final currentSummaryAsync = ref.watch(currentShiftSummaryProvider);
    final movementsAsync = ref.watch(currentShiftMovementsProvider);
    final historyAsync = ref.watch(shiftHistoryProvider);
    final access = accessAsync.valueOrNull;
    final currentShift = currentShiftAsync.valueOrNull;
    final currentSummary = currentSummaryAsync.valueOrNull;
    final requiresManagedShift = ShiftRepository.roleRequiresManagedShift(
      SessionService.currentUserRole,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        automaticallyImplyLeading: false,
        title: Text('Shifts & Cash'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => invalidateShiftProviders(ref),
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: TrainingAnchor(
        id: 'shifts.workspace',
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => invalidateShiftProviders(ref),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            children: [
              Text(
                'Opening, closing, and drawer reconciliation live here.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (access?.autoClosedShift != null) ...[
                SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_send_outlined,
                        color: AppColors.warning,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'A previous-day shift was auto-closed so you can start fresh today.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: AppSpacing.xl),
              _CurrentShiftCard(
                shift: currentShift,
                summary: currentSummary,
                requiresManagedShift: requiresManagedShift,
                loading:
                    accessAsync.isLoading ||
                    currentShiftAsync.isLoading ||
                    (currentShift != null && currentSummaryAsync.isLoading),
                onOpenShift: () => _showOpenShiftDialog(context, ref),
                onCashIn: currentShift == null
                    ? null
                    : () => _showCashMovementDialog(
                        context,
                        ref,
                        shiftId: currentShift['id'] as String,
                        type: 'cash_in',
                      ),
                onCashOut: currentShift == null
                    ? null
                    : () => _showCashMovementDialog(
                        context,
                        ref,
                        shiftId: currentShift['id'] as String,
                        type: 'cash_out',
                      ),
                onCloseShift: currentShift == null || currentSummary == null
                    ? null
                    : () => _showCloseShiftDialog(
                        context,
                        ref,
                        shift: currentShift,
                        summary: currentSummary,
                      ),
              ),
              SizedBox(height: AppSpacing.xl),
              _MovementCard(
                movements: movementsAsync.valueOrNull ?? const [],
                loading: currentShift != null && movementsAsync.isLoading,
              ),
              SizedBox(height: AppSpacing.xl),
              _HistoryCard(
                shifts: historyAsync.valueOrNull ?? const [],
                loading: historyAsync.isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOpenShiftDialog(BuildContext context, WidgetRef ref) async {
    final userId = currentShiftActorId();
    final suggestedOpeningCash =
        await ShiftPreferencesService.getLastOpeningCash(userId);
    if (!context.mounted) {
      return;
    }

    final openingCashController = TextEditingController(
      text: _formatOpeningCashInput(suggestedOpeningCash),
    );
    final noteController = TextEditingController();
    String? errorText;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text('Open Shift'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: openingCashController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Opening cash',
                  prefixText: ShopSettings.currency,
                  helperText: suggestedOpeningCash == null
                      ? null
                      : 'Suggested from your last shift opening.',
                  errorText: errorText,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              TextField(
                controller: noteController,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Opening note',
                  hintText: 'Optional handover or drawer note',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final openingCash = double.tryParse(
                        openingCashController.text.trim(),
                      );
                      if (openingCash == null || openingCash < 0) {
                        setState(
                          () => errorText = 'Enter a valid opening amount',
                        );
                        return;
                      }

                      setState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await ShiftRepository.openShift(
                          userId: userId,
                          cashierName: ShiftRepository.normalizeActorName(
                            SessionService.currentUserName,
                          ),
                          openingCash: openingCash,
                          note: noteController.text,
                        );
                        await ShiftPreferencesService.saveLastOpeningCash(
                          userId,
                          openingCash,
                        );
                        invalidateShiftProviders(ref);
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _showSnackBar(
                            context,
                            'Shift opened successfully.',
                            AppColors.success,
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          setState(() {
                            isSaving = false;
                            errorText = AppErrorMessage.from(
                              error,
                              fallback: AppErrorMessage.saveFailed,
                            );
                          });
                        }
                      }
                    },
              child: isSaving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Open Shift'),
            ),
          ],
        ),
      ),
    );

    openingCashController.dispose();
    noteController.dispose();
  }

  Future<void> _showCashMovementDialog(
    BuildContext context,
    WidgetRef ref, {
    required String shiftId,
    required String type,
  }) async {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    String? errorText;
    var isSaving = false;
    final isCashIn = type == 'cash_in';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text(isCashIn ? 'Record Cash In' : 'Record Cash Out'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: ShopSettings.currency,
                  errorText: errorText,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              TextField(
                controller: reasonController,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Petty cash, float top-up, courier payout...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final amount = double.tryParse(
                        amountController.text.trim(),
                      );
                      if (amount == null || amount <= 0) {
                        setState(
                          () => errorText =
                              'Enter a valid amount greater than zero',
                        );
                        return;
                      }
                      if (reasonController.text.trim().isEmpty) {
                        setState(() => errorText = 'Add a short reason');
                        return;
                      }

                      setState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await ShiftRepository.recordCashMovement(
                          shiftId: shiftId,
                          userId: currentShiftActorId(),
                          type: type,
                          amount: amount,
                          reason: reasonController.text,
                        );
                        invalidateShiftProviders(ref);
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          _showSnackBar(
                            context,
                            isCashIn
                                ? 'Cash in recorded.'
                                : 'Cash out recorded.',
                            AppColors.success,
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          setState(() {
                            isSaving = false;
                            errorText = AppErrorMessage.from(
                              error,
                              fallback: AppErrorMessage.saveFailed,
                            );
                          });
                        }
                      }
                    },
              child: isSaving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isCashIn ? 'Save Cash In' : 'Save Cash Out'),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    reasonController.dispose();
  }

  Future<void> _showCloseShiftDialog(
    BuildContext context,
    WidgetRef ref, {
    required Map<String, dynamic> shift,
    required Map<String, dynamic> summary,
  }) async {
    final countedCashController = TextEditingController(
      text: (summary['expected_cash'] as num? ?? 0).toString(),
    );
    final noteController = TextEditingController(
      text: shift['note'] as String? ?? '',
    );
    String? errorText;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text('Close Shift'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Expected cash: ${_currency(summary['expected_cash'])}',
                style: TextStyle(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              SizedBox(height: AppSpacing.md),
              TextField(
                controller: countedCashController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Counted cash',
                  prefixText: ShopSettings.currency,
                  errorText: errorText,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              TextField(
                controller: noteController,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Closing note',
                  hintText: 'Optional closing note',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final countedCash = double.tryParse(
                        countedCashController.text.trim(),
                      );
                      if (countedCash == null || countedCash < 0) {
                        setState(
                          () => errorText = 'Enter a valid counted amount',
                        );
                        return;
                      }

                      setState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        final closedShift = await ShiftRepository.closeShift(
                          shiftId: shift['id'] as String,
                          closingCashCounted: countedCash,
                          note: noteController.text,
                        );
                        invalidateShiftProviders(ref);
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          final difference =
                              (closedShift['difference'] as num?)?.toDouble() ??
                              0;
                          final label = difference == 0
                              ? 'Shift closed with balanced cash.'
                              : difference > 0
                              ? 'Shift closed. Drawer is over by ${_currency(difference)}.'
                              : 'Shift closed. Drawer is short by ${_currency(difference.abs())}.';
                          _showSnackBar(context, label, AppColors.success);
                        }
                      } catch (error) {
                        if (context.mounted) {
                          setState(() {
                            isSaving = false;
                            errorText = AppErrorMessage.from(
                              error,
                              fallback: AppErrorMessage.saveFailed,
                            );
                          });
                        }
                      }
                    },
              child: isSaving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Close Shift'),
            ),
          ],
        ),
      ),
    );

    countedCashController.dispose();
    noteController.dispose();
  }

  static void _showSnackBar(
    BuildContext context,
    String message,
    Color backgroundColor,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  static String _currency(Object? value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return '${ShopSettings.currency}${amount.toStringAsFixed(2)}';
  }

  static String _formatOpeningCashInput(double? amount) {
    if (amount == null) {
      return '0';
    }
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }
}

class _CurrentShiftCard extends StatelessWidget {
  final Map<String, dynamic>? shift;
  final Map<String, dynamic>? summary;
  final bool requiresManagedShift;
  final bool loading;
  final VoidCallback onOpenShift;
  final VoidCallback? onCashIn;
  final VoidCallback? onCashOut;
  final VoidCallback? onCloseShift;

  const _CurrentShiftCard({
    required this.shift,
    required this.summary,
    required this.requiresManagedShift,
    required this.loading,
    required this.onOpenShift,
    required this.onCashIn,
    required this.onCashOut,
    required this.onCloseShift,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading && shift == null) {
      return _SectionCard(
        title: 'Current Shift',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (shift == null) {
      return _SectionCard(
        title: 'Current Shift',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No open shift for ${ShiftRepository.normalizeActorName(SessionService.currentUserName)}.',
              style: theme.textTheme.bodyMedium,
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              requiresManagedShift
                  ? 'Cash shifts will auto-open on the first cash transaction, or you can open one now.'
                  : 'Shifts are optional for your role. Open one when you want drawer-level cash tracking.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onOpenShift,
              icon: Icon(Icons.play_circle_outline),
              label: Text('Open Shift'),
            ),
          ],
        ),
      );
    }

    final currentShift = shift!;
    final shiftSummary = summary ?? ShiftRepository.emptySummary();
    final openedAt = _formatDateTime(currentShift['opened_at'] as String?);
    final note = currentShift['note'] as String?;
    final paymentBreakdown = (shiftSummary['payment_breakdown'] as Map<String, dynamic>?) ?? {};
    final additionalStats = paymentBreakdown.entries.map((e) {
      final label = e.key.isNotEmpty
          ? '${e.key[0].toUpperCase()}${e.key.substring(1).replaceAll('_', ' ')} sales'
          : 'Other sales';
      return _ShiftStatData(
        label: label,
        value: ShiftManagementScreen._currency(e.value),
      );
    });

    final statItems = [
      _ShiftStatData(label: 'Opened', value: openedAt),
      _ShiftStatData(
        label: 'Opening cash',
        value: ShiftManagementScreen._currency(currentShift['opening_cash']),
      ),
      _ShiftStatData(
        label: 'Expected cash',
        value: ShiftManagementScreen._currency(shiftSummary['expected_cash']),
        accent: AppColors.success,
      ),
      _ShiftStatData(
        label: 'Cash sales',
        value: ShiftManagementScreen._currency(
          shiftSummary['cash_sales_total'],
        ),
      ),
      _ShiftStatData(
        label: 'Cash refunds',
        value: ShiftManagementScreen._currency(
          shiftSummary['cash_refunds_total'],
        ),
        accent: AppColors.error,
      ),
      if (shiftSummary['kopesha_sales_total'] != null &&
          (shiftSummary['kopesha_sales_total'] as num) > 0)
        _ShiftStatData(
          label: 'Kopesha sales',
          value: ShiftManagementScreen._currency(
              shiftSummary['kopesha_sales_total']),
        ),
      ...additionalStats,
      _ShiftStatData(
        label: 'Cash in',
        value: ShiftManagementScreen._currency(shiftSummary['cash_in_total']),
      ),
      _ShiftStatData(
        label: 'Cash out',
        value: ShiftManagementScreen._currency(shiftSummary['cash_out_total']),
      ),
      _ShiftStatData(
        label: 'Transactions',
        value: '${(shiftSummary['sale_count'] as num? ?? 0).toInt()} sales',
      ),
    ];
    final actionButtons = <Widget>[
      OutlinedButton.icon(
        onPressed: onCashIn,
        icon: Icon(Icons.add_card_outlined),
        label: Text('Cash In'),
      ),
      OutlinedButton.icon(
        onPressed: onCashOut,
        icon: Icon(Icons.money_off_csred_outlined),
        label: Text('Cash Out'),
      ),
      FilledButton.icon(
        onPressed: onCloseShift,
        icon: Icon(Icons.lock_clock_outlined),
        label: Text('Close Shift'),
      ),
    ];

    return _SectionCard(
      title: 'Current Shift',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 430
                  ? 2
                  : constraints.maxWidth < 760
                  ? 3
                  : 4;
              final ratio = constraints.maxWidth < 430 ? 1.45 : 1.7;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: statItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: ratio,
                ),
                itemBuilder: (context, index) {
                  final item = statItems[index];
                  return _StatChip(
                    label: item.label,
                    value: item.value,
                    accent: item.accent,
                  );
                },
              );
            },
          ),
          if (note != null && note.trim().isNotEmpty) ...[
            SizedBox(height: AppSpacing.lg),
            Text(
              note.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 520 ? 2 : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: actionButtons.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.9,
                ),
                itemBuilder: (context, index) => actionButtons[index],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Just now';
    }
    final date = DateTime.tryParse(value);
    if (date == null) {
      return value;
    }
    return DateFormat('MMM d, yyyy  HH:mm').format(date.toLocal());
  }
}

class _MovementCard extends StatelessWidget {
  final List<Map<String, dynamic>> movements;
  final bool loading;

  const _MovementCard({required this.movements, required this.loading});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Cash Movements',
      child: loading
          ? Center(child: CircularProgressIndicator())
          : movements.isEmpty
          ? Text(
              'No cash in or cash out entries yet for this shift.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth < 340
                    ? 1
                    : constraints.maxWidth < 900
                    ? 2
                    : 3;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: movements.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: constraints.maxWidth < 900 ? 1.32 : 1.55,
                  ),
                  itemBuilder: (context, index) =>
                      _MovementTile(movement: movements[index]),
                );
              },
            ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final List<Map<String, dynamic>> shifts;
  final bool loading;

  const _HistoryCard({required this.shifts, required this.loading});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Recent Shifts',
      child: loading
          ? Center(child: CircularProgressIndicator())
          : shifts.isEmpty
          ? Text(
              'No shifts recorded yet.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth < 340
                    ? 1
                    : constraints.maxWidth < 900
                    ? 2
                    : 3;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: shifts.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: constraints.maxWidth < 900 ? 1.18 : 1.4,
                  ),
                  itemBuilder: (context, index) =>
                      _HistoryTile(shift: shifts[index]),
                );
              },
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _StatChip({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primaryLight;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

class _ShiftStatData {
  final String label;
  final String value;
  final Color? accent;

  const _ShiftStatData({required this.label, required this.value, this.accent});
}

class _MovementTile extends StatelessWidget {
  final Map<String, dynamic> movement;

  const _MovementTile({required this.movement});

  @override
  Widget build(BuildContext context) {
    final isCashIn = (movement['type'] as String? ?? '') == 'cash_in';
    final tone = isCashIn ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCashIn
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: tone,
              ),
              Spacer(),
              Text(
                ShiftManagementScreen._currency(movement['amount']),
                style: TextStyle(fontWeight: FontWeight.w700, color: tone, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            movement['reason'] as String? ?? 'Cash movement',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            _CurrentShiftCard._formatDateTime(
              movement['created_at'] as String?,
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> shift;

  const _HistoryTile({required this.shift});

  @override
  Widget build(BuildContext context) {
    final isOpen = (shift['status'] as String? ?? '') == 'open';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isOpen ? AppColors.success : Theme.of(context).colorScheme.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  shift['cashier_name'] as String? ?? 'Unknown Cashier',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            ShiftManagementScreen._currency(shift['expected_cash']),
            style: TextStyle(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            (shift['status'] as String? ?? 'open').toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          Spacer(),
          Text(
            'Opened ${_CurrentShiftCard._formatDateTime(shift['opened_at'] as String?)}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if ((shift['closed_at'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Closed ${_CurrentShiftCard._formatDateTime(shift['closed_at'] as String?)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
