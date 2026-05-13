import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pay/pay.dart';

import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';

class SubscriptionPlansSection extends StatefulWidget {
  final bool fullPage;
  final String? initialCountryCode;
  final String? initialProvider;
  final String? initialPlanCode;

  const SubscriptionPlansSection({
    super.key,
    this.fullPage = false,
    this.initialCountryCode,
    this.initialProvider,
    this.initialPlanCode,
  });

  @override
  State<SubscriptionPlansSection> createState() =>
      _SubscriptionPlansSectionState();
}

class _SubscriptionPlansSectionState extends State<SubscriptionPlansSection> {
  String? _selectedMarketKey;
  String? _selectedPlanCode;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  SubscriptionCatalog? _catalog;
  Map<String, dynamic>? _current;
  SubscriptionCheckoutResult? _checkout;
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPlanCode = widget.initialPlanCode;
    _selectedMarketKey = _marketKeyFromInitial();
    _load(countryCode: widget.initialCountryCode, marketKey: _selectedMarketKey);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load({String? countryCode, String? marketKey}) async {
    setState(() {
      _loading = true;
      _message = null;
      _checkout = null;
    });
    try {
      final catalog = await SubscriptionService.fetchPlans(
        countryCode: countryCode,
        provider: marketKey?.split(':').last ?? widget.initialProvider,
      );
      final selectedMarket =
          _marketForKey(catalog, marketKey ?? _selectedMarketKey) ??
          catalog.selectedMarket ??
          catalog.markets.firstOrNull;
      Map<String, dynamic>? current;
      try {
        current = await SubscriptionService.fetchCurrent(
          countryCode: selectedMarket?.countryCode,
        );
      } catch (_) {}
      if (!mounted) return;
      final currentSubscription = current?['subscription'];
      final currentPlan = currentSubscription is Map
          ? currentSubscription['plan']?.toString()
          : null;
      final visiblePlans = selectedMarket == null
          ? <SubscriptionPlanSummary>[]
          : catalog.plans
                .where((plan) => plan.priceFor(selectedMarket) != null)
                .toList();
      final preferredPlan = _selectedPlanCode ?? widget.initialPlanCode;
      final preferredPlanIsVisible = visiblePlans.any(
        (plan) => plan.code == preferredPlan,
      );
      final currentPlanIsVisible = visiblePlans.any(
        (plan) => plan.code == currentPlan,
      );
      setState(() {
        _catalog = catalog;
        _current = current;
        _selectedMarketKey = selectedMarket?.key;
        _selectedPlanCode = preferredPlanIsVisible
            ? preferredPlan
            : currentPlanIsVisible
            ? currentPlan
            : visiblePlans.firstOrNull?.code;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startCheckout() async {
    final planCode = _selectedPlanCode;
    final catalog = _catalog;
    final market = catalog == null
        ? null
        : _marketForKey(catalog, _selectedMarketKey) ?? catalog.selectedMarket;
    final plan = catalog?.plans
        .where((item) => item.code == planCode)
        .firstOrNull;
    final price = market == null ? null : plan?.priceFor(market);
    final isFree = _isFreePrice(price);
    if (planCode == null || planCode.isEmpty) {
      return;
    }
    if (market == null) {
      setState(() => _message = 'No active payment market is configured.');
      return;
    }
    if (market.provider == 'mpesa' &&
        !isFree &&
        _phoneController.text.trim().isEmpty) {
      setState(() => _message = 'Enter the M-Pesa phone number.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _checkout = null;
    });
    try {
      final result = await SubscriptionService.startCheckout(
        planCode: planCode,
        countryCode: market.countryCode,
        provider: market.provider,
        phoneNumber: market.provider == 'mpesa' && !isFree
            ? _phoneController.text
            : null,
      );
      if (!mounted) return;
      setState(() {
        _checkout = result;
        _message = result.message ?? _checkoutMessage(result);
      });
      if (result.status == 'paid') {
        await _refreshLicenseAndReload(market);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmGooglePay(Map<String, dynamic> paymentData) async {
    final checkout = _checkout;
    final catalog = _catalog;
    final market = catalog == null
        ? null
        : _marketForKey(catalog, _selectedMarketKey) ?? catalog.selectedMarket;
    if (checkout == null || checkout.paymentId.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await SubscriptionService.confirmGooglePay(
        paymentId: checkout.paymentId,
        paymentData: paymentData,
      );
      if (!mounted) return;
      setState(() {
        _message =
            result['message']?.toString() ??
            (result['activated'] == true
                ? 'Subscription activated'
                : 'Payment received for backend processing');
      });
      if (result['activated'] == true && market != null) {
        await _refreshLicenseAndReload(market);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshLicenseAndReload(SubscriptionMarket market) async {
    await LicenseService.refreshOnline(
      backendUrl: await _backendUrl(),
      deviceId: await _deviceId(),
    );
    await _load(countryCode: market.countryCode, marketKey: market.key);
  }

  Future<String> _backendUrl() async {
    await SyncSettingsService.init();
    return SyncSettingsService.backendUrl;
  }

  Future<String> _deviceId() async {
    return SyncSettingsService.getOrCreateDeviceId();
  }

  String? _marketKeyFromInitial() {
    final country = widget.initialCountryCode?.trim();
    final provider = widget.initialProvider?.trim();
    if (country == null ||
        country.isEmpty ||
        provider == null ||
        provider.isEmpty) {
      return null;
    }
    return '${country.toUpperCase()}:$provider';
  }

  SubscriptionMarket? _marketForKey(
    SubscriptionCatalog catalog,
    String? marketKey,
  ) {
    if (marketKey == null) return null;
    return catalog.markets
        .where((market) => market.key == marketKey)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _sectionShell(
        const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final catalog = _catalog;
    if (catalog == null) {
      return _sectionShell(
        _messageCard(_message ?? 'Subscription plans could not be loaded.'),
      );
    }

    final selectedMarket =
        _marketForKey(catalog, _selectedMarketKey) ??
        catalog.selectedMarket ??
        catalog.markets.firstOrNull;
    final visiblePlans = selectedMarket == null
        ? <SubscriptionPlanSummary>[]
        : catalog.plans
              .where((plan) => plan.priceFor(selectedMarket) != null)
              .toList();
    final currentPlan = _currentPlanCode();

    return _sectionShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(catalog, selectedMarket),
          const SizedBox(height: 14),
          _buildUsage(),
          const SizedBox(height: 16),
          if (selectedMarket == null)
            _messageCard('No subscription payment gateways are active yet.')
          else if (visiblePlans.isEmpty)
            _messageCard(
              'No active plan prices are configured for ${selectedMarket.displayLabel}.',
            )
          else
            _buildPlanGrid(visiblePlans, catalog, selectedMarket, currentPlan),
          if (_message != null) ...[
            const SizedBox(height: 14),
            _messageCard(_message!),
          ],
        ],
      ),
    );
  }

  Widget _sectionShell(Widget child) {
    if (widget.fullPage) {
      return child;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _buildHeader(
    SubscriptionCatalog catalog,
    SubscriptionMarket? selectedMarket,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.workspace_premium, color: Colors.white),
        ),
        SizedBox(
          width: widget.fullPage ? 420 : 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.fullPage ? 'Choose Your Subscription' : 'Subscription',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: widget.fullPage ? 24 : 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Plans and prices come from Super Admin.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: widget.fullPage ? 13 : 12,
                ),
              ),
            ],
          ),
        ),
        if (catalog.markets.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: DropdownButtonFormField<String>(
              initialValue: selectedMarket?.key,
              decoration: const InputDecoration(
                labelText: 'Market',
                prefixIcon: Icon(Icons.public_outlined),
              ),
              items: catalog.markets
                  .map(
                    (market) => DropdownMenuItem(
                      value: market.key,
                      child: Text(
                        market.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      final market = catalog.markets
                          .where((item) => item.key == value)
                          .firstOrNull;
                      setState(() => _selectedMarketKey = value);
                      _load(countryCode: market?.countryCode, marketKey: value);
                    },
            ),
          ),
      ],
    );
  }

  Widget _buildUsage() {
    final usage = _current?['usage'];
    final license = LicenseService.currentSnapshot;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _metricTile(
          Icons.verified_outlined,
          'Current Plan',
          _planNameForCode(license.plan ?? _currentPlanCode() ?? '-'),
        ),
        if (usage is Map) ...[
          _metricTile(
            Icons.store_mall_directory_outlined,
            'Branches',
            '${usage['branches'] ?? 0}/${_limitText(license.entitlements.maxBranches)}',
          ),
          _metricTile(
            Icons.group_outlined,
            'Employees',
            '${usage['employees'] ?? 0}/${_limitText(license.entitlements.maxEmployees)}',
          ),
          _metricTile(
            Icons.auto_awesome_outlined,
            'Piki Seats',
            '${usage['aiAgents'] ?? 0}/${_limitText(license.entitlements.maxAiAgents)}',
          ),
        ],
      ],
    );
  }

  Widget _metricTile(IconData icon, String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanGrid(
    List<SubscriptionPlanSummary> plans,
    SubscriptionCatalog catalog,
    SubscriptionMarket market,
    String? currentPlan,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final columns = maxWidth >= 1120
            ? 3
            : maxWidth >= 720
            ? 2
            : 1;
        const gap = 12.0;
        final cardWidth = columns == 1
            ? maxWidth
            : (maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: plans
              .map(
                (plan) => SizedBox(
                  width: cardWidth,
                  child: _buildPlanCard(plan, catalog, market, currentPlan),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildPlanCard(
    SubscriptionPlanSummary plan,
    SubscriptionCatalog catalog,
    SubscriptionMarket market,
    String? currentPlan,
  ) {
    final selected = plan.code == _selectedPlanCode;
    final isCurrent = plan.code == currentPlan;
    final price = plan.priceFor(market);
    final featureLabels = plan.features
        .map(UserAccessProfile.featureLabel)
        .toList(growable: false);
    final priceText = price?.displayAmount ?? 'Custom';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.4 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _priceBadge(priceText),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (isCurrent) _statusBadge('Current', AppColors.success),
              if (selected) _statusBadge('Selected', AppColors.primaryLight),
              _statusBadge(market.providerLabel, AppColors.secondary),
            ],
          ),
          const SizedBox(height: 14),
          _limitsGrid(plan),
          const SizedBox(height: 14),
          _sellingModes(plan),
          const SizedBox(height: 14),
          const Text(
            'Included Features',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (featureLabels.isEmpty)
            const Text(
              'No features configured.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: plan.features
                  .map(
                    (feature) => _featureChip(
                      UserAccessProfile.featureLabel(feature),
                      _featureIcon(feature),
                    ),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 16),
          _buildPlanAction(plan, catalog, market, selected, isCurrent),
        ],
      ),
    );
  }

  Widget _priceBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.secondary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _limitsGrid(SubscriptionPlanSummary plan) {
    final rates = plan.entitlements.aiRateLimits;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _limitPill(
          Icons.storefront_outlined,
          'Branches',
          _limitText(plan.entitlements.maxBranches),
        ),
        _limitPill(
          Icons.badge_outlined,
          'Employees',
          _limitText(plan.entitlements.maxEmployees),
        ),
        _limitPill(
          Icons.auto_awesome_outlined,
          'AI Seats',
          _limitText(plan.entitlements.maxAiAgents),
        ),
        _limitPill(
          Icons.bolt_outlined,
          'AI / Hour',
          _limitText(rates['hourly'] ?? 0),
        ),
        _limitPill(
          Icons.date_range_outlined,
          'AI / Week',
          _limitText(rates['weekly'] ?? 0),
        ),
        _limitPill(
          Icons.calendar_month_outlined,
          'AI / Month',
          _limitText(rates['monthly'] ?? 0),
        ),
      ],
    );
  }

  Widget _limitPill(IconData icon, String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryLight),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sellingModes(SubscriptionPlanSummary plan) {
    final modes = plan.sellingModes;
    if (modes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: modes
          .map(
            (mode) => _featureChip(
              _sellingModeLabel(mode),
              switch (mode) {
                'services' => Icons.design_services_outlined,
                'combo' => Icons.all_inclusive_outlined,
                _ => Icons.inventory_2_outlined,
              },
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _featureChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.secondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanAction(
    SubscriptionPlanSummary plan,
    SubscriptionCatalog catalog,
    SubscriptionMarket market,
    bool selected,
    bool isCurrent,
  ) {
    if (!selected) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () {
                  setState(() {
                    _selectedPlanCode = plan.code;
                    _checkout = null;
                    _message = null;
                  });
                },
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Select Plan'),
        ),
      );
    }

    final price = plan.priceFor(market);
    final isFree = _isFreePrice(price);
    if (isCurrent && isFree) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('Current Plan'),
        ),
      );
    }

    if (market.provider == 'mpesa' && !isFree) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'M-Pesa phone number',
              prefixIcon: Icon(Icons.phone_android_outlined),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _startCheckout,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.phone_iphone_outlined, size: 18),
            label: Text(_busy ? 'Starting...' : 'Pay with M-Pesa'),
          ),
        ],
      );
    }

    if (market.provider == 'google_pay' && !isFree) {
      if (_checkout == null) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _startCheckout,
            icon: const Icon(Icons.payment_outlined, size: 18),
            label: Text(isCurrent ? 'Renew with Google Pay' : 'Continue'),
          ),
        );
      }
      return _buildGooglePayButton(plan, catalog, market);
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : _startCheckout,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.verified_outlined, size: 18),
        label: Text(_busy ? 'Activating...' : 'Activate Plan'),
      ),
    );
  }

  Widget _buildGooglePayButton(
    SubscriptionPlanSummary plan,
    SubscriptionCatalog catalog,
    SubscriptionMarket market,
  ) {
    final price = plan.priceFor(market);
    final config =
        _checkout?.googlePayConfig?['paymentConfiguration'] ??
        catalog.googlePayConfig?['paymentConfiguration'];
    if (config is! Map<String, dynamic> || price == null) {
      return _messageCard('Google Pay is not configured for this plan.');
    }
    return GooglePayButton(
      paymentConfiguration: PaymentConfiguration.fromJsonString(
        jsonEncode(config),
      ),
      paymentItems: [
        PaymentItem(
          label: plan.name,
          amount: (price.amountMinor / 100).toStringAsFixed(2),
          status: PaymentItemStatus.final_price,
        ),
      ],
      type: GooglePayButtonType.pay,
      onPaymentResult: _confirmGooglePay,
      loadingIndicator: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _messageCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Text(message, style: const TextStyle(fontSize: 12)),
    );
  }

  String? _currentPlanCode() {
    final subscription = _current?['subscription'];
    if (subscription is Map) {
      return subscription['plan']?.toString();
    }
    return LicenseService.currentSnapshot.plan;
  }

  String _planNameForCode(String code) {
    final catalog = _catalog;
    if (catalog == null) return code;
    return catalog.plans
            .where((plan) => plan.code == code)
            .firstOrNull
            ?.name ??
        code;
  }

  String _checkoutMessage(SubscriptionCheckoutResult result) {
    if (result.status == 'paid') {
      return 'Subscription activated.';
    }
    if (result.provider == 'mpesa') {
      return 'M-Pesa prompt sent. Complete it on the phone to activate the plan.';
    }
    return 'Google Pay checkout is ready.';
  }

  bool _isFreePrice(SubscriptionPlanPrice? price) {
    return (price?.amountMinor ?? 0) == 0;
  }

  String _limitText(int value) {
    if (value <= 0 || value >= 999999) return 'Unlimited';
    return value.toString();
  }

  String _sellingModeLabel(String mode) {
    switch (mode) {
      case 'services':
        return 'Services only';
      case 'combo':
        return 'Products + Services';
      default:
        return 'Products only';
    }
  }

  IconData _featureIcon(String feature) {
    switch (feature) {
      case UserAccessProfile.featurePos:
        return Icons.point_of_sale_outlined;
      case UserAccessProfile.featureProducts:
        return Icons.inventory_2_outlined;
      case UserAccessProfile.featureCategories:
        return Icons.category_outlined;
      case UserAccessProfile.featurePurchases:
        return Icons.local_shipping_outlined;
      case UserAccessProfile.featureSales:
        return Icons.receipt_long_outlined;
      case UserAccessProfile.featureDashboard:
        return Icons.space_dashboard_outlined;
      case UserAccessProfile.featureKopesha:
        return Icons.account_balance_wallet_outlined;
      case UserAccessProfile.featureProfitLoss:
        return Icons.insert_chart_outlined;
      case UserAccessProfile.featureReports:
        return Icons.analytics_outlined;
      case UserAccessProfile.featureSettings:
        return Icons.settings_outlined;
      case UserAccessProfile.featureShifts:
        return Icons.timer_outlined;
      case UserAccessProfile.featureServices:
        return Icons.design_services_outlined;
      case UserAccessProfile.featureAgent:
      case UserAccessProfile.featureProactivePiki:
        return Icons.auto_awesome_outlined;
      case UserAccessProfile.featureStockList:
        return Icons.fact_check_outlined;
      case UserAccessProfile.featureTransfers:
        return Icons.swap_horiz_outlined;
      case UserAccessProfile.featureBranches:
        return Icons.store_mall_directory_outlined;
      case UserAccessProfile.featureAuditLogs:
        return Icons.manage_search_outlined;
      default:
        return Icons.check_circle_outline;
    }
  }
}
