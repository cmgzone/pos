import 'package:flutter/material.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../data/loyalty_repository.dart';

class LoyaltyScreen extends StatefulWidget {
  final Future<Map<String, dynamic>?> Function()? loadRules;
  final Future<List<Map<String, dynamic>>> Function()? loadCustomers;

  const LoyaltyScreen({super.key, this.loadRules, this.loadCustomers});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  Map<String, dynamic>? _rules;
  List<Map<String, dynamic>> _topCustomers = const [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final rules =
          await (widget.loadRules?.call() ?? LoyaltyRepository.getRules());
      final customers =
          await (widget.loadCustomers?.call() ??
              LoyaltyRepository.getTopCustomersByPoints());
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _topCustomers = customers
            .where(
              (customer) =>
                  ((customer['loyalty_points'] as num?)?.toDouble() ?? 0) > 0,
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppErrorMessage.from(
          e,
          fallback: AppErrorMessage.loadFailed,
        );
        _loading = false;
      });
    }
  }

  Future<void> _openRulesDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _LoyaltyRulesDialog(existing: _rules),
    );
    if (saved == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty'),
        actions: [
          FilledButton.icon(
            onPressed: _openRulesDialog,
            icon: const Icon(Icons.tune, size: 18),
            label: Text(_rules == null ? 'Set Up' : 'Settings'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _ErrorView(message: _errorMessage!, onRetry: _loadData)
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [_buildTopCustomersSection()],
    );
  }

  Widget _buildTopCustomersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Customers with points',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (_topCustomers.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No customers with points yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          ..._topCustomers.map(
            (customer) => _CustomerPointsTile(customer: customer),
          ),
      ],
    );
  }
}

class _CustomerPointsTile extends StatelessWidget {
  final Map<String, dynamic> customer;

  const _CustomerPointsTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    final name = customer['name'] as String? ?? 'Unknown';
    final phone = customer['phone'] as String? ?? '';
    final points = (customer['loyalty_points'] as num?)?.toInt() ?? 0;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight.withValues(alpha: 0.12),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: AppColors.primaryLight),
          ),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: phone.isEmpty
            ? null
            : Text(phone, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$points pts',
            style: TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoyaltyRulesDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _LoyaltyRulesDialog({this.existing});

  @override
  State<_LoyaltyRulesDialog> createState() => _LoyaltyRulesDialogState();
}

class _LoyaltyRulesDialogState extends State<_LoyaltyRulesDialog> {
  late final TextEditingController _pointsPerCurrencyController;
  late final TextEditingController _divisorController;
  late final TextEditingController _minRedemptionController;
  late final TextEditingController _factorController;
  late final TextEditingController _rewardThresholdController;
  late final TextEditingController _rewardAmountController;
  late final TextEditingController _rewardExpiryDaysController;
  late bool _isActive;
  late bool _giftCardRewardEnabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _pointsPerCurrencyController = TextEditingController(
      text: e != null
          ? ((e['points_per_currency'] as num?)?.toDouble() ?? 0)
                .toStringAsFixed(0)
          : '1',
    );
    _divisorController = TextEditingController(
      text: e != null
          ? ((e['currency_divisor'] as num?)?.toDouble() ?? 100)
                .toStringAsFixed(0)
          : '100',
    );
    _minRedemptionController = TextEditingController(
      text: e != null
          ? ((e['min_redemption_points'] as num?)?.toInt() ?? 0).toString()
          : '100',
    );
    _factorController = TextEditingController(
      text: e != null
          ? ((e['points_to_currency_factor'] as num?)?.toDouble() ?? 1)
                .toStringAsFixed(2)
          : '1.00',
    );
    _rewardThresholdController = TextEditingController(
      text: e != null
          ? ((e['gift_card_reward_points_threshold'] as num?)?.toInt() ?? 0)
                .toString()
          : '1000',
    );
    _rewardAmountController = TextEditingController(
      text: e != null
          ? ((e['gift_card_reward_amount'] as num?)?.toDouble() ?? 0)
                .toStringAsFixed(2)
          : '500.00',
    );
    _rewardExpiryDaysController = TextEditingController(
      text: e != null
          ? ((e['gift_card_reward_expiry_days'] as num?)?.toInt() ?? 0)
                .toString()
          : '0',
    );
    _isActive = e == null
        ? true
        : ((e['is_active'] is int
                  ? e['is_active'] as int
                  : int.tryParse(e['is_active']?.toString() ?? '') ?? 0) !=
              0);
    _giftCardRewardEnabled = e == null
        ? false
        : ((e['gift_card_reward_enabled'] is int
                  ? e['gift_card_reward_enabled'] as int
                  : int.tryParse(
                          e['gift_card_reward_enabled']?.toString() ?? '',
                        ) ??
                        0) !=
              0);
  }

  @override
  void dispose() {
    _pointsPerCurrencyController.dispose();
    _divisorController.dispose();
    _minRedemptionController.dispose();
    _factorController.dispose();
    _rewardThresholdController.dispose();
    _rewardAmountController.dispose();
    _rewardExpiryDaysController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pointsPerCurrency =
        double.tryParse(_pointsPerCurrencyController.text.trim()) ?? 0;
    final divisor = double.tryParse(_divisorController.text.trim()) ?? 100;
    final minRedemption =
        int.tryParse(_minRedemptionController.text.trim()) ?? 0;
    final factor = double.tryParse(_factorController.text.trim()) ?? 1;
    final rewardThreshold =
        int.tryParse(_rewardThresholdController.text.trim()) ?? 0;
    final rewardAmount =
        double.tryParse(_rewardAmountController.text.trim()) ?? 0;
    final rewardExpiryDays =
        int.tryParse(_rewardExpiryDaysController.text.trim()) ?? 0;

    if (divisor <= 0) {
      _showError('The spend amount must be greater than zero.');
      return;
    }
    if (factor <= 0) {
      _showError('The redemption value must be greater than zero.');
      return;
    }
    if (_giftCardRewardEnabled && (rewardThreshold <= 0 || rewardAmount <= 0)) {
      _showError('Set both the gift card point target and reward value.');
      return;
    }
    if (rewardExpiryDays < 0) {
      _showError('Gift card expiry days cannot be negative.');
      return;
    }

    setState(() => _saving = true);
    try {
      await LoyaltyRepository.saveRules(
        pointsPerCurrency: pointsPerCurrency,
        currencyDivisor: divisor,
        minRedemptionPoints: minRedemption,
        pointsToCurrencyFactor: factor,
        isActive: _isActive,
        giftCardRewardEnabled: _giftCardRewardEnabled,
        giftCardRewardPointsThreshold: rewardThreshold,
        giftCardRewardAmount: rewardAmount,
        giftCardRewardExpiryDays: rewardExpiryDays,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _showToast('Loyalty settings saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Set Up Loyalty' : 'Loyalty Settings',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NumberField(
                controller: _pointsPerCurrencyController,
                label: 'Points earned per spend unit',
                hint: 'e.g. 1',
                icon: Icons.stars_outlined,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _divisorController,
                label: 'Spend amount (${ShopSettings.currency})',
                hint: 'e.g. 100',
                icon: Icons.payments_outlined,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _minRedemptionController,
                label: 'Minimum points to redeem',
                hint: 'e.g. 100',
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _factorController,
                label: 'Redemption value per point (${ShopSettings.currency})',
                hint: 'e.g. 1.00',
                icon: Icons.redeem_outlined,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Loyalty program active'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto gift card reward'),
                subtitle: const Text(
                  'Convert points into a customer gift card when the target is reached.',
                ),
                value: _giftCardRewardEnabled,
                onChanged: (value) =>
                    setState(() => _giftCardRewardEnabled = value),
              ),
              if (_giftCardRewardEnabled) ...[
                const SizedBox(height: 8),
                _NumberField(
                  controller: _rewardThresholdController,
                  label: 'Points needed for gift card',
                  hint: 'e.g. 1000',
                  icon: Icons.flag_outlined,
                ),
                const SizedBox(height: 12),
                _NumberField(
                  controller: _rewardAmountController,
                  label: 'Gift card value (${ShopSettings.currency})',
                  hint: 'e.g. 500',
                  icon: Icons.card_giftcard_outlined,
                ),
                const SizedBox(height: 12),
                _NumberField(
                  controller: _rewardExpiryDaysController,
                  label: 'Gift card expiry days',
                  hint: '0 means no expiry',
                  icon: Icons.event_outlined,
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.primaryLight,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Example: a ${ShopSettings.currency}${_divisorController.text.trim().isEmpty ? "100" : _divisorController.text.trim()} sale earns ${_pointsPerCurrencyController.text.trim().isEmpty ? "1" : _pointsPerCurrencyController.text.trim()} point${(int.tryParse(_pointsPerCurrencyController.text.trim()) ?? 1) == 1 ? "" : "s"}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  const _NumberField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
