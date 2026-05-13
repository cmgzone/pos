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
  final bool afterSignup;
  final String? initialCountryCode;
  final String? initialProvider;
  final String? initialPlanCode;
  final VoidCallback? onOpenApp;

  const SubscriptionPlansSection({
    super.key,
    this.fullPage = false,
    this.afterSignup = false,
    this.initialCountryCode,
    this.initialProvider,
    this.initialPlanCode,
    this.onOpenApp,
  });

  @override
  State<SubscriptionPlansSection> createState() =>
      _SubscriptionPlansSectionState();
}

class _SubscriptionPlansSectionState extends State<SubscriptionPlansSection> {
  static const _premiumBackground = Color(0xFF10050D);
  static const _panelColor = Color(0xFF17121F);
  static const _panelSoft = Color(0xFF211B2F);
  static const _pink = Color(0xFFFF2A6D);
  static const _fuchsia = Color(0xFFC72DFF);

  String? _selectedMarketKey;
  String? _selectedPlanCode;
  String? _selectedBillingPeriod;
  String? _selectedSellingMode;
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
    _load(
      countryCode: widget.initialCountryCode,
      marketKey: _selectedMarketKey,
    );
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

      final plans = selectedMarket == null
          ? <SubscriptionPlanSummary>[]
          : _plansForMarket(catalog, selectedMarket);
      final periods = selectedMarket == null
          ? <String>[]
          : _billingPeriodsFor(plans, selectedMarket);
      final billingPeriod = _preferredBillingPeriod(periods);
      final plansForBilling = selectedMarket == null || billingPeriod == null
          ? <SubscriptionPlanSummary>[]
          : _plansForBilling(plans, selectedMarket, billingPeriod);
      final currentPlan = _currentPlanCodeFrom(current);
      final preferredPlan = _selectedPlanCode ?? widget.initialPlanCode;
      final selectedPlanCode = _preferredPlanCode(
        plansForBilling,
        preferredPlan,
        currentPlan,
      );
      final selectedPlan = plansForBilling
          .where((plan) => plan.code == selectedPlanCode)
          .firstOrNull;
      final sellingMode = _preferredSellingMode(selectedPlan, current);

      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _current = current;
        _selectedMarketKey = selectedMarket?.key;
        _selectedBillingPeriod = billingPeriod;
        _selectedPlanCode = selectedPlanCode;
        _selectedSellingMode = sellingMode;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _startCheckout() async {
    final catalog = _catalog;
    final market = catalog == null
        ? null
        : _marketForKey(catalog, _selectedMarketKey) ?? catalog.selectedMarket;
    final plan = _selectedPlan();
    final billingPeriod = _selectedBillingPeriod;
    final sellingMode = _selectedSellingMode;
    final price = market == null || billingPeriod == null
        ? null
        : plan?.priceFor(market, billingPeriod: billingPeriod);
    final isFree = _isFreePrice(price);

    if (market == null) {
      setState(() => _message = 'No active payment market is configured.');
      return;
    }
    if (plan == null || billingPeriod == null) {
      setState(() => _message = 'Choose a subscription plan.');
      return;
    }
    if (sellingMode == null || !plan.sellingModes.contains(sellingMode)) {
      setState(
        () => _message =
            'Choose products, services, or combo for this subscription.',
      );
      return;
    }
    if (price == null) {
      setState(
        () => _message =
            'This billing cycle is not configured for the selected plan.',
      );
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
        planCode: plan.code,
        countryCode: market.countryCode,
        provider: market.provider,
        billingPeriod: billingPeriod,
        sellingMode: sellingMode,
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
    if (checkout == null || checkout.paymentId.isEmpty) return;
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

  @override
  Widget build(BuildContext context) {
    if (widget.fullPage) {
      return _buildFullPage(context);
    }
    return _buildEmbedded(context);
  }

  Widget _buildFullPage(BuildContext context) {
    return Container(
      color: _premiumBackground,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _loading
                        ? _loadingPanel()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _premiumHeader(context),
                              const SizedBox(height: 22),
                              _heroPanel(context),
                              const SizedBox(height: 16),
                              _marketSelector(),
                              const SizedBox(height: 14),
                              _billingToggle(),
                              const SizedBox(height: 14),
                              _sellingModeSelector(),
                              const SizedBox(height: 16),
                              _planList(),
                              if (_message != null) ...[
                                const SizedBox(height: 14),
                                _messageCard(_message!),
                              ],
                              const SizedBox(height: 14),
                              _safeDataPanel(),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            if (!_loading) _stickyFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbedded(BuildContext context) {
    if (_loading) {
      return _sectionShell(_loadingPanel());
    }
    return _sectionShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _premiumHeader(context, compact: true),
          const SizedBox(height: 16),
          _marketSelector(),
          const SizedBox(height: 14),
          _billingToggle(),
          const SizedBox(height: 14),
          _sellingModeSelector(),
          const SizedBox(height: 16),
          _planList(),
          if (_message != null) ...[
            const SizedBox(height: 14),
            _messageCard(_message!),
          ],
          const SizedBox(height: 14),
          _embeddedActionPanel(),
        ],
      ),
    );
  }

  Widget _sectionShell(Widget child) {
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

  Widget _loadingPanel() {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Center(child: CircularProgressIndicator(color: _pink)),
    );
  }

  Widget _premiumHeader(BuildContext context, {bool compact = false}) {
    final canSkip = _canSkipToPos;
    return Row(
      children: [
        Container(
          width: compact ? 44 : 52,
          height: compact ? 44 : 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_pink, _fuchsia]),
            borderRadius: BorderRadius.circular(compact ? 16 : 20),
            boxShadow: [
              BoxShadow(
                color: _pink.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Piki Premium',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.afterSignup ? 'Upgrade your POS' : 'Manage your POS',
                style: const TextStyle(
                  color: Color(0xB8F9DDF0),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (widget.onOpenApp != null)
          OutlinedButton(
            onPressed: canSkip ? widget.onOpenApp : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: Text(widget.afterSignup ? 'Skip' : 'Open POS'),
          ),
      ],
    );
  }

  Widget _heroPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _pink.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, size: 17, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'AI shop assistant included',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Run your shop smarter with Piki.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose exactly what your business sells, unlock the right features, and pay through the market your admin configured.',
            style: TextStyle(
              color: Color(0xB8F9DDF0),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _marketSelector() {
    final catalog = _catalog;
    final selectedMarket = _selectedMarket();
    if (catalog == null || catalog.markets.isEmpty) {
      return _messageCard('No subscription markets are active yet.');
    }
    return DropdownButtonFormField<String>(
      initialValue: selectedMarket?.key,
      dropdownColor: _panelColor,
      decoration: _inputDecoration('Market', Icons.public_outlined),
      items: catalog.markets
          .map(
            (market) => DropdownMenuItem(
              value: market.key,
              child: Text(market.displayLabel, overflow: TextOverflow.ellipsis),
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
    );
  }

  Widget _billingToggle() {
    final periods = _availableBillingPeriods();
    if (periods.length <= 1) {
      final label = periods.isEmpty
          ? 'No billing cycle configured'
          : 'Billing: ${_periodLabel(periods.first)}';
      return _softPanel(
        Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: periods.map((period) {
          final selected = period == _selectedBillingPeriod;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        final market = _selectedMarket();
                        final catalog = _catalog;
                        if (market == null || catalog == null) return;
                        final plans = _plansForBilling(
                          _plansForMarket(catalog, market),
                          market,
                          period,
                        );
                        final selectedPlan = plans
                            .where((plan) => plan.code == _selectedPlanCode)
                            .firstOrNull;
                        final nextPlan = selectedPlan ?? plans.firstOrNull;
                        setState(() {
                          _selectedBillingPeriod = period;
                          _selectedPlanCode = nextPlan?.code;
                          _selectedSellingMode = _sellingModeForPlan(
                            nextPlan,
                            _selectedSellingMode,
                          );
                          _checkout = null;
                          _message = null;
                        });
                      },
                style: TextButton.styleFrom(
                  backgroundColor: selected ? _pink : Colors.transparent,
                  foregroundColor: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.66),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text(
                  _periodLabel(period),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sellingModeSelector() {
    final plan = _selectedPlan();
    final modes = plan?.sellingModes ?? const <String>[];
    if (plan == null) {
      return _messageCard('Choose a plan to select what your business sells.');
    }
    if (modes.isEmpty) {
      return _messageCard(
        'This plan is not available for product or service selling yet.',
      );
    }
    return _softPanel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What do you sell?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: modes.map((mode) {
              final selected = mode == _selectedSellingMode;
              return ChoiceChip(
                selected: selected,
                avatar: Icon(_sellingModeIcon(mode), size: 17),
                label: Text(_sellingModeLabel(mode)),
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                        _selectedSellingMode = mode;
                        _checkout = null;
                        _message = null;
                      }),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _planList() {
    final catalog = _catalog;
    final market = _selectedMarket();
    final billingPeriod = _selectedBillingPeriod;
    if (catalog == null || market == null) {
      return _messageCard('No active plans are configured for this country.');
    }
    if (billingPeriod == null) {
      return _messageCard('No billing cycles are configured for this country.');
    }
    final plans = _plansForBilling(
      _plansForMarket(catalog, market),
      market,
      billingPeriod,
    );
    if (plans.isEmpty) {
      return _messageCard(
        'No active plan prices are configured for ${market.displayLabel}.',
      );
    }

    return Column(
      children: plans.map((plan) {
        final selected = plan.code == _selectedPlanCode;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _planCard(plan, market, billingPeriod, selected),
        );
      }).toList(),
    );
  }

  Widget _planCard(
    SubscriptionPlanSummary plan,
    SubscriptionMarket market,
    String billingPeriod,
    bool selected,
  ) {
    final price = plan.priceFor(market, billingPeriod: billingPeriod);
    final isCurrent = plan.code == _currentPlanCode();
    final featureLabels = plan.features
        .map(UserAccessProfile.featureLabel)
        .toList(growable: false);

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: _busy
          ? null
          : () => setState(() {
              _selectedPlanCode = plan.code;
              _selectedSellingMode = _sellingModeForPlan(
                plan,
                _selectedSellingMode,
              );
              _checkout = null;
              _message = null;
            }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? _pink.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.10),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _pink.withValues(alpha: 0.22),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
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
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: selected
                          ? const [_pink, _fuchsia]
                          : [
                              Colors.white.withValues(alpha: 0.12),
                              Colors.white.withValues(alpha: 0.05),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(_planIcon(plan), color: Colors.white),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              plan.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (isCurrent) _tinyBadge('Current'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.description.isEmpty
                            ? 'Configured by Super Admin.'
                            : plan.description,
                        style: const TextStyle(
                          color: Color(0xB8F9DDF0),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price?.displayAmount ?? 'Custom',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '/${_periodShortLabel(billingPeriod)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.52),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (selected) ...[
              const SizedBox(height: 14),
              _limitsGrid(plan),
              const SizedBox(height: 12),
              if (featureLabels.isEmpty)
                const Text(
                  'No features configured.',
                  style: TextStyle(color: Color(0xB8F9DDF0), fontSize: 12),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: plan.features
                      .map(
                        (feature) => _featurePill(
                          UserAccessProfile.featureLabel(feature),
                          _featureIcon(feature),
                        ),
                      )
                      .toList(),
                ),
            ],
          ],
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
          Icons.calendar_month_outlined,
          'AI / Month',
          _limitText(rates['monthly'] ?? 0),
        ),
      ],
    );
  }

  Widget _limitPill(IconData icon, String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFFFB6D1)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featurePill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFFB6D1)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _safeDataPanel() {
    return _softPanel(
      const Row(
        children: [
          Icon(Icons.verified_user_outlined, color: Colors.white),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cancel anytime',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Your shop data remains safe when you change plans.',
                  style: TextStyle(
                    color: Color(0xB8F9DDF0),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stickyFooter() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _premiumBackground.withValues(alpha: 0.98),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _footerContent(),
        ),
      ),
    );
  }

  Widget _embeddedActionPanel() {
    return _softPanel(_footerContent(showSummary: true));
  }

  Widget _footerContent({bool showSummary = true}) {
    final market = _selectedMarket();
    final plan = _selectedPlan();
    final billingPeriod = _selectedBillingPeriod;
    final price = market == null || billingPeriod == null
        ? null
        : plan?.priceFor(market, billingPeriod: billingPeriod);
    final isFree = _isFreePrice(price);
    final isCurrent = plan?.code == _currentPlanCode();
    final selectedMode = _selectedSellingMode;
    final canCheckout =
        market != null &&
        plan != null &&
        billingPeriod != null &&
        price != null &&
        selectedMode != null &&
        plan.sellingModes.contains(selectedMode) &&
        !_busy &&
        !(isCurrent && isFree);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSummary)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _sellingModeLabel(selectedMode ?? ''),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan?.name ?? 'Choose plan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price?.displayAmount ?? '-',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '/${_periodShortLabel(billingPeriod ?? 'monthly')}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.52),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (market?.provider == 'mpesa' && !isFree) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              'M-Pesa phone number',
              Icons.phone_android_outlined,
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (market?.provider == 'google_pay' &&
            !isFree &&
            _checkout != null &&
            plan != null)
          _googlePayButton(plan, market!, price)
        else
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: canCheckout ? _startCheckout : null,
              style: FilledButton.styleFrom(
                backgroundColor: _pink,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.10),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(
                _actionLabel(market, plan, isFree, isCurrent),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
      ],
    );
  }

  Widget _googlePayButton(
    SubscriptionPlanSummary plan,
    SubscriptionMarket market,
    SubscriptionPlanPrice? price,
  ) {
    final catalog = _catalog;
    final config =
        _checkout?.googlePayConfig?['paymentConfiguration'] ??
        catalog?.googlePayConfig?['paymentConfiguration'];
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

  Widget _softPanel(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: child,
    );
  }

  Widget _messageCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFB1B1),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tinyBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.success,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFFFFB6D1)),
      filled: true,
      fillColor: _panelSoft,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _pink),
      ),
    );
  }

  SubscriptionMarket? _selectedMarket() {
    final catalog = _catalog;
    if (catalog == null) return null;
    return _marketForKey(catalog, _selectedMarketKey) ??
        catalog.selectedMarket ??
        catalog.markets.firstOrNull;
  }

  SubscriptionPlanSummary? _selectedPlan() {
    final catalog = _catalog;
    final market = _selectedMarket();
    final billingPeriod = _selectedBillingPeriod;
    if (catalog == null || market == null || billingPeriod == null) return null;
    return _plansForBilling(
      _plansForMarket(catalog, market),
      market,
      billingPeriod,
    ).where((plan) => plan.code == _selectedPlanCode).firstOrNull;
  }

  List<SubscriptionPlanSummary> _plansForMarket(
    SubscriptionCatalog catalog,
    SubscriptionMarket market,
  ) {
    return catalog.plans
        .where((plan) => plan.billingPeriodsFor(market).isNotEmpty)
        .toList();
  }

  List<SubscriptionPlanSummary> _plansForBilling(
    List<SubscriptionPlanSummary> plans,
    SubscriptionMarket market,
    String billingPeriod,
  ) {
    return plans
        .where(
          (plan) => plan.priceFor(market, billingPeriod: billingPeriod) != null,
        )
        .toList();
  }

  List<String> _billingPeriodsFor(
    List<SubscriptionPlanSummary> plans,
    SubscriptionMarket market,
  ) {
    final periods = <String>[];
    for (final plan in plans) {
      for (final period in plan.billingPeriodsFor(market)) {
        if (!periods.contains(period)) periods.add(period);
      }
    }
    periods.sort((a, b) {
      const order = {'monthly': 0, 'yearly': 1, 'weekly': 2};
      return (order[a] ?? 99).compareTo(order[b] ?? 99);
    });
    return periods;
  }

  List<String> _availableBillingPeriods() {
    final catalog = _catalog;
    final market = _selectedMarket();
    if (catalog == null || market == null) return const [];
    return _billingPeriodsFor(_plansForMarket(catalog, market), market);
  }

  String? _preferredBillingPeriod(List<String> periods) {
    if (periods.isEmpty) return null;
    if (_selectedBillingPeriod != null &&
        periods.contains(_selectedBillingPeriod)) {
      return _selectedBillingPeriod;
    }
    if (periods.contains('monthly')) return 'monthly';
    return periods.first;
  }

  String? _preferredPlanCode(
    List<SubscriptionPlanSummary> plans,
    String? preferred,
    String? current,
  ) {
    if (preferred != null && plans.any((plan) => plan.code == preferred)) {
      return preferred;
    }
    if (current != null && plans.any((plan) => plan.code == current)) {
      return current;
    }
    final pro = plans.where((plan) => plan.code == 'pro').firstOrNull;
    return pro?.code ?? plans.firstOrNull?.code;
  }

  String? _preferredSellingMode(
    SubscriptionPlanSummary? plan,
    Map<String, dynamic>? current,
  ) {
    final currentMode = _currentSellingModeFrom(current);
    return _sellingModeForPlan(plan, _selectedSellingMode ?? currentMode);
  }

  String? _sellingModeForPlan(
    SubscriptionPlanSummary? plan,
    String? preferred,
  ) {
    final modes = plan?.sellingModes ?? const <String>[];
    if (modes.isEmpty) return null;
    if (preferred != null && modes.contains(preferred)) return preferred;
    if (modes.contains('products')) return 'products';
    return modes.first;
  }

  String? _currentPlanCode() => _currentPlanCodeFrom(_current);

  String? _currentPlanCodeFrom(Map<String, dynamic>? current) {
    final subscription = current?['subscription'];
    if (subscription is Map) {
      return subscription['plan']?.toString();
    }
    return LicenseService.currentSnapshot.plan;
  }

  String? _currentSellingModeFrom(Map<String, dynamic>? current) {
    final subscription = current?['subscription'];
    if (subscription is Map) {
      final entitlements = subscription['entitlements'];
      if (entitlements is Map) {
        return entitlements['sellingMode']?.toString();
      }
    }
    return LicenseService.currentSnapshot.entitlements.sellingMode;
  }

  bool get _canSkipToPos {
    final license = LicenseService.currentSnapshot;
    return widget.onOpenApp != null &&
        (license.accessStatus == LicenseAccessStatus.active ||
            license.accessStatus == LicenseAccessStatus.grace ||
            license.accessStatus == LicenseAccessStatus.localOnly);
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

  bool _isFreePrice(SubscriptionPlanPrice? price) {
    return (price?.amountMinor ?? 0) == 0;
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

  String _actionLabel(
    SubscriptionMarket? market,
    SubscriptionPlanSummary? plan,
    bool isFree,
    bool isCurrent,
  ) {
    if (_busy) return 'Working...';
    if (plan == null) return 'Choose a plan';
    if (isCurrent && isFree) return 'Current plan';
    if (isFree) return 'Activate ${plan.name}';
    if (market?.provider == 'mpesa') return 'Pay with M-Pesa';
    if (market?.provider == 'google_pay' && _checkout == null) {
      return isCurrent ? 'Renew with Google Pay' : 'Continue';
    }
    return 'Continue with ${plan.name}';
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'yearly':
        return 'Yearly';
      case 'weekly':
        return 'Weekly';
      default:
        return 'Monthly';
    }
  }

  String _periodShortLabel(String period) {
    switch (period) {
      case 'yearly':
        return 'year';
      case 'weekly':
        return 'week';
      default:
        return 'month';
    }
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
      case 'products':
        return 'Products only';
      default:
        return 'Choose business type';
    }
  }

  IconData _sellingModeIcon(String mode) {
    switch (mode) {
      case 'services':
        return Icons.design_services_outlined;
      case 'combo':
        return Icons.all_inclusive_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  IconData _planIcon(SubscriptionPlanSummary plan) {
    switch (plan.code) {
      case 'pro':
      case 'enterprise':
        return Icons.workspace_premium_outlined;
      case 'growth':
        return Icons.bolt_outlined;
      case 'starter':
        return Icons.storefront_outlined;
      default:
        return Icons.auto_awesome_outlined;
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
