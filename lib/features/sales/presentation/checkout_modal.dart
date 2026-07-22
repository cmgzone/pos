import 'package:flutter/material.dart';

/// A premium, production-ready POS checkout modal for Piki POS.
///
/// Design language: a flat, minimal, Square/Toast/Shopify-POS-inspired
/// checkout surface. Soft shadows only, no gradients, generous whitespace,
/// large 18–22px radii, and a premium orange (#E86A33) accent.
///
/// The cashier completes a sale in under 3 seconds: the amount is the visual
/// focus, and selecting a payment method takes a single tap.
class CheckoutModal extends StatefulWidget {
  final String currency;
  final double total;
  final double subtotal;
  final double tax;
  final double taxRate;
  final bool mpesaConfigured;
  final Map<String, dynamic>? selectedCustomer;

  const CheckoutModal({
    super.key,
    this.currency = 'KSh',
    this.total = 2160.00,
    this.subtotal = 2000.00,
    this.tax = 160.00,
    this.taxRate = 8,
    this.mpesaConfigured = true,
    this.selectedCustomer,
  });

  /// Shows the checkout modal over a dimmed, blurred backdrop.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    String currency = 'KSh',
    double total = 2160.00,
    double subtotal = 2000.00,
    double tax = 160.00,
    double taxRate = 8,
    bool mpesaConfigured = true,
    Map<String, dynamic>? selectedCustomer,
  }) {
    return showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss checkout',
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (pageContext, animation, secondaryAnimation) => CheckoutModal(
        currency: currency,
        total: total,
        subtotal: subtotal,
        tax: tax,
        taxRate: taxRate,
        mpesaConfigured: mpesaConfigured,
        selectedCustomer: selectedCustomer,
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CheckoutModal> createState() => _CheckoutModalState();
}

String _format(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final decimals = parts.length > 1 ? '.${parts[1]}' : '';
  final negative = intPart.startsWith('-');
  final digits = negative ? intPart.substring(1) : intPart;
  final grouped = digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '${negative ? '-' : ''}$grouped$decimals';
}

String _formatRate(double rate) =>
    rate == rate.roundToDouble() ? rate.round().toString() : rate.toString();

class _CheckoutModalState extends State<CheckoutModal> {
  static const _bg = Color(0xFFF8F8F8);
  static const _border = Color(0xFFECECEC);

  int _method = 0; // 0 = M-Pesa, 1 = Cash

  final Map<String, dynamic> _defaultCustomer = const {
    'name': 'Charles',
    'phone': '0707041808',
    'balance': 0.00,
  };

  late Map<String, dynamic>? _customer;

  @override
  void initState() {
    super.initState();
    _customer = widget.selectedCustomer ?? _defaultCustomer;
  }

  void _pay() {
    Navigator.of(context).pop({
      'method': _method == 0 ? 'mpesa' : 'cash',
      'total': widget.total,
      'customer': _customer,
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 560;
    final width = compact ? media.size.width - 24 : 460.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: compact ? 12 : 28,
      ),
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A0B1020),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(onClose: () => Navigator.of(context).pop()),
                      const SizedBox(height: 18),
                      _TotalCard(
                        currency: widget.currency,
                        total: widget.total,
                      ),
                      const SizedBox(height: 22),
                      _SectionTitle(title: 'Choose Payment Method'),
                      const SizedBox(height: 12),
                      _PaymentMethods(
                        selected: _method,
                        onSelect: (v) => setState(() => _method = v),
                      ),
                      if (!widget.mpesaConfigured) ...[
                        const SizedBox(height: 12),
                        _MpesaWarning(onConfigure: () {}),
                      ],
                      const SizedBox(height: 22),
                      _CustomerSection(
                        customer: _customer,
                        onAdd: () => setState(() => _customer = _defaultCustomer),
                        onChange: () => setState(() => _customer = null),
                      ),
                      const SizedBox(height: 18),
                      _SummaryCard(
                        currency: widget.currency,
                        subtotal: widget.subtotal,
                        tax: widget.tax,
                        taxRate: widget.taxRate,
                        total: widget.total,
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),
            _ActionBar(
              currency: widget.currency,
              total: widget.total,
              method: _method,
              onCancel: () => Navigator.of(context).pop(),
              onPay: _pay,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFCEEE6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.shopping_cart_outlined,
            color: Color(0xFFE86A33),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Checkout',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B1B1F),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Complete this sale',
                style: TextStyle(fontSize: 13, color: Color(0xFF8A8A93)),
              ),
            ],
          ),
        ),
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(0xFFECECEC)),
              ),
              child: const Icon(
                Icons.close,
                size: 18,
                color: Color(0xFF6B6B73),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String currency;
  final double total;
  const _TotalCard({required this.currency, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(0xFFECECEC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080B1020),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'TOTAL TO PAY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Color(0xFF8A8A93),
            ),
          ),
          const SizedBox(height: 10),
          Text(
                              '$currency ${_format(total)}',
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B1B1F),
              letterSpacing: -1.2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE9F6EF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 15, color: Color(0xFF2E9E6B)),
                SizedBox(width: 6),
                Text(
                  'Includes VAT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E9E6B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1B1B1F),
        letterSpacing: -0.2,
      ),
    );
  }
}

class _PaymentMethods extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _PaymentMethods({required this.selected, required this.onSelect});

  static const _items = [
    _PayItem(icon: Icons.phone_android_outlined, title: 'M-Pesa', subtitle: 'Safaricom STK Push'),
    _PayItem(icon: Icons.payments_outlined, title: 'Cash', subtitle: 'Receive cash payment'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_items.length, (i) {
        final item = _items[i];
        final active = selected == i;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
            child: _PaymentCard(
              item: item,
              active: active,
              onTap: () => onSelect(i),
            ),
          ),
        );
      }),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final _PayItem item;
  final bool active;
  final VoidCallback onTap;
  const _PaymentCard({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFE86A33) : const Color(0xFF6B6B73);
    final bg = active ? const Color(0xFFFCEEE6) : Colors.white;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: const Color(0xFFE86A33).withValues(alpha: 0.08),
        highlightColor: const Color(0xFFE86A33).withValues(alpha: 0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? const Color(0xFFE86A33) : const Color(0xFFECECEC),
              width: active ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: active
                    ? const Color(0xFFE86A33).withValues(alpha: 0.16)
                    : const Color(0x060B1020),
                blurRadius: active ? 14 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFE86A33).withValues(alpha: 0.16)
                          : const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(item.icon, size: 19, color: color),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? const Color(0xFFE86A33)
                          : const Color(0xFF1B1B1F),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A8A93),
                    ),
                  ),
                ],
              ),
              if (active)
                Positioned(
                  top: 0,
                  right: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE86A33),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MpesaWarning extends StatelessWidget {
  final VoidCallback onConfigure;
  const _MpesaWarning({required this.onConfigure});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF4E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2D9A8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB57A1E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Business M-Pesa not configured',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A5A12),
              ),
            ),
          ),
          TextButton(
            onPressed: onConfigure,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB57A1E),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Configure now →',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerSection extends StatelessWidget {
  final Map<String, dynamic>? customer;
  final VoidCallback onAdd;
  final VoidCallback onChange;
  const _CustomerSection({
    required this.customer,
    required this.onAdd,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Customer (Optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B1B1F),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE86A33),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '+ Add Customer',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Color(0xFFECECEC)),
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search customer by name, phone or email',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB5B5BC)),
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: Color(0xFFB5B5BC),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
            ),
          ),
        ),
        if (customer != null) ...[
          const SizedBox(height: 12),
          _SelectedCustomerCard(customer: customer!, onChange: onChange),
        ],
      ],
    );
  }
}

class _SelectedCustomerCard extends StatelessWidget {
  final Map<String, dynamic> customer;
  final VoidCallback onChange;
  const _SelectedCustomerCard({
    required this.customer,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final name = customer['name']?.toString() ?? 'Customer';
    final phone = customer['phone']?.toString() ?? '';
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0.0;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFFECECEC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x050B1020),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFCEEE6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE86A33),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B1B1F),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A8A93)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Balance',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A8A93),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'KSh ${_format(balance)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B1B1F),
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: onChange,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color(0xFFECECEC)),
                  ),
                  child: const Text(
                    'Change',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B6B73),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String currency;
  final double subtotal;
  final double tax;
  final double taxRate;
  final double total;
  const _SummaryCard({
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.taxRate,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFFECECEC)),
      ),
      child: Column(
        children: [
          _Row(
            label: 'Subtotal',
            value: '$currency ${_format(subtotal)}',
          ),
          const SizedBox(height: 8),
          _Row(
            label: 'Tax (${_formatRate(taxRate)}%)',
            value: '$currency ${_format(tax)}',
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Color(0xFFECECEC)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B1B1F),
                ),
              ),
              const Spacer(),
              Text(
                '$currency ${_format(total)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B1B1F),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF6B6B73)),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1B1B1F),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  final String currency;
  final double total;
  final int method;
  final VoidCallback onCancel;
  final VoidCallback onPay;
  const _ActionBar({
    required this.currency,
    required this.total,
    required this.method,
    required this.onCancel,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFECECEC))),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B6B73),
              padding: const EdgeInsets.symmetric(vertical: 15),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 65,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onPay,
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE86A33),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2EE86A33),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          method == 0 ? Icons.phone_android_outlined : Icons.payments_outlined,
                          color: Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            method == 0 ? 'Pay with M-Pesa' : 'Take Cash',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
            '$currency ${_format(total)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayItem {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PayItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}
