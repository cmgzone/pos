import 'package:flutter/material.dart';

import '../../../core/services/storefront_theme_service.dart';
import '../../../core/utils/error_messages.dart';

class StorefrontDeliverySection extends StatefulWidget {
  final String storefrontType;

  const StorefrontDeliverySection({super.key, this.storefrontType = 'retail'});

  @override
  State<StorefrontDeliverySection> createState() =>
      _StorefrontDeliverySectionState();
}

class _StorefrontDeliverySectionState extends State<StorefrontDeliverySection> {
  StorefrontTheme? _theme;
  bool _pickup = true;
  bool _delivery = true;
  bool _showAddress = true;
  bool _showNote = true;
  bool _showTracking = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await StorefrontThemeService.list(
        branchId: 'main_branch',
        storefrontType: widget.storefrontType,
      );
      final theme =
          result.themes.where((item) => item.isPublished).firstOrNull ??
          result.themes.firstOrNull;
      if (!mounted) return;
      setState(() {
        _theme = theme;
        _pickup = theme?.checkout.fulfillmentMethods.contains('pickup') ?? true;
        _delivery =
            theme?.checkout.fulfillmentMethods.contains('delivery') ?? true;
        _showAddress = theme?.checkout.showDeliveryAddress ?? true;
        _showNote = theme?.checkout.showOrderNote ?? true;
        _showTracking = theme?.checkout.showOrderTracking ?? true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final theme = _theme;
    if (theme == null || (!_pickup && !_delivery) || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = theme.isPublished
          ? await StorefrontThemeService.duplicate(
              theme.id,
              name: '${theme.name} delivery draft',
            )
          : theme;
      final checkout = theme.checkout.toJson();
      checkout.addAll({
        'fulfillmentMethods': [
          if (_pickup) 'pickup',
          if (_delivery) 'delivery',
        ],
        'defaultFulfillmentMethod': _pickup ? 'pickup' : 'delivery',
        'showDeliveryAddress': _delivery && _showAddress,
        'showOrderNote': _showNote,
        'showOrderTracking': _showTracking,
      });
      final updated = await StorefrontThemeService.update(draft.id, {
        'checkout': checkout,
        'source': 'manual',
      });
      if (!mounted) return;
      setState(() => _theme = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery settings saved to a storefront draft.'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          Icons.local_shipping_outlined,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pickup and delivery',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Choose what customers see at checkout. Changes are saved safely as a draft before publishing.',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_theme == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Icon(
                          Icons.web_asset_off_outlined,
                          size: 42,
                          color: colors.primary,
                        ),
                        const SizedBox(height: 10),
                        const Text('Create a website theme first'),
                        const SizedBox(height: 5),
                        Text(
                          'Delivery settings belong to the customer checkout theme.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Fulfilment choices',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _pickup,
                          title: const Text('Customer pickup'),
                          subtitle: const Text(
                            'Customers collect the order from your business.',
                          ),
                          onChanged: (value) =>
                              setState(() => _pickup = value ?? false),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _delivery,
                          title: const Text('Delivery'),
                          subtitle: const Text(
                            'Customers provide a delivery address at checkout.',
                          ),
                          onChanged: (value) =>
                              setState(() => _delivery = value ?? false),
                        ),
                        const Divider(height: 28),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _delivery && _showAddress,
                          title: const Text('Require delivery address'),
                          onChanged: _delivery
                              ? (value) => setState(() => _showAddress = value)
                              : null,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _showNote,
                          title: const Text('Allow order instructions'),
                          onChanged: (value) =>
                              setState(() => _showNote = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _showTracking,
                          title: const Text('Show order tracking'),
                          onChanged: (value) =>
                              setState(() => _showTracking = value),
                        ),
                        if (!_pickup && !_delivery)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Choose at least one fulfilment method.',
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _saving || (!_pickup && !_delivery)
                                ? null
                                : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Save delivery draft'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _message(Object error) => AppErrorMessage.from(
    error,
    fallback: 'Delivery settings could not be loaded. Try again.',
  );
}
