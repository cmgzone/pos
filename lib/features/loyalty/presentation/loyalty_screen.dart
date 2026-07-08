import 'package:flutter/material.dart';
import 'package:pos_app/features/app/app_shell.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../data/loyalty_repository.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

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
      final rules = await LoyaltyRepository.getRules();
      final customers = await LoyaltyRepository.getTopCustomersByPoints();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _topCustomers = customers;
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

  bool get _isLoyaltyActive {
    final rules = _rules;
    if (rules == null) return false;
    final value = rules['is_active'];
    if (value is int) return value != 0;
    if (value is num) return value.toInt() != 0;
    return int.tryParse(value?.toString() ?? '') != 0;
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
        leading: !Navigator.of(context).canPop() &&
                MediaQuery.of(context).size.width <= 800
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
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
      children: [
        _buildStatusCard(),
        const SizedBox(height: 20),
        _buildHowItWorksCard(),
        const SizedBox(height: 20),
        _buildTopCustomersSection(),
      ],
    );
  }

  Widget _buildStatusCard() {
    final isActive = _isLoyaltyActive;
    final rules = _rules;
    final pointsPerCurrency =
        (rules?['points_per_currency'] as num?)?.toDouble() ?? 0;
    final divisor = (rules?['currency_divisor'] as num?)?.toDouble() ?? 100;
    final minRedemption =
        (rules?['min_redemption_points'] as num?)?.toInt() ?? 0;
    final factor =
        (rules?['points_to_currency_factor'] as num?)?.toDouble() ?? 1;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.success.withValues(alpha: 0.12)
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isActive
                        ? Icons.loyalty_rounded
                        : Icons.loyalty_outlined,
                    color: isActive ? AppColors.success : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isActive ? 'Loyalty is Active' : 'Loyalty is Off',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        rules == null
                            ? 'Set up your rewards program to start earning customer points.'
                            : 'Customers earn points on every purchase.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (rules != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              _StatRow(
                label: 'Earn rate',
                value: pointsPerCurrency > 0 && divisor > 0
                    ? '$pointsPerCurrency pts / ${ShopSettings.currency}${divisor.toStringAsFixed(0)} spent'
                    : 'Not set',
              ),
              _StatRow(
                label: 'Redemption',
                value: '${ShopSettings.currency}${factor.toStringAsFixed(2)} per point',
              ),
              _StatRow(
                label: 'Min. to redeem',
                value: '$minRedemption points',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How it works',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _HowItWorksStep(
              icon: Icons.point_of_sale_outlined,
              text: 'Customers earn points automatically when they pay for a sale.',
            ),
            const SizedBox(height: 10),
            _HowItWorksStep(
              icon: Icons.redeem_outlined,
              text: 'Points can be redeemed as a discount at checkout.',
            ),
            const SizedBox(height: 10),
            _HowItWorksStep(
              icon: Icons.sync_outlined,
              text: 'Points sync across all your devices and branches.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCustomersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Top customers by points',
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
                  'No customers have earned points yet. Once loyalty is active, your top point earners will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          ..._topCustomers.map((customer) => _CustomerPointsTile(customer: customer)),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HowItWorksStep({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primaryLight),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
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
        subtitle: phone.isEmpty ? null : Text(phone, maxLines: 1, overflow: TextOverflow.ellipsis),
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
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _pointsPerCurrencyController = TextEditingController(
      text: e != null
          ? ((e['points_per_currency'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)
          : '1',
    );
    _divisorController = TextEditingController(
      text: e != null
          ? ((e['currency_divisor'] as num?)?.toDouble() ?? 100).toStringAsFixed(0)
          : '100',
    );
    _minRedemptionController = TextEditingController(
      text: e != null
          ? ((e['min_redemption_points'] as num?)?.toInt() ?? 0).toString()
          : '100',
    );
    _factorController = TextEditingController(
      text: e != null
          ? ((e['points_to_currency_factor'] as num?)?.toDouble() ?? 1).toStringAsFixed(2)
          : '1.00',
    );
    _isActive = e == null
        ? true
        : ((e['is_active'] is int
                ? e['is_active'] as int
                : int.tryParse(e['is_active']?.toString() ?? '') ?? 0) !=
            0);
  }

  @override
  void dispose() {
    _pointsPerCurrencyController.dispose();
    _divisorController.dispose();
    _minRedemptionController.dispose();
    _factorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pointsPerCurrency =
        double.tryParse(_pointsPerCurrencyController.text.trim()) ?? 0;
    final divisor = double.tryParse(_divisorController.text.trim()) ?? 100;
    final minRedemption =
        int.tryParse(_minRedemptionController.text.trim()) ?? 0;
    final factor = double.tryParse(_factorController.text.trim()) ?? 1;

    if (divisor <= 0) {
      _showError('The spend amount must be greater than zero.');
      return;
    }
    if (factor <= 0) {
      _showError('The redemption value must be greater than zero.');
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
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _showToast('Loyalty settings saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(
        AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
      );
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
      title: Text(widget.existing == null ? 'Set Up Loyalty' : 'Loyalty Settings'),
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
                onChanged: (value) =>
                    setState(() => _isActive = value),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppColors.primaryLight),
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
