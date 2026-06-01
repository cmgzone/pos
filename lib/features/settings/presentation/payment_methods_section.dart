import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pos_app/core/services/pos_payment_service.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/core/utils/error_messages.dart';
import '../data/payment_method_provider.dart';
import '../data/payment_method_repository.dart';

class PaymentMethodsSection extends ConsumerStatefulWidget {
  const PaymentMethodsSection({super.key});

  @override
  ConsumerState<PaymentMethodsSection> createState() =>
      _PaymentMethodsSectionState();
}

class _PaymentMethodsSectionState extends ConsumerState<PaymentMethodsSection> {
  final _mpesaDisplayNameController = TextEditingController(text: 'M-Pesa');
  final _mpesaShortcodeController = TextEditingController();
  final _mpesaAccountReferenceController = TextEditingController();
  final _mpesaConsumerKeyController = TextEditingController();
  final _mpesaConsumerSecretController = TextEditingController();
  final _mpesaPasskeyController = TextEditingController();

  bool _mpesaActive = false;
  bool _loadingMpesa = true;
  bool _savingMpesa = false;
  String _mpesaTransactionType = 'CustomerPayBillOnline';
  String _mpesaMessage = '';

  @override
  void initState() {
    super.initState();
    _loadMpesaSettings();
  }

  @override
  void dispose() {
    _mpesaDisplayNameController.dispose();
    _mpesaShortcodeController.dispose();
    _mpesaAccountReferenceController.dispose();
    _mpesaConsumerKeyController.dispose();
    _mpesaConsumerSecretController.dispose();
    _mpesaPasskeyController.dispose();
    super.dispose();
  }

  Future<void> _loadMpesaSettings() async {
    setState(() {
      _loadingMpesa = true;
      _mpesaMessage = '';
    });
    try {
      final settings = await PosPaymentService.fetchBusinessMpesaSettings();
      final publicConfig = settings.publicConfig;
      final secretConfig = settings.secretConfig;
      if (!mounted) return;
      setState(() {
        _mpesaActive = settings.isActive;
        _mpesaDisplayNameController.text = settings.displayName;
        _mpesaShortcodeController.text =
            publicConfig['shortcode']?.toString() ?? '';
        _mpesaTransactionType =
            publicConfig['transactionType']?.toString() ??
            'CustomerPayBillOnline';
        _mpesaAccountReferenceController.text =
            publicConfig['accountReference']?.toString() ?? '';
        _mpesaConsumerKeyController.text =
            secretConfig['consumerKey']?.toString() ?? '';
        _mpesaConsumerSecretController.text =
            secretConfig['consumerSecret']?.toString() ?? '';
        _mpesaPasskeyController.text =
            secretConfig['passkey']?.toString() ?? '';
        _loadingMpesa = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMpesa = false;
        _mpesaMessage = AppErrorMessage.withContext(
          error,
          prefix: 'M-Pesa settings unavailable.',
          fallback: AppErrorMessage.loadFailed,
        );
      });
    }
  }

  Future<void> _saveMpesaSettings() async {
    if (_mpesaActive) {
      final missing = <String>[];
      if (_mpesaShortcodeController.text.trim().isEmpty) {
        missing.add('Till or PayBill number');
      }
      if (_mpesaConsumerKeyController.text.trim().isEmpty) {
        missing.add('consumer key');
      }
      if (_mpesaConsumerSecretController.text.trim().isEmpty) {
        missing.add('consumer secret');
      }
      if (_mpesaPasskeyController.text.trim().isEmpty) {
        missing.add('passkey');
      }
      if (missing.isNotEmpty) {
        setState(() {
          _mpesaMessage =
              'Complete M-Pesa settings before enabling: ${missing.join(', ')}.';
        });
        return;
      }
    }

    setState(() {
      _savingMpesa = true;
      _mpesaMessage = '';
    });
    try {
      final settings = await PosPaymentService.saveBusinessMpesaSettings(
        isActive: _mpesaActive,
        displayName: _mpesaDisplayNameController.text,
        shortcode: _mpesaShortcodeController.text,
        transactionType: _mpesaTransactionType,
        accountReference: _mpesaAccountReferenceController.text,
        consumerKey: _mpesaConsumerKeyController.text,
        consumerSecret: _mpesaConsumerSecretController.text,
        passkey: _mpesaPasskeyController.text,
      );
      if (!mounted) return;
      setState(() {
        _mpesaActive = settings.isActive;
        _mpesaConsumerKeyController.text =
            settings.secretConfig['consumerKey']?.toString() ?? '';
        _mpesaConsumerSecretController.text =
            settings.secretConfig['consumerSecret']?.toString() ?? '';
        _mpesaPasskeyController.text =
            settings.secretConfig['passkey']?.toString() ?? '';
        _mpesaMessage = 'M-Pesa collection saved';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _mpesaMessage = AppErrorMessage.withContext(
          error,
          prefix: 'M-Pesa save failed.',
          fallback: AppErrorMessage.saveFailed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingMpesa = false);
      }
    }
  }

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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
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
                              content: Text(
                                AppErrorMessage.from(
                                  e,
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
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
          content: Text(
            AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteMethod(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
            content: Text(
              AppErrorMessage.from(
                e,
                fallback:
                    'Could not delete this payment method. Please try again.',
              ),
            ),
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
        color: AppColors.surface,
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
          _buildMpesaCollectionSettings(),
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
                          ? AppColors.surfaceHighlight.withValues(alpha: 0.25)
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
              AppErrorMessage.from(err, fallback: AppErrorMessage.loadFailed),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMpesaCollectionSettings() {
    if (_loadingMpesa) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'M-Pesa Business Collection',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Switch(
              value: _mpesaActive,
              onChanged: _savingMpesa
                  ? null
                  : (value) => setState(() => _mpesaActive = value),
              activeThumbColor: AppColors.primaryLight,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _mpesaDisplayNameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _mpesaShortcodeController,
                decoration: const InputDecoration(
                  labelText: 'Till or PayBill number',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue: _mpesaTransactionType,
                decoration: const InputDecoration(
                  labelText: 'Transaction type',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'CustomerPayBillOnline',
                    child: Text('PayBill'),
                  ),
                  DropdownMenuItem(
                    value: 'CustomerBuyGoodsOnline',
                    child: Text('Buy Goods'),
                  ),
                ],
                onChanged: _savingMpesa
                    ? null
                    : (value) => setState(
                        () => _mpesaTransactionType =
                            value ?? 'CustomerPayBillOnline',
                      ),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _mpesaAccountReferenceController,
                decoration: const InputDecoration(
                  labelText: 'Account reference',
                ),
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _mpesaConsumerKeyController,
                decoration: const InputDecoration(labelText: 'Consumer key'),
                obscureText: true,
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _mpesaConsumerSecretController,
                decoration: const InputDecoration(labelText: 'Consumer secret'),
                obscureText: true,
              ),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _mpesaPasskeyController,
                decoration: const InputDecoration(labelText: 'Passkey'),
                obscureText: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _savingMpesa ? null : _saveMpesaSettings,
              icon: _savingMpesa
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_savingMpesa ? 'Saving...' : 'Save M-Pesa'),
            ),
            OutlinedButton.icon(
              onPressed: _savingMpesa ? null : _loadMpesaSettings,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reload'),
            ),
            if (_mpesaMessage.isNotEmpty)
              Text(
                _mpesaMessage,
                style: TextStyle(
                  color: _mpesaMessage.contains('saved')
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
