import 'package:flutter/material.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../products/data/product_repository.dart';
import '../data/promotion_repository.dart';

class PromotionScreen extends StatefulWidget {
  const PromotionScreen({super.key});

  @override
  State<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends State<PromotionScreen> {
  List<Map<String, dynamic>> _promotions = const [];
  Map<String, List<Map<String, dynamic>>> _rules = const {};
  List<Map<String, dynamic>> _products = const [];
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
      final promotions = await PromotionRepository.getAll();
      final rules = <String, List<Map<String, dynamic>>>{};
      for (final promotion in promotions) {
        final id = promotion['id'] as String;
        rules[id] = await PromotionRepository.getRules(id);
      }
      final products = await ProductRepository.getAll();
      if (!mounted) return;
      setState(() {
        _promotions = promotions;
        _rules = rules;
        _products = products;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppErrorMessage.from(
          error,
          fallback: AppErrorMessage.loadFailed,
        );
        _loading = false;
      });
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? promotion}) async {
    final rules = promotion == null
        ? const <Map<String, dynamic>>[]
        : _rules[promotion['id'] as String] ?? const [];
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PromotionEditorDialog(
        promotion: promotion,
        rules: rules,
        products: _products,
      ),
    );
    if (saved == true) {
      await _loadData();
    }
  }

  Future<void> _deletePromotion(Map<String, dynamic> promotion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Promotion?'),
        content: Text('Delete "${promotion['name']}" from active rules?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PromotionRepository.delete(promotion['id'] as String);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showError(AppErrorMessage.from(error, fallback: 'Could not delete.'));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotions'),
        actions: [
          IconButton(
            onPressed: _loadData,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Promotion'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _ErrorView(message: _errorMessage!, onRetry: _loadData)
            : _buildList(),
      ),
    );
  }

  Widget _buildList() {
    if (_promotions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.local_offer_outlined, size: 48),
          SizedBox(height: 12),
          Center(
            child: Text('No promotions yet.', textAlign: TextAlign.center),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _promotions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final promotion = _promotions[index];
        final rules = _rules[promotion['id'] as String] ?? const [];
        final active = ((promotion['is_active'] as num?)?.toInt() ?? 0) != 0;
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            leading: CircleAvatar(
              backgroundColor: active
                  ? AppColors.success.withValues(alpha: 0.14)
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
              child: Icon(
                _promotionIcon(promotion['promotion_type']?.toString()),
                color: active ? AppColors.success : null,
              ),
            ),
            title: Text(
              promotion['name']?.toString() ?? 'Promotion',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  _promotionTypeLabel(promotion['promotion_type']?.toString()),
                  _discountLabel(promotion),
                  if (rules.isNotEmpty)
                    '${rules.length} rule${rules.length == 1 ? '' : 's'}',
                  active ? 'active' : 'off',
                ].where((value) => value.trim().isNotEmpty).join(' - '),
              ),
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => _openEditor(promotion: promotion),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _deletePromotion(promotion),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PromotionEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? promotion;
  final List<Map<String, dynamic>> rules;
  final List<Map<String, dynamic>> products;

  const _PromotionEditorDialog({
    this.promotion,
    required this.rules,
    required this.products,
  });

  @override
  State<_PromotionEditorDialog> createState() => _PromotionEditorDialogState();
}

class _PromotionEditorDialogState extends State<_PromotionEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _discountController;
  late final TextEditingController _minSubtotalController;
  late final TextEditingController _buyQtyController;
  late final TextEditingController _freeQtyController;
  late final TextEditingController _priorityController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;
  late String _promotionType;
  late String _discountType;
  late bool _isActive;
  String? _productId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final promotion = widget.promotion;
    final rule = widget.rules.isEmpty ? null : widget.rules.first;
    _promotionType = promotion?['promotion_type']?.toString() ?? 'amount_off';
    _discountType =
        promotion?['discount_type']?.toString() ??
        (_promotionType == 'percent_off' ? 'percent' : 'amount');
    _isActive = ((promotion?['is_active'] as num?)?.toInt() ?? 1) != 0;
    _productId = rule?['product_id']?.toString();
    if ((_productId ?? '').isEmpty) _productId = null;
    _nameController = TextEditingController(
      text: promotion?['name']?.toString() ?? '',
    );
    _descriptionController = TextEditingController(
      text: promotion?['description']?.toString() ?? '',
    );
    _discountController = TextEditingController(
      text: ((promotion?['discount_value'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(2),
    );
    _minSubtotalController = TextEditingController(
      text: ((rule?['min_subtotal'] as num?)?.toDouble() ?? 0).toStringAsFixed(
        2,
      ),
    );
    _buyQtyController = TextEditingController(
      text: ((rule?['min_quantity'] as num?)?.toDouble() ?? 0).toStringAsFixed(
        0,
      ),
    );
    _freeQtyController = TextEditingController(
      text: ((rule?['free_quantity'] as num?)?.toDouble() ?? 0).toStringAsFixed(
        0,
      ),
    );
    _priorityController = TextEditingController(
      text: ((promotion?['priority'] as num?)?.toInt() ?? 0).toString(),
    );
    _startTimeController = TextEditingController(
      text: promotion?['start_time']?.toString() ?? '',
    );
    _endTimeController = TextEditingController(
      text: promotion?['end_time']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _discountController.dispose();
    _minSubtotalController.dispose();
    _buyQtyController.dispose();
    _freeQtyController.dispose();
    _priorityController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Promotion name is required.');
      return;
    }
    if ((_promotionType == 'buy_x_get_y' || _promotionType == 'bundle') &&
        (_productId == null || _productId!.isEmpty)) {
      _showError('Choose a product for this promotion.');
      return;
    }
    final discountValue = double.tryParse(_discountController.text.trim()) ?? 0;
    final buyQty = double.tryParse(_buyQtyController.text.trim()) ?? 0;
    final freeQty = double.tryParse(_freeQtyController.text.trim()) ?? 0;
    if (_promotionType == 'buy_x_get_y' && (buyQty <= 0 || freeQty <= 0)) {
      _showError('Buy X Get Y needs both buy quantity and free quantity.');
      return;
    }
    setState(() => _saving = true);
    try {
      final rules = [
        PromotionRuleDraft(
          ruleType: _promotionType,
          productId: _productId,
          minQuantity: buyQty,
          freeQuantity: freeQty,
          bundleQuantity: buyQty,
          minSubtotal: double.tryParse(_minSubtotalController.text.trim()) ?? 0,
        ),
      ];
      final id = widget.promotion?['id'] as String?;
      if (id == null) {
        await PromotionRepository.create(
          name: name,
          description: _descriptionController.text,
          promotionType: _promotionType,
          discountType: _effectiveDiscountType,
          discountValue: _promotionType == 'buy_x_get_y' ? 0 : discountValue,
          priority: int.tryParse(_priorityController.text.trim()) ?? 0,
          startTime: _promotionType == 'happy_hour'
              ? _startTimeController.text
              : null,
          endTime: _promotionType == 'happy_hour'
              ? _endTimeController.text
              : null,
          isActive: _isActive,
          rules: rules,
        );
      } else {
        await PromotionRepository.update(
          id: id,
          name: name,
          description: _descriptionController.text,
          promotionType: _promotionType,
          discountType: _effectiveDiscountType,
          discountValue: _promotionType == 'buy_x_get_y' ? 0 : discountValue,
          priority: int.tryParse(_priorityController.text.trim()) ?? 0,
          startTime: _promotionType == 'happy_hour'
              ? _startTimeController.text
              : null,
          endTime: _promotionType == 'happy_hour'
              ? _endTimeController.text
              : null,
          isActive: _isActive,
          rules: rules,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(
        AppErrorMessage.from(error, fallback: AppErrorMessage.saveFailed),
      );
    }
  }

  String get _effectiveDiscountType {
    if (_promotionType == 'percent_off') return 'percent';
    if (_promotionType == 'amount_off') return 'amount';
    return _discountType;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDiscount = _promotionType != 'buy_x_get_y';
    final showProduct =
        _promotionType == 'buy_x_get_y' || _promotionType == 'bundle';
    final showBuyGet = _promotionType == 'buy_x_get_y';
    final showTime = _promotionType == 'happy_hour';
    return AlertDialog(
      title: Text(
        widget.promotion == null ? 'New Promotion' : 'Edit Promotion',
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width < 800
              ? MediaQuery.of(context).size.width - 32
              : 520,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Promotion name',
                  prefixIcon: Icon(Icons.local_offer_outlined),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _promotionType,
                decoration: const InputDecoration(labelText: 'Promotion type'),
                items: const [
                  DropdownMenuItem(
                    value: 'amount_off',
                    child: Text('Amount off'),
                  ),
                  DropdownMenuItem(
                    value: 'percent_off',
                    child: Text('Percent off'),
                  ),
                  DropdownMenuItem(
                    value: 'buy_x_get_y',
                    child: Text('Buy X Get Y'),
                  ),
                  DropdownMenuItem(value: 'bundle', child: Text('Bundle')),
                  DropdownMenuItem(
                    value: 'happy_hour',
                    child: Text('Happy hour'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _promotionType = value ?? _promotionType;
                        if (_promotionType == 'percent_off') {
                          _discountType = 'percent';
                        } else if (_promotionType == 'amount_off') {
                          _discountType = 'amount';
                        }
                      }),
              ),
              const SizedBox(height: 12),
              if (showDiscount) ...[
                if (_promotionType == 'bundle' ||
                    _promotionType == 'happy_hour')
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'amount', label: Text('Amount')),
                      ButtonSegment(value: 'percent', label: Text('Percent')),
                    ],
                    selected: {_discountType},
                    onSelectionChanged: _saving
                        ? null
                        : (values) =>
                              setState(() => _discountType = values.first),
                  ),
                if (_promotionType == 'bundle' ||
                    _promotionType == 'happy_hour')
                  const SizedBox(height: 12),
                TextField(
                  controller: _discountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _effectiveDiscountType == 'percent'
                        ? 'Discount percent'
                        : 'Discount amount',
                    prefixText: _effectiveDiscountType == 'amount'
                        ? ShopSettings.currency
                        : null,
                    suffixText: _effectiveDiscountType == 'percent'
                        ? '%'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (showProduct) ...[
                DropdownButtonFormField<String>(
                  initialValue: _productId,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: widget.products
                      .map(
                        (product) => DropdownMenuItem<String>(
                          value: product['id'] as String,
                          child: Text(
                            product['name']?.toString() ?? 'Product',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _productId = value),
                ),
                const SizedBox(height: 12),
              ],
              if (showBuyGet) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _buyQtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Buy quantity',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _freeQtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Free quantity',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _minSubtotalController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Minimum cart subtotal',
                  prefixText: ShopSettings.currency,
                ),
              ),
              const SizedBox(height: 12),
              if (showTime) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startTimeController,
                        decoration: const InputDecoration(
                          labelText: 'Start time',
                          hintText: '09:00',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _endTimeController,
                        decoration: const InputDecoration(
                          labelText: 'End time',
                          hintText: '17:00',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priorityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Priority'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: _isActive,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _isActive = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Internal note',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
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
          child: Column(
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

IconData _promotionIcon(String? type) {
  switch (type) {
    case 'percent_off':
      return Icons.percent_outlined;
    case 'buy_x_get_y':
      return Icons.redeem_outlined;
    case 'bundle':
      return Icons.inventory_2_outlined;
    case 'happy_hour':
      return Icons.schedule_outlined;
    default:
      return Icons.local_offer_outlined;
  }
}

String _promotionTypeLabel(String? type) {
  switch (type) {
    case 'percent_off':
      return 'Percent off';
    case 'buy_x_get_y':
      return 'Buy X Get Y';
    case 'bundle':
      return 'Bundle';
    case 'happy_hour':
      return 'Happy hour';
    default:
      return 'Amount off';
  }
}

String _discountLabel(Map<String, dynamic> promotion) {
  final type = promotion['promotion_type']?.toString() ?? '';
  if (type == 'buy_x_get_y') return '';
  final discountType = promotion['discount_type']?.toString() ?? 'amount';
  final value = (promotion['discount_value'] as num?)?.toDouble() ?? 0;
  if (discountType == 'percent') {
    return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}%';
  }
  return '${ShopSettings.currency}${value.toStringAsFixed(2)}';
}
