import 'package:flutter/material.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';

class ShiftAutoOpenDialogResult {
  final double openingCash;
  final String? note;

  const ShiftAutoOpenDialogResult({
    required this.openingCash,
    required this.note,
  });
}

Future<ShiftAutoOpenDialogResult?> showShiftAutoOpenDialog(
  BuildContext context, {
  required String transactionLabel,
  double? suggestedOpeningCash,
}) async {
  final openingCashController = TextEditingController(
    text: _formatOpeningCashInput(suggestedOpeningCash),
  );
  final noteController = TextEditingController();
  String? errorText;

  final result = await showDialog<ShiftAutoOpenDialogResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Start Cash Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Before this $transactionLabel, set the opening cash for this drawer. Leave it at 0 for a quick start.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (suggestedOpeningCash != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Suggested from your last shift opening.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: openingCashController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Opening cash',
                prefixText: ShopSettings.currency,
                errorText: errorText,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Opening note',
                hintText: 'Optional float or handover note',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(
              ctx,
              const ShiftAutoOpenDialogResult(openingCash: 0, note: null),
            ),
            child: const Text('Quick 0 Open'),
          ),
          FilledButton(
            onPressed: () {
              final openingCash = double.tryParse(
                openingCashController.text.trim(),
              );
              if (openingCash == null || openingCash < 0) {
                setState(() => errorText = 'Enter a valid opening amount');
                return;
              }

              final rawNote = noteController.text.trim();
              Navigator.pop(
                ctx,
                ShiftAutoOpenDialogResult(
                  openingCash: openingCash,
                  note: rawNote.isEmpty ? null : rawNote,
                ),
              );
            },
            child: const Text('Open Shift'),
          ),
        ],
      ),
    ),
  );

  openingCashController.dispose();
  noteController.dispose();
  return result;
}

String _formatOpeningCashInput(double? amount) {
  if (amount == null) {
    return '0';
  }
  return amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
}
