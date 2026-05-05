import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pos_app/core/theme/app_colors.dart';
import '../data/payment_method_provider.dart';
import '../data/payment_method_repository.dart';

class PaymentMethodsSection extends ConsumerStatefulWidget {
  const PaymentMethodsSection({super.key});

  @override
  ConsumerState<PaymentMethodsSection> createState() =>
      _PaymentMethodsSectionState();
}

class _PaymentMethodsSectionState extends ConsumerState<PaymentMethodsSection> {
  Future<void> _showAddPaymentMethodDialog([
    Map<String, dynamic>? existing,
  ]) async {
    final isEditing = existing != null;
    final nameController = TextEditingController(
      text: isEditing ? existing['name'] : '',
    );
    bool isCashDrawer = isEditing ? (existing['is_cash_drawer'] == 1) : false;
    bool isCredit = isEditing ? (existing['is_credit'] == 1) : false;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit Payment Method' : 'Add Payment Method'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. M-Pesa, Card, Bank Transfer',
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Affects Cash Drawer'),
                  subtitle: const Text(
                    'Check this if this payment method represents physical cash going into the till.',
                  ),
                  value: isCashDrawer,
                  onChanged: (val) => setDialogState(() {
                    isCashDrawer = val;
                    if (val) isCredit = false; // Cash drawer can't be credit
                  }),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Credit Payment (Kopesha)'),
                  subtitle: const Text(
                    'Check this for credit sales that require customer assignment and due dates.',
                  ),
                  value: isCredit,
                  onChanged: (val) => setDialogState(() {
                    isCredit = val;
                    if (val) {
                      isCashDrawer = false; // Credit can't be cash drawer
                    }
                  }),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        if (isEditing) {
                          await PaymentMethodRepository.update(
                            existing['id'],
                            name: nameController.text.trim(),
                            isCashDrawer: isCashDrawer,
                            isCredit: isCredit,
                            isActive: existing['is_active'] == 1,
                            sortOrder: existing['sort_order'],
                          );
                        } else {
                          await PaymentMethodRepository.create(
                            name: nameController.text.trim(),
                            isCashDrawer: isCashDrawer,
                            isCredit: isCredit,
                          );
                        }
                        if (context.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isEditing ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ref.invalidate(paymentMethodsProvider);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> method, bool isActive) async {
    try {
      await PaymentMethodRepository.update(
        method['id'],
        name: method['name'],
        isCashDrawer: method['is_cash_drawer'] == 1,
        isCredit: method['is_credit'] == 1,
        isActive: isActive,
        sortOrder: method['sort_order'],
      );
      ref.invalidate(paymentMethodsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error toggling status: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteMethod(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Payment Method?'),
        content: const Text(
          'Are you sure you want to delete this payment method? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await PaymentMethodRepository.delete(id);
        ref.invalidate(paymentMethodsProvider);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentMethodsAsync = ref.watch(paymentMethodsProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => _showAddPaymentMethodDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Payment Method'),
              ),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(paymentMethodsProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          paymentMethodsAsync.when(
            data: (methods) {
              if (methods.isEmpty) {
                return const Text(
                  'No custom payment methods defined.',
                  style: TextStyle(color: AppColors.textSecondary),
                );
              }
              return Column(
                children: methods.map((method) {
                  final isActive = method['is_active'] == 1;
                  final isCashDrawer = method['is_cash_drawer'] == 1;
                  final isCredit = method['is_credit'] == 1;

                  String subtitle = 'Digital/External payment';
                  if (isCashDrawer) {
                    subtitle = 'Affects cash drawer';
                  } else if (isCredit) {
                    subtitle = 'Credit payment (Kopesha)';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                      color: isActive
                          ? Colors.transparent
                          : AppColors.surfaceHighlight.withValues(alpha: 0.5),
                    ),
                    child: ListTile(
                      title: Text(
                        method['name'],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isActive
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: isActive,
                            onChanged: (val) => _toggleActive(method, val),
                            activeThumbColor: AppColors.primaryLight,
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () =>
                                _showAddPaymentMethodDialog(method),
                            tooltip: 'Edit',
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: AppColors.error,
                            ),
                            onPressed: () => _deleteMethod(method['id']),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Text(
              'Error: $err',
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
