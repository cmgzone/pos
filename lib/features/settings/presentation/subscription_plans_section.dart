import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pay/pay.dart';

import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';

class SubscriptionPlansSection extends StatefulWidget {
  const SubscriptionPlansSection({super.key});

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
    _load();
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
        provider: marketKey?.split(':').last,
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
      final currentPlanIsVisible = visiblePlans.any(
        (plan) => plan.code == currentPlan,
      );
      final selectedPlanIsVisible = visiblePlans.any(
        (plan) => plan.code == _selectedPlanCode,
      );
      setState(() {
        _catalog = catalog;
        _current = current;
        _selectedMarketKey = selectedMarket?.key;
        _selectedPlanCode = selectedPlanIsVisible
            ? _selectedPlanCode
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
    if (planCode == null || planCode.isEmpty) {
      return;
    }
    if (market == null) {
      setState(() => _message = 'No active payment market is configured.');
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
        phoneNumber: market.provider == 'mpesa' ? _phoneController.text : null,
      );
      if (!mounted) return;
      setState(() {
        _checkout = result;
        _message = result.message ?? _checkoutMessage(result);
      });
      if (result.status == 'paid') {
        await LicenseService.refreshOnline(
          backendUrl: await _backendUrl(),
          deviceId: await _deviceId(),
        );
        await _load(countryCode: market.countryCode, marketKey: market.key);
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
      if (result['activated'] == true) {
        await LicenseService.refreshOnline(
          backendUrl: await _backendUrl(),
          deviceId: await _deviceId(),
        );
        await _load(countryCode: market?.countryCode, marketKey: market?.key);
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

  Future<String> _backendUrl() async {
    await SyncSettingsService.init();
    return SyncSettingsService.backendUrl;
  }

  Future<String> _deviceId() async {
    return SyncSettingsService.getOrCreateDeviceId();
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
      return const Center(child: CircularProgressIndicator());
    }

    final catalog = _catalog;
    if (catalog == null) {
      return _messageCard(
        _message ?? 'Subscription plans could not be loaded.',
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
    final selectedPlan = visiblePlans
        .where((plan) => plan.code == _selectedPlanCode)
        .firstOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Subscription',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              if (catalog.markets.isNotEmpty)
                DropdownButton<String>(
                  value: selectedMarket?.key,
                  items: catalog.markets
                      .map(
                        (market) => DropdownMenuItem(
                          value: market.key,
                          child: Text(market.displayLabel),
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
                          _load(
                            countryCode: market?.countryCode,
                            marketKey: value,
                          );
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildUsage(),
          const SizedBox(height: 12),
          if (selectedMarket == null)
            _messageCard('No subscription payment gateways are active yet.')
          else if (visiblePlans.isEmpty)
            _messageCard(
              'No active plan prices are configured for ${selectedMarket.displayLabel}.',
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: visiblePlans
                  .map((plan) => _buildPlanChip(plan, selectedMarket))
                  .toList(growable: false),
            ),
          if (selectedPlan != null && selectedMarket != null) ...[
            const SizedBox(height: 14),
            _buildSelectedPlan(selectedPlan, catalog, selectedMarket),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            _messageCard(_message!),
          ],
        ],
      ),
    );
  }

  Widget _buildUsage() {
    final usage = _current?['usage'];
    final license = LicenseService.currentSnapshot;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _usagePill('Plan', license.plan ?? _currentPlanLabel()),
        if (usage is Map) ...[
          _usagePill(
            'Branches',
            '${usage['branches'] ?? 0}/${license.entitlements.maxBranches == 0 ? '-' : license.entitlements.maxBranches}',
          ),
          _usagePill(
            'Employees',
            '${usage['employees'] ?? 0}/${license.entitlements.maxEmployees == 0 ? '-' : license.entitlements.maxEmployees}',
          ),
          _usagePill(
            'Piki seats',
            '${usage['aiAgents'] ?? 0}/${license.entitlements.maxAiAgents == 0 ? '-' : license.entitlements.maxAiAgents}',
          ),
        ],
      ],
    );
  }

  String _currentPlanLabel() {
    final subscription = _current?['subscription'];
    if (subscription is Map) {
      return subscription['plan']?.toString() ?? '-';
    }
    return '-';
  }

  Widget _usagePill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildPlanChip(
    SubscriptionPlanSummary plan,
    SubscriptionMarket market,
  ) {
    final selected = plan.code == _selectedPlanCode;
    final price = plan.priceFor(market);
    return ChoiceChip(
      label: Text('${plan.name} - ${price?.displayAmount ?? 'Custom'}'),
      selected: selected,
      onSelected: _busy
          ? null
          : (_) {
              setState(() {
                _selectedPlanCode = plan.code;
                _checkout = null;
              });
            },
    );
  }

  Widget _buildSelectedPlan(
    SubscriptionPlanSummary plan,
    SubscriptionCatalog catalog,
    SubscriptionMarket market,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan.description,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: plan.features.take(8).map((feature) {
            return Chip(
              visualDensity: VisualDensity.compact,
              label: Text(UserAccessProfile.featureLabel(feature)),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (market.provider == 'mpesa') ...[
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
                : const Icon(Icons.phone_iphone_outlined),
            label: Text(_busy ? 'Starting...' : 'Pay with M-Pesa'),
          ),
        ] else if (market.provider == 'google_pay') ...[
          if (_checkout == null)
            FilledButton.icon(
              onPressed: _busy ? null : _startCheckout,
              icon: const Icon(Icons.payment_outlined),
              label: const Text('Prepare Google Pay'),
            )
          else
            _buildGooglePayButton(plan, catalog, market),
        ] else ...[
          _messageCard(
            '${market.providerLabel} checkout is not supported in the app yet.',
          ),
        ],
      ],
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

  String _checkoutMessage(SubscriptionCheckoutResult result) {
    if (result.provider == 'mpesa') {
      return 'M-Pesa prompt sent. Complete it on the phone to activate the plan.';
    }
    return 'Google Pay checkout is ready.';
  }
}
