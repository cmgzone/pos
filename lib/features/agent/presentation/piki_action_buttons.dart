import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../app/app_shell.dart';

/// Row of action buttons rendered inside task-complete message cards.
class PikiActionButtons extends StatelessWidget {
  final Map<String, dynamic>? results;
  final ValueChanged<String>? onSendPrompt;

  const PikiActionButtons({super.key, this.results, this.onSendPrompt});

  @override
  Widget build(BuildContext context) {
    final hasRestock = results?.containsKey('restockList') ?? false;
    final hasLowStock = results?.containsKey('analyzeLowStock') ?? false;
    final hasReport =
        results?.containsKey('todaysSummary') ??
        results?.containsKey('salesReport') ??
        false;
    final hasCatalogOrders = results?.containsKey('catalogOrders') ?? false;
    final hasPurchaseCreated =
        results?.containsKey('purchaseDraftConfirm') ?? false;

    final canCreatePurchaseDraft =
        (hasRestock || hasLowStock) && !hasPurchaseCreated;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canCreatePurchaseDraft)
          _ActionChip(
            icon: Icons.local_shipping_outlined,
            label: 'Create Purchase Draft',
            filled: true,
            onTap: () {
              if (onSendPrompt != null) {
                onSendPrompt!('Create a purchase draft for low stock items');
              }
            },
          ),
        if (hasReport)
          _ActionChip(
            icon: Icons.open_in_new_rounded,
            label: 'Open Report',
            onTap: () => AppShell.selectIndex(8), // Reports
          ),
        if (hasCatalogOrders)
          _ActionChip(
            icon: Icons.assignment_outlined,
            label: 'Open Orders',
            onTap: () => AppShell.selectIndex(17),
          ),
        if (hasPurchaseCreated)
          _ActionChip(
            icon: Icons.local_shipping_outlined,
            label: 'Open Purchases',
            filled: true,
            onTap: () => AppShell.selectIndex(3),
          ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      );
    }

    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
