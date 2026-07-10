import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../app/app_shell.dart';
import '../data/product_repository.dart';
import '../data/wastage_repository.dart';

class WastageScreen extends StatefulWidget {
  const WastageScreen({super.key});

  @override
  State<WastageScreen> createState() => _WastageScreenState();
}

class _WastageScreenState extends State<WastageScreen> {
  late Future<List<Map<String, dynamic>>> _logsFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _logsFuture = WastageRepository.getAll();
  }

  void _refresh() => setState(() => _logsFuture = WastageRepository.getAll());

  Future<void> _recordWastage() async {
    final products = await ProductRepository.getAll(
      typeFilter: ProductTypeFilter.simpleOnly,
    );
    if (!mounted) return;
    if (products.isEmpty) {
      _showMessage(
        'Add a tracked product before recording wastage.',
        error: true,
      );
      return;
    }
    Map<String, dynamic> selected = products.first;
    final quantityController = TextEditingController();
    final noteController = TextEditingController();
    var reason = 'wastage';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Wastage'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected['id'] as String,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: products
                      .map(
                        (product) => DropdownMenuItem(
                          value: product['id'] as String,
                          child: Text(product['name'] as String? ?? 'Product'),
                        ),
                      )
                      .toList(),
                  onChanged: (id) => setDialogState(() {
                    selected = products.firstWhere(
                      (product) => product['id'] == id,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Quantity (${UnitUtils.label(selected['stock_unit'] as String?)})',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: const [
                    DropdownMenuItem(value: 'wastage', child: Text('Wastage')),
                    DropdownMenuItem(
                      value: 'spoilage',
                      child: Text('Spoilage'),
                    ),
                    DropdownMenuItem(value: 'damage', child: Text('Damage')),
                    DropdownMenuItem(value: 'expiry', child: Text('Expired')),
                    DropdownMenuItem(
                      value: 'theft',
                      child: Text('Theft / loss'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => reason = value ?? reason),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final quantity = double.tryParse(quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      _showMessage('Enter a valid quantity.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await WastageRepository.record(
        product: selected,
        quantity: quantity,
        reason: reason,
        note: noteController.text,
      );
      _refresh();
      _showMessage('Wastage recorded and stock reduced.');
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
      ),
      title: const Text('Wastage & Spoilage'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton.icon(
            onPressed: _busy ? null : _recordWastage,
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Record'),
          ),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _logsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final logs = snapshot.data ?? const <Map<String, dynamic>>[];
        if (logs.isEmpty) {
          return Center(
            child: FilledButton.icon(
              onPressed: _recordWastage,
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('Record First Wastage'),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: logs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final log = logs[index];
            final quantity = (log['quantity'] as num? ?? 0).toDouble();
            final unit = UnitUtils.normalize(log['unit'] as String?);
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.error.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.remove_shopping_cart_outlined,
                    color: AppColors.error,
                  ),
                ),
                title: Text(log['product_name'] as String? ?? 'Product'),
                subtitle: Text(
                  '${log['reason']?.toString() ?? 'wastage'} · ${log['recorded_at']?.toString().replaceFirst('T', ' ').split('.').first ?? ''}',
                ),
                trailing: Text(
                  '-${UnitUtils.formatWithUnit(quantity, unit)}',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
