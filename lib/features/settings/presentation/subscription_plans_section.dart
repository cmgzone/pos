import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _panelColor = Color(0xFF17121F);
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
  StreamSubscription<List<PurchaseDetails>>? _purchaseUpdates;
  Completer<PurchaseDetails>? _pendingPlayPurchase;
  String? _pendingPlayProductId;

  @override
  void initState() {
    super.initState();
    _selectedPlanCode = widget.initialPlanCode;
    _selectedMarketKey = _marketKeyFromInitial();
    if (Platform.isAndroid) {
      _purchaseUpdates = InAppPurchase.instance.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object error) {
          final pending = _pendingPlayPurchase;
          if (pending != null && !pending.isCompleted) {
            pending.completeError(error);
          }
        },
      );
    }
    _load(
      countryCode: widget.initialCountryCode,
      marketKey: _selectedMarketKey,
    );
  }

  @override
  void dispose() {
    _purchaseUpdates?.cancel();
    super.dispose();
  }

  void _handlePurchaseUpdates(List<PurchaseDetails> purchases) {
    final pending = _pendingPlayPurchase;
    if (pending == null || pending.isCompleted) return;
    for (final purchase in purchases) {
      if (purchase.productID != _pendingPlayProductId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          pending.complete(purchase);
          return;
        case PurchaseStatus.error:
          pending.completeError(
            purchase.error ?? Exception('Google Play purchase failed.'),
          );
          return;
        case PurchaseStatus.canceled:
          pending.completeError(
            Exception('Google Play purchase was cancelled.'),
          );
          return;
        case PurchaseStatus.pending:
          if (mounted) {
            setState(() => _message = 'Google Play payment is pending.');
          }
      }
    }
  }

  Future<void> _load({String? countryCode, String? marketKey}) async {
    setState(() {
      _loading = true;
      _message = null;
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
    if (!isFree && !market.paymentActive) {
      setState(
        () => _message =
            '${market.providerLabel} is not active for paid subscription checkout yet.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final result = await SubscriptionService.startCheckout(
        planCode: plan.code,
        countryCode: market.countryCode,
        provider: market.provider,
        billingPeriod: billingPeriod,
        sellingMode: sellingMode,
      );
      if (!mounted) return;
      setState(() {
        _message = result.message ?? _checkoutMessage(result);
      });
      if (result.status == 'paid') {
        await _refreshLicenseAndReload(market);
      } else if (result.provider == 'google_play') {
        await _purchaseWithGooglePlay(result, market, price);
      } else if (result.provider == 'paypal' ||
          result.provider == 'flutterwave') {
        await _openHostedCheckout(result, market);
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

  Future<void> _purchaseWithGooglePlay(
    SubscriptionCheckoutResult checkout,
    SubscriptionMarket market,
    SubscriptionPlanPrice price,
  ) async {
    final productId = checkout.storeProductId ?? price.storeProductId;
    if (productId == null || productId.isEmpty) {
      throw Exception('Google Play product is not configured for this plan.');
    }

    final purchaseApi = InAppPurchase.instance;
    if (!await purchaseApi.isAvailable()) {
      throw Exception('Google Play Billing is not available on this device.');
    }
    final products = await purchaseApi.queryProductDetails({productId});
    if (products.error != null) {
      throw Exception(products.error!.message);
    }
    if (products.productDetails.isEmpty ||
        products.notFoundIDs.contains(productId)) {
      throw Exception('Google Play product $productId was not found.');
    }

    final completer = Completer<PurchaseDetails>();
    _pendingPlayPurchase = completer;
    _pendingPlayProductId = productId;
    try {
      final started = await purchaseApi.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: products.productDetails.first,
        ),
      );
      if (!started) {
        throw Exception('Google Play could not start the purchase.');
      }
      final purchase = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException(
          'Google Play purchase confirmation timed out.',
        ),
      );
      final confirmation = await SubscriptionService.confirmGooglePlay(
        paymentId: checkout.paymentId,
        productId: productId,
        purchaseToken: purchase.verificationData.serverVerificationData,
      );
      if (confirmation['activated'] != true) {
        throw Exception(
          confirmation['message']?.toString() ??
              'Google Play purchase could not be verified.',
        );
      }
      if (purchase.pendingCompletePurchase) {
        await purchaseApi.completePurchase(purchase);
      }
      if (mounted) {
        setState(() => _message = 'Subscription activated.');
        await _refreshLicenseAndReload(market);
      }
    } finally {
      _pendingPlayPurchase = null;
      _pendingPlayProductId = null;
    }
  }

  Future<void> _openHostedCheckout(
    SubscriptionCheckoutResult checkout,
    SubscriptionMarket market,
  ) async {
    final uri = Uri.tryParse(checkout.checkoutUrl ?? '');
    if (uri == null || !uri.hasScheme) {
      throw Exception('${market.providerLabel} checkout URL is missing.');
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw Exception('Could not open ${market.providerLabel} checkout.');
    }
    if (mounted) {
      setState(() {
        _message =
            'Complete payment in ${market.providerLabel}. This screen will update automatically.';
      });
    }
    await _pollHostedPayment(checkout.paymentId, market);
  }

  Future<void> _pollHostedPayment(
    String paymentId,
    SubscriptionMarket market,
  ) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      SubscriptionCheckoutResult payment;
      try {
        payment = await SubscriptionService.fetchPayment(paymentId: paymentId);
      } catch (_) {
        if (attempt < 99) continue;
        rethrow;
      }
      if (payment.status == 'paid') {
        if (mounted) {
          setState(() => _message = 'Subscription activated.');
          await _refreshLicenseAndReload(market);
        }
        return;
      }
      if (payment.status == 'failed' || payment.status == 'cancelled') {
        throw Exception(
          payment.message ?? '${market.providerLabel} payment failed.',
        );
      }
    }
    throw TimeoutException(
      '${market.providerLabel} payment is still pending. You can refresh the subscription page after completing it.',
    );
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
        final desktop = constraints.maxWidth >= 960;
        final maxWidth = desktop ? 1240.0 : 520.0;
        final pagePadding = desktop
            ? const EdgeInsets.fromLTRB(28, 24, 28, 28)
            : const EdgeInsets.fromLTRB(16, 16, 16, 18);
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF060611), Color(0xFF160817), Color(0xFF09090E)],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  left: -160,
                  bottom: 60,
                  child: _orb(360, _fuchsia.withValues(alpha: 0.22)),
                ),
                Positioned(
                  right: -180,
                  bottom: 40,
                  child: _orb(430, _pink.withValues(alpha: 0.28)),
                ),
                SingleChildScrollView(
                  padding: pagePadding,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: _loading
                          ? _loadingPanel()
                          : desktop
                          ? _desktopSubscriptionFrame(context)
                          : _mobileSubscriptionFrame(context),
                    ),
                  ),
                ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 760;
        return _sectionShell(
          desktop
              ? _embeddedDesktopLayout(context)
              : _embeddedMobileLayout(context),
          premium: desktop,
        );
      },
    );
  }

  Widget _embeddedMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mobileHeaderBar(context),
        const SizedBox(height: 14),
        _countryAndBillingRow(compact: true),
        const SizedBox(height: 12),
        _planList(compact: true),
        if (_message != null) ...[
          const SizedBox(height: 14),
          _messageCard(_message!),
        ],
        const SizedBox(height: 14),
        _paymentMethodRail(compact: true),
        const SizedBox(height: 12),
        _embeddedActionPanel(),
      ],
    );
  }

  Widget _embeddedDesktopLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _premiumHeader(context)),
            const SizedBox(width: 18),
            SizedBox(width: 230, child: _countryPill()),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _headlineBlock(context)),
            const SizedBox(width: 18),
            SizedBox(width: 220, child: _billingToggle()),
          ],
        ),
        const SizedBox(height: 20),
        _planList(forceGrid: true),
        if (_message != null) ...[
          const SizedBox(height: 14),
          _messageCard(_message!),
        ],
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _paymentMethodRail()),
            const SizedBox(width: 16),
            SizedBox(width: 280, child: _sellingModeSelector()),
          ],
        ),
        const SizedBox(height: 18),
        _embeddedActionPanel(),
      ],
    );
  }

  Widget _sectionShell(Widget child, {bool premium = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(premium ? 24 : 18),
      decoration: BoxDecoration(
        color: premium
            ? const Color(0xFF080A12).withValues(alpha: 0.96)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(premium ? 28 : 14),
        border: Border.all(
          color: premium
              ? Colors.white.withValues(alpha: 0.14)
              : AppColors.border,
        ),
        boxShadow: premium
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.38),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ]
            : null,
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

  Widget _orb(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }

  Widget _desktopSubscriptionFrame(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 700),
      decoration: BoxDecoration(
        color: const Color(0xFF080A12).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 42,
            offset: const Offset(0, 24),
          ),
          BoxShadow(
            color: _pink.withValues(alpha: 0.18),
            blurRadius: 60,
            spreadRadius: -18,
            offset: const Offset(0, 28),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _desktopSidebar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _premiumHeader(context)),
                      const SizedBox(width: 18),
                      SizedBox(width: 230, child: _countryPill()),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _headlineBlock(context)),
                      const SizedBox(width: 18),
                      SizedBox(width: 220, child: _billingToggle()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _planList(),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _paymentMethodRail()),
                      const SizedBox(width: 16),
                      SizedBox(width: 280, child: _sellingModeSelector()),
                    ],
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 14),
                    _messageCard(_message!),
                  ],
                  const SizedBox(height: 18),
                  _footerContent(showSummary: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopSidebar() {
    const items = [
      (Icons.space_dashboard_outlined, 'Overview'),
      (Icons.receipt_long_outlined, 'Sales'),
      (Icons.inventory_2_outlined, 'Products'),
      (Icons.groups_outlined, 'Customers'),
      (Icons.analytics_outlined, 'Reports'),
      (Icons.auto_awesome_outlined, 'AI Assistant'),
      (Icons.payments_outlined, 'Payments'),
      (Icons.workspace_premium_outlined, 'Subscription'),
    ];
    return Container(
      width: 222,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              _WindowDot(color: Color(0xFFFF5F57)),
              SizedBox(width: 8),
              _WindowDot(color: Color(0xFFFFBD2E)),
              SizedBox(width: 8),
              _WindowDot(color: Color(0xFF28C840)),
            ],
          ),
          const SizedBox(height: 34),
          const Row(
            children: [
              Icon(Icons.shopping_bag_rounded, color: _pink, size: 24),
              SizedBox(width: 10),
              Text(
                'Piki POS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          ...items.map((item) {
            final active = item.$2 == 'Subscription';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                gradient: active
                    ? LinearGradient(
                        colors: [
                          _pink.withValues(alpha: 0.42),
                          _fuchsia.withValues(alpha: 0.08),
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    item.$1,
                    color: active ? Colors.white : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.$2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white60,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
          _sidebarPremiumCard(),
          const SizedBox(height: 18),
          Row(
            children: const [
              Icon(Icons.settings_outlined, color: Colors.white54, size: 18),
              SizedBox(width: 12),
              Text('Settings', style: TextStyle(color: Colors.white60)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sidebarPremiumCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            _pink.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.workspace_premium_rounded, color: _pink),
          SizedBox(height: 10),
          Text(
            'Piki Premium',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8),
          Text(
            'Unlock the full power of your business.',
            style: TextStyle(color: Color(0xB8F9DDF0), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _mobileSubscriptionFrame(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 430),
      decoration: BoxDecoration(
        color: const Color(0xFF090B13),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _mobileHeaderBar(context),
            const SizedBox(height: 24),
            _headlineBlock(context, compact: true),
            const SizedBox(height: 14),
            _countryAndBillingRow(compact: true),
            const SizedBox(height: 12),
            _planList(compact: true),
            if (_message != null) ...[
              const SizedBox(height: 12),
              _messageCard(_message!),
            ],
            const SizedBox(height: 14),
            _paymentMethodRail(compact: true),
            const SizedBox(height: 12),
            _footerContent(showSummary: false),
            const SizedBox(height: 10),
            _safeDataPanel(),
          ],
        ),
      ),
    );
  }

  Widget _mobileHeaderBar(BuildContext context) {
    return Row(
      children: [
        if (widget.onOpenApp != null)
          IconButton(
            onPressed: _canSkipToPos ? widget.onOpenApp : null,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          )
        else
          const SizedBox(width: 4),
        Expanded(child: _premiumHeader(context, compact: true)),
      ],
    );
  }

  Widget _headlineBlock(BuildContext context, {bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose your plan',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            height: 1.05,
            fontSize: compact ? 24 : 30,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pick the perfect plan for your business.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _countryAndBillingRow({bool compact = false}) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _countryPill(),
          const SizedBox(height: 10),
          _billingToggle(),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: _countryPill()),
        const SizedBox(width: 12),
        Expanded(child: _billingToggle()),
      ],
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

  Widget _countryPill() {
    final market = _selectedMarket();
    final label = market?.label == 'Other Countries'
        ? market?.countryCode ?? 'GLOBAL'
        : market?.label ?? 'Kenya';
    final countryCode =
        market?.countryCode ?? widget.initialCountryCode ?? 'KE';
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Text(_countryFlag(countryCode), style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodRail({bool compact = false}) {
    final catalog = _catalog;
    final markets = catalog?.markets ?? const <SubscriptionMarket>[];
    final providers = <String, SubscriptionMarket>{};
    for (final market in markets) {
      providers.putIfAbsent(market.provider, () => market);
    }
    final chips = providers.values.isEmpty
        ? [_selectedMarket()].whereType<SubscriptionMarket>().toList()
        : providers.values.toList();

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Secure payments with',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: chips
                .map(
                  (market) => InkWell(
                    onTap: _busy
                        ? null
                        : () {
                            setState(() => _selectedMarketKey = market.key);
                            _load(
                              countryCode: market.countryCode,
                              marketKey: market.key,
                            );
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: _providerBadge(market, compact: compact),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _providerBadge(SubscriptionMarket market, {bool compact = false}) {
    final selected = market.key == _selectedMarket()?.key;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 18,
        vertical: compact ? 9 : 12,
      ),
      decoration: BoxDecoration(
        color: selected
            ? _pink.withValues(alpha: 0.13)
            : Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? _pink.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _providerIcon(market.provider),
            size: compact ? 17 : 20,
            color: _providerColor(market.provider),
          ),
          SizedBox(width: compact ? 6 : 9),
          Text(
            market.providerLabel,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
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

  Widget _planList({bool compact = false, bool forceGrid = false}) {
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
        final canGrid = forceGrid || (!compact && constraints.maxWidth >= 720);
        if (!canGrid) {
          return Column(
            children: plans.map((plan) {
              final selected = plan.code == _selectedPlanCode;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _mobilePlanTile(plan, market, billingPeriod, selected),
              );
            }).toList(),
          );
        }
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        const gap = 14.0;
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        final cardHeight = columns >= 4 ? 410.0 : 386.0;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: plans.map((plan) {
            final selected = plan.code == _selectedPlanCode;
            return SizedBox(
              width: cardWidth,
              height: cardHeight,
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
    final popular = _isPopularPlan(plan);

    return AnimatedScale(
      scale: selected ? 1.015 : 1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _busy
            ? null
            : () => setState(() {
                _selectedPlanCode = plan.code;
                _selectedSellingMode = _sellingModeForPlan(
                  plan,
                  _selectedSellingMode,
                );
                _message = null;
              }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 292),
          padding: const EdgeInsets.all(18),
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
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? _pink.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.14),
              width: selected ? 1.6 : 1,
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
              if (popular)
                Align(
                  alignment: Alignment.topRight,
                  child: Transform.translate(
                    offset: const Offset(8, -30),
                    child: _popularRibbon(),
                  ),
                ),
              Row(
                children: [
                  _planIconBox(plan, selected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      plan.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (isCurrent)
                    _tinyBadge('Current', color: AppColors.success),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _planSubtitle(plan),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xB8F9DDF0),
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: 16),
              _priceLine(price, billingPeriod, large: true),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: 16),
              ..._featurePreview(plan).map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 16,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          UserAccessProfile.featureLabel(feature),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _selectedPlanCode = plan.code;
                          _selectedSellingMode = _sellingModeForPlan(
                            plan,
                            _selectedSellingMode,
                          );
                          _message = null;
                        }),
                  style:
                      OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: selected
                            ? null
                            : Colors.black.withValues(alpha: 0.16),
                        side: BorderSide(
                          color: selected
                              ? Colors.transparent
                              : _fuchsia.withValues(alpha: 0.65),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ).copyWith(
                        backgroundColor: selected
                            ? const WidgetStatePropertyAll(null)
                            : null,
                      ),
                  child: Ink(
                    decoration: selected
                        ? BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_pink, _fuchsia],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          )
                        : null,
                    child: Center(
                      child: Text(
                        _isFreePrice(price) ? 'Try for free' : 'Subscribe',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobilePlanTile(
    SubscriptionPlanSummary plan,
    SubscriptionMarket market,
    String billingPeriod,
    bool selected,
  ) {
    final price = plan.priceFor(market, billingPeriod: billingPeriod);
    final popular = _isPopularPlan(plan);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _busy
          ? null
          : () => setState(() {
              _selectedPlanCode = plan.code;
              _selectedSellingMode = _sellingModeForPlan(
                plan,
                _selectedSellingMode,
              );
              _message = null;
            }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    _pink.withValues(alpha: 0.20),
                    _fuchsia.withValues(alpha: 0.10),
                  ],
                )
              : LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.07),
                    Colors.white.withValues(alpha: 0.025),
                  ],
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? _pink.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _pink.withValues(alpha: 0.22),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                _planIconBox(plan, selected, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _planSubtitle(plan),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _priceLine(price, billingPeriod),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  color: selected ? _pink : Colors.white70,
                ),
              ],
            ),
            if (popular)
              Positioned(
                top: -15,
                right: 64,
                child: _popularRibbon(compact: true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _planIconBox(
    SubscriptionPlanSummary plan,
    bool selected, {
    double size = 48,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: selected
              ? const [_pink, _fuchsia]
              : [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.04),
                ],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(_planIcon(plan), color: Colors.white, size: size * 0.52),
    );
  }

  Widget _priceLine(
    SubscriptionPlanPrice? price,
    String billingPeriod, {
    bool large = false,
  }) {
    final amount = price?.displayAmount ?? 'Not set';
    return Column(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          amount,
          style: TextStyle(
            color: Colors.white,
            fontSize: large ? 26 : 13.5,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          price == null ? 'price' : '/${_periodShortLabel(billingPeriod)}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.56),
            fontSize: large ? 13 : 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _popularRibbon({bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_pink, _fuchsia]),
        borderRadius: BorderRadius.circular(compact ? 6 : 9),
        boxShadow: [
          BoxShadow(color: _pink.withValues(alpha: 0.35), blurRadius: 16),
        ],
      ),
      child: Text(
        'Most Popular',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 9 : 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  List<String> _featurePreview(SubscriptionPlanSummary plan) {
    if (plan.features.isNotEmpty) return plan.features.take(4).toList();
    return const [
      UserAccessProfile.featurePos,
      UserAccessProfile.featureSales,
      UserAccessProfile.featureDashboard,
    ];
  }

  String _planSubtitle(SubscriptionPlanSummary plan) {
    if (plan.description.trim().isNotEmpty) return plan.description;
    switch (plan.code) {
      case 'trial':
        return '7 days free';
      case 'starter':
        return 'For small shops';
      case 'growth':
        return 'For growing businesses';
      case 'pro':
        return 'For established brands';
      default:
        return 'Configured by Super Admin.';
    }
  }

  bool _isPopularPlan(SubscriptionPlanSummary plan) {
    return plan.code == 'growth' ||
        (plan.code == 'pro' &&
            !(_catalog?.plans.any((item) => item.code == 'growth') ?? false));
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
        (isFree || market.paymentActive) &&
        !_busy &&
        !(isCurrent && isFree);
    final desktop = MediaQuery.sizeOf(context).width >= 900;

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
    return catalog.plans.where((plan) => plan.sellingModes.isNotEmpty).toList();
  }

  List<SubscriptionPlanSummary> _plansForBilling(
    List<SubscriptionPlanSummary> plans,
    SubscriptionMarket market,
    String billingPeriod,
  ) {
    return plans.where((plan) {
      return plan.priceFor(market, billingPeriod: billingPeriod) != null ||
          plan.billingPeriodsFor(market).isEmpty;
    }).toList();
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
    final growth = plans.where((plan) => plan.code == 'growth').firstOrNull;
    if (growth != null) return growth.code;
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
    return price != null && price.amountMinor == 0;
  }

  String _checkoutMessage(SubscriptionCheckoutResult result) {
    if (result.status == 'paid') {
      return 'Subscription activated.';
    }
    if (result.provider == 'google_play') {
      return 'Google Play checkout is ready.';
    }
    return 'Continue in ${result.provider == 'paypal' ? 'PayPal' : 'Flutterwave'} to complete payment.';
  }

  String _actionLabel(
    SubscriptionMarket? market,
    SubscriptionPlanSummary? plan,
    bool isFree,
    bool isCurrent,
  ) {
    if (_busy) return 'Working...';
    if (plan == null) return 'Choose a plan';
    final price = market == null
        ? null
        : plan.priceFor(market, billingPeriod: _selectedBillingPeriod);
    if (price == null) return 'Price not configured';
    if (isCurrent && isFree) return 'Current plan';
    if (!isFree && market != null && !market.paymentActive) {
      return '${market.providerLabel} inactive';
    }
    if (isFree) return 'Activate ${plan.name}';
    switch (market?.provider) {
      case 'google_play':
        return isCurrent
            ? 'Renew with Google Play'
            : 'Subscribe with Google Play';
      case 'paypal':
        return 'Continue with PayPal';
      case 'flutterwave':
        return 'Continue with Flutterwave';
    }
    return 'Continue';
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

  String _countryFlag(String countryCode) {
    final code = countryCode.trim().toUpperCase();
    if (code.length != 2 || code == 'GLOBAL') return '🌍';
    final first = code.codeUnitAt(0);
    final second = code.codeUnitAt(1);
    if (first < 65 || first > 90 || second < 65 || second > 90) {
      return '🌍';
    }
    return String.fromCharCodes([first + 127397, second + 127397]);
  }

  IconData _providerIcon(String provider) {
    switch (provider) {
      case 'google_play':
        return Icons.play_arrow_rounded;
      case 'paypal':
        return Icons.account_balance_wallet_rounded;
      case 'flutterwave':
        return Icons.favorite_border_rounded;
      default:
        return Icons.payments_outlined;
    }
  }

  Color _providerColor(String provider) {
    switch (provider) {
      case 'google_play':
        return const Color(0xFF54D17A);
      case 'paypal':
        return const Color(0xFF8FB7FF);
      case 'flutterwave':
        return const Color(0xFFFFB020);
      default:
        return Colors.white70;
    }
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
}

class _WindowDot extends StatelessWidget {
  final Color color;

  const _WindowDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
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
