import 'package:flutter/material.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../data/exchange_rate_repository.dart';

class MultiCurrencySection extends StatefulWidget {
  const MultiCurrencySection({super.key});

  @override
  State<MultiCurrencySection> createState() => _MultiCurrencySectionState();
}

class _MultiCurrencySectionState extends State<MultiCurrencySection> {
  late final TextEditingController _rateController;
  late String _quoteCurrency;
  late bool _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _quoteCurrency = ShopSettings.secondaryCurrency;
    _enabled = ShopSettings.dualCurrencyEnabled;
    _rateController = TextEditingController(
      text: ShopSettings.secondaryCurrencyRate > 0
          ? ShopSettings.secondaryCurrencyRate.toString()
          : '',
    );
    _loadActive();
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _loadActive() async {
    final active = await ExchangeRateRepository.getActive();
    if (!mounted || active == null) return;
    setState(() {
      _quoteCurrency =
          active['quote_currency'] as String? ?? ShopSettings.secondaryCurrency;
      _rateController.text = ((active['rate'] as num?)?.toDouble() ?? 0)
          .toString();
      _enabled = (active['is_active'] as num? ?? 0) == 1;
    });
  }

  Future<void> _save() async {
    final rate = double.tryParse(_rateController.text.trim()) ?? 0;
    setState(() => _busy = true);
    try {
      await ExchangeRateRepository.saveActive(
        quoteCurrency: _quoteCurrency,
        rate: rate,
        enabled: _enabled,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Multi-currency settings saved.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = ShopSettings.currency;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
          title: const Text('Show second currency in POS'),
          subtitle: Text('Base currency remains $base for accounting.'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _quoteCurrency,
          decoration: const InputDecoration(
            labelText: 'Secondary currency',
            prefixIcon: Icon(Icons.currency_exchange_rounded),
          ),
          items: ShopSettings.currencyOptions
              .map(
                (option) => DropdownMenuItem(
                  value: option.prefix,
                  child: Text(option.label),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _quoteCurrency = value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _rateController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Rate',
            helperText: '1 $base equals how much $_quoteCurrency',
            prefixIcon: const Icon(Icons.trending_up_rounded),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: const Icon(Icons.point_of_sale_rounded),
            ),
            title: const Text('POS preview'),
            subtitle: Text(
              'Example: $base 1,000 = $_quoteCurrency ${((double.tryParse(_rateController.text) ?? 0) * 1000).toStringAsFixed(2)}',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }
}
