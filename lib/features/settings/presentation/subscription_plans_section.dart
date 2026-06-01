import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pay/pay.dart';

import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';

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
  bool _featuresExpanded = false;
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
        _message = AppErrorMessage.from(
          error,
          fallback: AppErrorMessage.loadFailed,
        );
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
      } else if (result.provider == 'mpesa' && result.paymentId.isNotEmpty) {
        await _pollMpesaPayment(result.paymentId, market);
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _message = AppErrorMessage.from(
          error,
          fallback: AppErrorMessage.paymentFailed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pollMpesaPayment(
    String paymentId,
    SubscriptionMarket market,
  ) async {
    for (var attempt = 0; attempt < 24; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      SubscriptionCheckoutResult payment;
      try {
        payment = await SubscriptionService.fetchPayment(paymentId: paymentId);
      } catch (_) {
        continue;
      }
      if (!mounted) return;

      setState(() {
        _checkout = payment;
      });
      if (payment.status == 'paid') {
        setState(() => _message = 'Payment received. Activating your plan...');
        await _refreshLicenseAndReload(market);
        return;
      }
      if (payment.status == 'failed') {
        setState(
          () => _message =
              'M-Pesa payment was not completed. Try again when you are ready.',
        );
        return;
      }
      if (payment.status == 'pending_configuration') {
        setState(
          () => _message =
              'M-Pesa is not fully configured yet. Contact your administrator.',
        );
        return;
      }
    }

    if (mounted) {
      setState(
        () => _message =
            'M-Pesa payment is still pending. Reopen subscriptions shortly to refresh the result.',
      );
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
      setState(
        () => _message = AppErrorMessage.from(
          error,
          fallback: AppErrorMessage.paymentFailed,
        ),
      );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final maxWidth = desktop ? 1180.0 : 520.0;
        final pagePadding = desktop
            ? const EdgeInsets.fromLTRB(28, 22, 28, 24)
            : const EdgeInsets.fromLTRB(18, 18, 18, 18);
        return Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.0, -0.6),
              radius: 1.4,
              colors: [
                Color(0xFF1B0C24), // Ambient deep purple glow
                Color(0xFF09090E), // Base background
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: pagePadding,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: _loading
                            ? _loadingPanel()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _premiumHeader(context),
                                  const SizedBox(height: 22),
                                  if (desktop)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: _heroPanel(context),
                                        ),
                                        const SizedBox(width: 18),
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            children: [
                                              _marketSelector(),
                                              const SizedBox(height: 14),
                                              _billingToggle(),
                                              const SizedBox(height: 14),
                                              _sellingModeSelector(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  else ...[
                                    _heroPanel(context),
                                    const SizedBox(height: 16),
                                    _marketSelector(),
                                    const SizedBox(height: 14),
                                    _billingToggle(),
                                    const SizedBox(height: 14),
                                    _sellingModeSelector(),
                                  ],
                                  const SizedBox(height: 18),
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
      },
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
          const _ShimmeringAiTag(),
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

    final activeIndex = periods.indexOf(_selectedBillingPeriod ?? '');
    final double alignX = periods.length > 1
        ? -1.0 + (2.0 * activeIndex / (periods.length - 1))
        : 0.0;

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Stack(
        children: [
          // Sliding background capsule
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: Alignment(alignX, 0.0),
            child: FractionallySizedBox(
              widthFactor: 1.0 / periods.length,
              heightFactor: 0.88,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_pink, _fuchsia]),
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: _pink.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Buttons
          Row(
            children: periods.map((period) {
              final selected = period == _selectedBillingPeriod;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy
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
                            _featuresExpanded = false;
                            _checkout = null;
                            _message = null;
                          });
                        },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                      child: Text(_periodLabel(period)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
          const SizedBox(height: 12),
          Row(
            children: modes.map((mode) {
              final selected = mode == _selectedSellingMode;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: _busy
                        ? null
                        : () => setState(() {
                            _selectedSellingMode = mode;
                            _checkout = null;
                            _message = null;
                          }),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? _pink.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? _pink.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.08),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sellingModeIcon(mode),
                            size: 20,
                            color: selected ? Colors.white : Colors.white60,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _sellingModeLabel(mode),
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white60,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final canGrid = widget.fullPage && constraints.maxWidth >= 760;
        if (!canGrid) {
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
        final columns = constraints.maxWidth >= 1080 ? 3 : 2;
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: plans.map((plan) {
            final selected = plan.code == _selectedPlanCode;
            return SizedBox(
              width: cardWidth,
              child: _planCard(plan, market, billingPeriod, selected),
            );
          }).toList(),
        );
      },
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

    return AnimatedScale(
      scale: selected ? 1.025 : 0.985,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _busy
            ? null
            : () => setState(() {
                _selectedPlanCode = plan.code;
                _selectedSellingMode = _sellingModeForPlan(
                  plan,
                  _selectedSellingMode,
                );
                _featuresExpanded = false;
                _checkout = null;
                _message = null;
              }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      _pink.withValues(alpha: 0.22),
                      _fuchsia.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.05),
                      Colors.white.withValues(alpha: 0.01),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.08),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _pink.withValues(alpha: 0.25),
                      blurRadius: 36,
                      spreadRadius: -2,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: _fuchsia.withValues(alpha: 0.15),
                      blurRadius: 36,
                      spreadRadius: -2,
                      offset: const Offset(0, -12),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
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
                            if (selected) ...[
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.secondary,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (isCurrent) ...[
                              _tinyBadge('Current', color: AppColors.success),
                              const SizedBox(width: 6),
                            ],
                            if (plan.code == 'pro')
                              _tinyBadge('Popular', color: AppColors.warning),
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
                const SizedBox(height: 16),
                _limitsGrid(plan),
                const SizedBox(height: 16),
                _featuresList(plan),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _limitsGrid(SubscriptionPlanSummary plan) {
    final rates = plan.entitlements.aiRateLimits;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Limits & Quotas',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _limitRowItem(
                  Icons.storefront_outlined,
                  'Max Branches',
                  _limitText(plan.entitlements.maxBranches),
                ),
              ),
              Expanded(
                child: _limitRowItem(
                  Icons.badge_outlined,
                  'Max Employees',
                  _limitText(plan.entitlements.maxEmployees),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),
          Row(
            children: [
              Expanded(
                child: _limitRowItem(
                  Icons.auto_awesome_outlined,
                  'AI Seats',
                  _limitText(plan.entitlements.maxAiAgents),
                ),
              ),
              Expanded(
                child: _limitRowItem(
                  Icons.bolt_outlined,
                  'AI Limits',
                  '${_limitText(rates['hourly'] ?? 0)}/hr • ${_limitText(rates['monthly'] ?? 0)}/mo',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _limitRowItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _pink.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFFFFB6D1)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
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
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featuresList(SubscriptionPlanSummary plan) {
    final features = plan.features;
    if (features.isEmpty) {
      return const Text(
        'No features configured.',
        style: TextStyle(color: Color(0xB8F9DDF0), fontSize: 12),
      );
    }

    final displayedFeatures = _featuresExpanded
        ? features
        : features.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Included Features',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        ...displayedFeatures.map((feature) {
          final isAi =
              feature.toLowerCase().contains('ai') ||
              feature.toLowerCase().contains('intelligence');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _featureIcon(feature),
                    size: 12,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          UserAccessProfile.featureLabel(feature),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isAi) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _pink.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _pink.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'AI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        if (features.length > 4) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              setState(() {
                _featuresExpanded = !_featuresExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _featuresExpanded
                        ? 'See less'
                        : 'See all ${features.length} features',
                    style: const TextStyle(
                      color: _pink,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _featuresExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: _pink,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
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
    final desktop = MediaQuery.sizeOf(context).width >= 900;
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
          constraints: BoxConstraints(maxWidth: desktop ? 1180 : 520),
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
    final desktop = widget.fullPage && MediaQuery.sizeOf(context).width >= 900;

    final summary = Container(
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
    );

    final paymentControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSummary && !desktop) const SizedBox(height: 10),
        if (market?.provider == 'mpesa' && !isFree)
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              'M-Pesa phone number',
              Icons.phone_android_outlined,
            ),
          ),
        if (market?.provider == 'mpesa' && !isFree) const SizedBox(height: 10),
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
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _actionLabel(market, plan, isFree, isCurrent),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
      ],
    );

    if (desktop && showSummary) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: summary),
          const SizedBox(width: 16),
          SizedBox(width: 380, child: paymentControls),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [if (showSummary) summary, paymentControls],
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: GooglePayButton(
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
        theme: GooglePayButtonTheme.dark,
        type: GooglePayButtonType.pay,
        onPaymentResult: _confirmGooglePay,
        loadingIndicator: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
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

  Widget _tinyBadge(String label, {Color color = AppColors.success}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
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

class _ShimmeringAiTag extends StatefulWidget {
  const _ShimmeringAiTag();

  @override
  State<_ShimmeringAiTag> createState() => _ShimmeringAiTagState();
}

class _ShimmeringAiTagState extends State<_ShimmeringAiTag>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                Color(0xFFFF2A6D),
                Color(0xFFC72DFF),
                Color(0xFFFF2A6D),
              ],
              stops: [0.0, _controller.value, 1.0],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2A6D).withValues(alpha: 0.15),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 15, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'AI SHOP ASSISTANT INCLUDED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
