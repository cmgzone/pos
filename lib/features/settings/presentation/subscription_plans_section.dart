import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/country_detector.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/utils/error_messages.dart';

/// ---------------------------------------------------------------------------
/// The Till Ledger design language.
///
/// The subscription page is dressed like a shop's till ledger: a deep green
/// counter surface, warm paper "receipts" for each plan with perforated edges,
/// monospace figures, dashed rules and a rubber-stamp selection mark. It reads
/// as a place where money is counted — which is exactly what a plan is.
/// ---------------------------------------------------------------------------
class _Ledger {
  const _Ledger._();

  // Counter (dark) surface
  static const Color counter = Color(0xFF0B1B15);
  static const Color counterRaised = Color(0xFF12251D);
  static const Color counterLine = Color(0xFF22392F);

  // Paper (receipt) surface
  static const Color paper = Color(0xFFF8F4E8);
  static const Color paperDeep = Color(0xFFEFE9D8);
  static const Color paperInk = Color(0xFF1B241F);
  static const Color paperFaded = Color(0xFF63705F);
  static const Color paperRule = Color(0xFFCBC2AA);

  // Accents
  static const Color stamp = Color(0xFFE0641A);
  static const Color stampDeep = Color(0xFFB14E0C);
  static const Color mint = Color(0xFF2FBFA4);
  static const Color gold = Color(0xFFE3B341);

  static TextStyle display(
    double size, {
    Color color = paper,
    FontWeight weight = FontWeight.w700,
    double? height,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: size * -0.02,
        height: height ?? 1.05,
      );

  static TextStyle mono(
    double size, {
    Color color = paperInk,
    FontWeight weight = FontWeight.w600,
    double? letterSpacing,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle body(
    double size, {
    Color color = paperFaded,
    FontWeight weight = FontWeight.w500,
    double? height,
  }) =>
      TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height ?? 1.4,
      );
}

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

class _SubscriptionPlansSectionState extends State<SubscriptionPlansSection>
    with TickerProviderStateMixin {
  String? _selectedMarketKey;
  String? _selectedPlanCode;
  String? _selectedBillingPeriod;
  String? _selectedSellingMode;
  String? _detectedCountryCode;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  SubscriptionCatalog? _catalog;
  Map<String, dynamic>? _current;
  StreamSubscription<List<PurchaseDetails>>? _purchaseUpdates;
  Completer<PurchaseDetails>? _pendingPlayPurchase;
  String? _pendingPlayProductId;

  final LayerLink _countryLink = LayerLink();
  OverlayEntry? _countryEntry;

  late final AnimationController _reveal;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
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
    _closeCountryPicker();
    _reveal.dispose();
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
      final resolvedCountry = countryCode ?? await _resolveCountryFallback();
      final catalog = await SubscriptionService.fetchPlans(
        countryCode: resolvedCountry,
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
      } catch (e, st) {
        debugPrint('SubscriptionPlansSection: fetchCurrent failed: $e\n$st');
      }

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
            'Choose products, services, restaurant, or combo for this subscription.',
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

  // ── Full page: the till counter ────────────────────────────────────────────
  Widget _buildFullPage(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        return DecoratedBox(
          decoration: const BoxDecoration(color: _Ledger.counter),
          child: SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _counterBackdropTop(desktop)),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: desktop ? 1240.0 : 560.0,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 32 : 18,
                          0,
                          desktop ? 32 : 18,
                          56,
                        ),
                        child: _loading
                            ? _ledgerLoading()
                            : (desktop
                                  ? _desktopLedger(context)
                                  : _mobileLedger(context)),
                      ),
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

  /// The masthead that sits on the counter: brand line, giant display title,
  /// and the live license strip. This is the "open with the subject" moment —
  /// a till header, not a generic hero.
  Widget _counterBackdropTop(bool desktop) {
    final license = LicenseService.currentSnapshot;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 32 : 18,
        desktop ? 34 : 22,
        desktop ? 32 : 18,
        desktop ? 30 : 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: desktop ? 1240.0 : 560.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeTransition(
                opacity: _reveal,
                child: Row(
                  children: [
                    _brandMark(),
                    const SizedBox(width: 12),
                    Text(
                      'PIKI POS',
                      style: _Ledger.mono(
                        13,
                        color: _Ledger.paper.withValues(alpha: 0.85),
                        weight: FontWeight.w700,
                        letterSpacing: 3.2,
                      ),
                    ),
                    const Spacer(),
                    if (widget.onOpenApp != null)
                      _ghostCounterButton(
                        label: widget.afterSignup ? 'SKIP' : 'OPEN POS',
                        icon: Icons.arrow_forward_rounded,
                        enabled: _canSkipToPos,
                        onTap: widget.onOpenApp!,
                      ),
                  ],
                ),
              ),
              SizedBox(height: desktop ? 34 : 26),
              FadeTransition(
                opacity: _reveal,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.afterSignup
                            ? 'Open your\nfirst till.'
                            : 'Balance the\ncounter.',
                        style: _Ledger.display(
                          desktop ? 64 : 44,
                          color: _Ledger.paper,
                          weight: FontWeight.w700,
                          height: 0.98,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.afterSignup
                            ? 'Pick the plan that matches what you sell. Change it any time — your data never leaves the till.'
                            : 'Plans, billing and receipts in one ledger. Switch any time; your shop data stays put.',
                        style: _Ledger.body(
                          desktop ? 15 : 13.5,
                          color: _Ledger.paper.withValues(alpha: 0.62),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: desktop ? 26 : 20),
              FadeTransition(
                opacity: _reveal,
                child: _licenseStrip(license),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandMark() {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: _Ledger.stamp,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: _Ledger.stamp.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(
        Icons.point_of_sale_rounded,
        color: Color(0xFF14100A),
        size: 21,
      ),
    );
  }

  Widget _ghostCounterButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: _Ledger.paper.withValues(alpha: 0.28),
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: _Ledger.mono(
                    11,
                    color: _Ledger.paper.withValues(alpha: 0.9),
                    weight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 14, color: _Ledger.paper.withValues(alpha: 0.9)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _licenseStrip(LicenseSnapshot license) {
    final market = _selectedMarket();
    final status = _licenseStatusLabel(license.accessStatus);
    final active = license.accessStatus == LicenseAccessStatus.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _Ledger.counterRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Ledger.counterLine),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final items = [
            _stripCell(
              'LICENSE',
              status.toUpperCase(),
              active ? _Ledger.mint : _Ledger.gold,
            ),
            _stripCell(
              'MARKET',
              (market?.displayLabel ?? '—').toUpperCase(),
              _Ledger.paper.withValues(alpha: 0.8),
            ),
            _stripCell(
              'CURRENT PLAN',
              (_currentPlanCode() ?? 'none').toUpperCase(),
              _Ledger.paper.withValues(alpha: 0.8),
            ),
          ];
          if (constraints.maxWidth >= 640) {
            return Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) _stripDivider(),
                  Expanded(child: items[i]),
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(
                      color: _Ledger.counterLine,
                      height: 1,
                      thickness: 1,
                    ),
                  ),
                items[i],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _stripDivider() {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      color: _Ledger.counterLine,
    );
  }

  Widget _stripCell(String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: valueColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: _Ledger.mono(
                  9.5,
                  color: _Ledger.paper.withValues(alpha: 0.42),
                  weight: FontWeight.w600,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _Ledger.mono(12.5, color: valueColor, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Desktop ledger: receipts on the left, order rail on the right ─────────
  Widget _desktopLedger(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 70,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _controlRow(),
              const SizedBox(height: 24),
              _receiptRack(),
              const SizedBox(height: 22),
              _sellingModeLedger(),
            ],
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 340,
          child: _orderRail(sticky: true),
        ),
      ],
    );
  }

  Widget _mobileLedger(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controlRow(compact: true),
        const SizedBox(height: 20),
        _receiptRack(compact: true),
        const SizedBox(height: 20),
        _sellingModeLedger(compact: true),
        const SizedBox(height: 20),
        _orderRail(sticky: false),
      ],
    );
  }

  /// Country + billing controls, styled as stamped counter controls.
  Widget _controlRow({bool compact = false}) {
    final controls = [
      Expanded(child: _countryControl()),
      const SizedBox(width: 12),
      Expanded(child: _billingControl()),
    ];
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _countryControl(),
          const SizedBox(height: 10),
          _billingControl(),
        ],
      );
    }
    return Row(children: controls);
  }

  Widget _countryControl() {
    final market = _selectedMarket();
    final label = market?.label ?? 'Other Countries';
    final countryCode =
        market?.countryCode ??
        widget.initialCountryCode ??
        _detectedCountryCode ??
        'KE';
    final canChange = _availableCountries().length > 1 && !_busy;
    return CompositedTransformTarget(
      link: _countryLink,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canChange ? _toggleCountryPicker : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _Ledger.counterRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _countryEntry != null
                    ? _Ledger.stamp.withValues(alpha: 0.6)
                    : _Ledger.counterLine,
              ),
            ),
            child: Row(
              children: [
                Text(
                  _countryFlag(countryCode),
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'MARKET',
                        style: _Ledger.mono(
                          9,
                          color: _Ledger.paper.withValues(alpha: 0.4),
                          weight: FontWeight.w600,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _Ledger.display(
                          15,
                          color: _Ledger.paper,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _countryEntry != null ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: canChange
                        ? _Ledger.paper.withValues(alpha: 0.7)
                        : _Ledger.paper.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<SubscriptionCountry> _availableCountries() {
    return _catalog?.availableCountries ?? const <SubscriptionCountry>[];
  }

  void _toggleCountryPicker() {
    if (_countryEntry != null) {
      _closeCountryPicker();
    } else {
      _openCountryPicker();
    }
  }

  void _openCountryPicker() {
    final countries = _availableCountries();
    if (countries.length <= 1) return;
    _countryEntry = OverlayEntry(
      builder: (_) => _CountryPickerOverlay(
        link: _countryLink,
        countries: countries,
        selectedCode: _selectedMarket()?.countryCode,
        flagFor: _countryFlag,
        onPick: _selectCountry,
        onDismiss: _closeCountryPicker,
      ),
    );
    Overlay.of(context).insert(_countryEntry!);
    setState(() {});
  }

  void _closeCountryPicker() {
    final entry = _countryEntry;
    if (entry == null) return;
    _countryEntry = null;
    entry.remove();
    if (mounted) {
      setState(() {});
    }
  }

  void _selectCountry(SubscriptionCountry country) {
    _closeCountryPicker();
    final provider = _selectedMarket()?.provider;
    _load(
      countryCode: country.countryCode,
      marketKey: provider == null
          ? null
          : '${country.countryCode}:$provider',
    );
  }

  Widget _billingControl() {
    final periods = _availableBillingPeriods();
    if (periods.length <= 1) {
      final label = periods.isEmpty
          ? 'No billing cycle configured'
          : 'Billing: ${_periodLabel(periods.first)}';
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _Ledger.counterRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Ledger.counterLine),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: _Ledger.paper.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: _Ledger.display(
                  14,
                  color: _Ledger.paper,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _Ledger.counterRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Ledger.counterLine),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeIndex = math.max(
            0,
            periods.indexOf(_selectedBillingPeriod ?? ''),
          );
          final cellWidth = constraints.maxWidth / periods.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: activeIndex * cellWidth,
                top: 0,
                bottom: 0,
                width: cellWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: _Ledger.paper,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: periods.map((period) {
                  final selected = period == _selectedBillingPeriod;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _busy ? null : () => _selectBillingPeriod(period),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: _Ledger.mono(
                            12.5,
                            weight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: selected
                                ? _Ledger.paperInk
                                : _Ledger.paper.withValues(alpha: 0.55),
                          ),
                          child: Text(
                            _periodLabel(period).toUpperCase(),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  void _selectBillingPeriod(String period) {
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
  }

  /// The rack of plan receipts.
  Widget _receiptRack({bool compact = false}) {
    final catalog = _catalog;
    final market = _selectedMarket();
    final billingPeriod = _selectedBillingPeriod;
    if (catalog == null || market == null) {
      return _counterNote('No active plans are configured for this country.');
    }
    if (billingPeriod == null) {
      return _counterNote('No billing cycles are configured for this country.');
    }
    final plans = _plansForBilling(
      _plansForMarket(catalog, market),
      market,
      billingPeriod,
    );
    if (plans.isEmpty) {
      return _counterNote(
        'No active plan prices are configured for ${market.displayLabel}.',
      );
    }

    if (compact) {
      return Column(
        children: [
          for (var i = 0; i < plans.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _planReceipt(
              plan: plans[i],
              market: market,
              billingPeriod: billingPeriod,
              selected: plans[i].code == _selectedPlanCode,
              index: i,
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? plans.length.clamp(2, 4) : 2;
        const gap = 18.0;
        final width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < plans.length; i++)
              SizedBox(
                width: width,
                child: _planReceipt(
                  plan: plans[i],
                  market: market,
                  billingPeriod: billingPeriod,
                  selected: plans[i].code == _selectedPlanCode,
                  index: i,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _counterNote(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _Ledger.counterRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Ledger.counterLine),
      ),
      child: Text(
        text,
        style: _Ledger.body(13, color: _Ledger.paper.withValues(alpha: 0.7)),
      ),
    );
  }

  // ── Order rail (the "YOUR ORDER" till receipt) ────────────────────────────
  Widget _orderRail({required bool sticky}) {
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

    return _PaperReceipt(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'YOUR ORDER',
                  style: _Ledger.mono(
                    12,
                    color: _Ledger.paperInk,
                    weight: FontWeight.w700,
                    letterSpacing: 2.4,
                  ),
                ),
                const Spacer(),
                Text(
                  _tillNumber(),
                  style: _Ledger.mono(
                    10.5,
                    color: _Ledger.paperFaded,
                    weight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'PIKI POS · ${(_countryFlag(market?.countryCode ?? 'KE'))} ${market?.displayLabel ?? '—'}',
              style: _Ledger.mono(
                10,
                color: _Ledger.paperFaded,
                weight: FontWeight.w500,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 16),
            _DashedRule(color: _Ledger.paperRule),
            const SizedBox(height: 16),
            _orderLine(
              'PLAN',
              plan?.name ?? '—',
              value: price?.displayAmount ?? '—',
            ),
            const SizedBox(height: 10),
            _orderLine(
              'CYCLE',
              '/${_periodShortLabel(billingPeriod ?? 'monthly')}',
              value: isFree ? 'FREE' : '',
            ),
            const SizedBox(height: 10),
            _orderLine(
              'SELLS',
              _sellingModeLabel(selectedMode ?? ''),
              value: '',
            ),
            const SizedBox(height: 16),
            _DashedRule(color: _Ledger.paperRule),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'TOTAL',
                  style: _Ledger.mono(
                    11,
                    color: _Ledger.paperFaded,
                    weight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    key: ValueKey(price?.displayAmount ?? '—'),
                    price?.displayAmount ?? '—',
                    style: _Ledger.mono(
                      26,
                      color: _Ledger.paperInk,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'DUE TODAY · ${_periodShortLabel(billingPeriod ?? 'monthly').toUpperCase()}',
                style: _Ledger.mono(
                  9.5,
                  color: _Ledger.paperFaded,
                  weight: FontWeight.w600,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _BarcodeStrip(seed: (plan?.code ?? 'plan').hashCode),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: _stampButton(
                label: _actionLabel(market, plan, isFree, isCurrent),
                enabled: canCheckout,
                onTap: _startCheckout,
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _ledgerMessage(_message!),
            ],
            const SizedBox(height: 14),
            _paymentBadges(),
          ],
        ),
      ),
    );
  }

  Widget _orderLine(String label, String name, {required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: _Ledger.mono(
              9.5,
              color: _Ledger.paperFaded,
              weight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
        Expanded(
          child: Text(
            name,
            style: _Ledger.mono(
              12.5,
              color: _Ledger.paperInk,
              weight: FontWeight.w600,
            ),
          ),
        ),
        if (value.isNotEmpty)
          Text(
            value,
            style: _Ledger.mono(
              12.5,
              color: _Ledger.paperInk,
              weight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  String _tillNumber() {
    final id = SessionService.currentUserId;
    final tail = id.length > 4 ? id.substring(id.length - 4) : id;
    return 'TILL #$tail';
  }

  Widget _paymentBadges() {
    final catalog = _catalog;
    final markets = catalog?.markets ?? const <SubscriptionMarket>[];
    final providers = <String, SubscriptionMarket>{};
    for (final market in markets) {
      providers.putIfAbsent(market.provider, () => market);
    }
    final chips = providers.values.isEmpty
        ? [_selectedMarket()].whereType<SubscriptionMarket>().toList()
        : providers.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SECURE PAYMENTS WITH',
          style: _Ledger.mono(
            9,
            color: _Ledger.paperFaded,
            weight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips.map((market) {
            final selected = market.key == _selectedMarket()?.key;
            return GestureDetector(
              onTap: _busy
                  ? null
                  : () {
                      setState(() => _selectedMarketKey = market.key);
                      _load(
                        countryCode: market.countryCode,
                        marketKey: market.key,
                      );
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? _Ledger.paperInk
                      : _Ledger.paperDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? _Ledger.paperInk
                        : _Ledger.paperRule,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _providerIcon(market.provider),
                      size: 14,
                      color: selected
                          ? _Ledger.gold
                          : _Ledger.paperFaded,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      market.providerLabel,
                      style: _Ledger.mono(
                        10.5,
                        color: selected
                            ? _Ledger.paper
                            : _Ledger.paperInk,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _stampButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: _Ledger.stamp.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: enabled ? _Ledger.stamp : _Ledger.paperDeep,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        label.toUpperCase(),
                        style: _Ledger.mono(
                          13,
                          color: enabled
                              ? const Color(0xFF171006)
                              : _Ledger.paperFaded,
                          weight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _ledgerMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3D9C8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Ledger.stamp.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: _Ledger.stampDeep, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: _Ledger.body(
                11.5,
                color: _Ledger.stampDeep,
                weight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Selling mode selector ─────────────────────────────────────────────────
  Widget _sellingModeLedger({bool compact = false}) {
    final plan = _selectedPlan();
    final modes = plan?.sellingModes ?? const <String>[];
    if (plan == null) {
      return _counterNote('Choose a plan to select what your business sells.');
    }
    if (modes.isEmpty) {
      return _counterNote(
        'This plan is not available for product or service selling yet.',
      );
    }

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: _Ledger.counterRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Ledger.counterLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT DO YOU SELL?',
            style: _Ledger.mono(
              10.5,
              color: _Ledger.paper.withValues(alpha: 0.5),
              weight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cells = modes.map((mode) {
                final selected = mode == _selectedSellingMode;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: _busy
                          ? null
                          : () => setState(() {
                              _selectedSellingMode = mode;
                              _message = null;
                            }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selected
                              ? _Ledger.paper
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? _Ledger.paper
                                : _Ledger.counterLine,
                            width: selected ? 1.4 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _sellingModeIcon(mode),
                              size: 20,
                              color: selected
                                  ? _Ledger.stampDeep
                                  : _Ledger.paper.withValues(alpha: 0.55),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _sellingModeLabel(mode).toUpperCase(),
                              textAlign: TextAlign.center,
                              style: _Ledger.mono(
                                9.5,
                                weight: FontWeight.w700,
                                letterSpacing: 1,
                                color: selected
                                    ? _Ledger.paperInk
                                    : _Ledger.paper.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList();
              if (compact && modes.length > 2) {
                return Column(
                  children: [
                    Row(children: cells.sublist(0, 2)),
                    const SizedBox(height: 8),
                    Row(children: cells.sublist(2)),
                  ],
                );
              }
              return Row(children: cells);
            },
          ),
        ],
      ),
    );
  }

  // ── A single plan, rendered as a paper receipt ────────────────────────────
  Widget _planReceipt({
    required SubscriptionPlanSummary plan,
    required SubscriptionMarket market,
    required String billingPeriod,
    required bool selected,
    required int index,
  }) {
    final price = plan.priceFor(market, billingPeriod: billingPeriod);
    final isCurrent = plan.code == _currentPlanCode();
    final popular = _isPopularPlan(plan);
    final isFree = _isFreePrice(price);

    return _ReceiptReveal(
      index: index,
      controller: _reveal,
      child: _PlanReceiptCard(
        plan: plan,
        price: price,
        billingPeriod: billingPeriod,
        selected: selected,
        isCurrent: isCurrent,
        popular: popular,
        isFree: isFree,
        busy: _busy,
        features: _featurePreview(plan),
        subtitle: _planSubtitle(plan),
        icon: _planIcon(plan),
        periodLabel: _periodShortLabel(billingPeriod),
        onSelect: () => setState(() {
          _selectedPlanCode = plan.code;
          _selectedSellingMode = _sellingModeForPlan(
            plan,
            _selectedSellingMode,
          );
          _message = null;
        }),
      ),
    );
  }

  Widget _ledgerLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 90),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: _Ledger.mint,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'OPENING THE LEDGER…',
              style: _Ledger.mono(
                11,
                color: _Ledger.paper.withValues(alpha: 0.55),
                weight: FontWeight.w600,
                letterSpacing: 2.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Embedded variant (settings panel) ─────────────────────────────────────
  Widget _buildEmbedded(BuildContext context) {
    if (_loading) {
      return _embeddedShell(_ledgerLoadingEmbedded());
    }
    return _embeddedShell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _controlRow(compact: true),
          const SizedBox(height: 16),
          _receiptRack(compact: true),
          const SizedBox(height: 16),
          _sellingModeLedger(compact: true),
          if (_message != null) ...[
            const SizedBox(height: 14),
            _ledgerMessage(_message!),
          ],
          const SizedBox(height: 16),
          _orderRail(sticky: false),
        ],
      ),
    );
  }

  Widget _embeddedShell(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _Ledger.counter,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _Ledger.counterLine),
      ),
      child: child,
    );
  }

  Widget _ledgerLoadingEmbedded() {
    return const SizedBox(
      height: 220,
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color: _Ledger.mint,
        ),
      ),
    );
  }

  // ── Logic helpers (unchanged behaviour) ───────────────────────────────────
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

  Future<String?> _resolveCountryFallback() async {
    final initial = widget.initialCountryCode?.trim().toUpperCase();
    if (initial != null && initial.isNotEmpty) return initial;
    final detected = await CountryDetector.detect();
    if (detected != null && detected.isNotEmpty) {
      if (mounted) {
        setState(() => _detectedCountryCode = detected.toUpperCase());
      }
      return detected.toUpperCase();
    }
    return null;
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
    if (_busy) return 'Working…';
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

  String _licenseStatusLabel(LicenseAccessStatus status) {
    switch (status) {
      case LicenseAccessStatus.active:
        return 'Active';
      case LicenseAccessStatus.grace:
        return 'Grace period';
      case LicenseAccessStatus.expired:
        return 'Expired';
      case LicenseAccessStatus.invalid:
        return 'Needs refresh';
      case LicenseAccessStatus.localOnly:
        return 'Local only';
    }
  }

  String _sellingModeLabel(String mode) {
    switch (mode) {
      case 'services':
        return 'Services only';
      case 'restaurant':
        return 'Restaurant';
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
      case 'restaurant':
        return Icons.restaurant_outlined;
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
}

/// ───────────────────────────────────────────────────────────────────────────
/// Receipt building blocks
/// ───────────────────────────────────────────────────────────────────────────

/// Staggered entrance for a receipt on the rack.
class _ReceiptReveal extends StatelessWidget {
  final int index;
  final AnimationController controller;
  final Widget child;

  const _ReceiptReveal({
    required this.index,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.09).clamp(0.0, 0.5);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.55).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.16),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// A paper receipt with perforated top and bottom edges. The perforation is a
/// real zig-zag clip, so the counter colour shows through the teeth.
class _PaperReceipt extends StatelessWidget {
  final Widget child;

  const _PaperReceipt({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _PerforatedClipper(tooth: 7),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _Ledger.paper),
        child: child,
      ),
    );
  }
}

class _PerforatedClipper extends CustomClipper<Path> {
  final double tooth;

  _PerforatedClipper({required this.tooth});

  @override
  Path getClip(Size size) {
    final path = Path();
    final count = (size.width / (tooth * 2)).ceil();
    final step = size.width / count;

    path.moveTo(0, tooth);
    for (var i = 0; i < count; i++) {
      final x = i * step;
      path.lineTo(x + step / 2, 0);
      path.lineTo(x + step, tooth);
    }
    path.lineTo(size.width, size.height - tooth);
    for (var i = count - 1; i >= 0; i--) {
      final x = i * step;
      path.lineTo(x + step / 2, size.height);
      path.lineTo(x, size.height - tooth);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_PerforatedClipper old) => old.tooth != tooth;
}

class _DashedRule extends StatelessWidget {
  final Color color;

  const _DashedRule({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 6.0;
        const gap = 5.0;
        const height = 1.4;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => SizedBox(
              width: dash,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A decorative barcode derived from a seed so each plan gets its own.
class _BarcodeStrip extends StatelessWidget {
  final int seed;

  const _BarcodeStrip({required this.seed});

  @override
  Widget build(BuildContext context) {
    final random = math.Random(seed);
    return SizedBox(
      height: 34,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bars = <Widget>[];
          var x = 0.0;
          while (x < constraints.maxWidth - 4) {
            final wide = random.nextBool();
            final width = wide ? 3.0 : 1.4;
            bars.add(
              Container(
                width: width,
                color: _Ledger.paperInk.withValues(
                  alpha: random.nextBool() ? 0.9 : 0.65,
                ),
              ),
            );
            x += width + (random.nextBool() ? 2.6 : 1.4);
            bars.add(const SizedBox(width: 2));
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: bars,
          );
        },
      ),
    );
  }
}

/// The rubber-stamp "SELECTED" mark that appears on the chosen receipt.
class _StampMark extends StatefulWidget {
  const _StampMark();

  @override
  State<_StampMark> createState() => _StampMarkState();
}

class _StampMarkState extends State<_StampMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.6, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      ),
      child: FadeTransition(
        opacity: _controller,
        child: Transform.rotate(
          angle: -0.14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: _Ledger.stamp, width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'SELECTED',
              style: _Ledger.mono(
                10,
                color: _Ledger.stamp,
                weight: FontWeight.w700,
                letterSpacing: 2.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single plan rendered as a paper receipt card.
class _PlanReceiptCard extends StatefulWidget {
  final SubscriptionPlanSummary plan;
  final SubscriptionPlanPrice? price;
  final String billingPeriod;
  final bool selected;
  final bool isCurrent;
  final bool popular;
  final bool isFree;
  final bool busy;
  final List<String> features;
  final String subtitle;
  final IconData icon;
  final String periodLabel;
  final VoidCallback onSelect;

  const _PlanReceiptCard({
    required this.plan,
    required this.price,
    required this.billingPeriod,
    required this.selected,
    required this.isCurrent,
    required this.popular,
    required this.isFree,
    required this.busy,
    required this.features,
    required this.subtitle,
    required this.icon,
    required this.periodLabel,
    required this.onSelect,
  });

  @override
  State<_PlanReceiptCard> createState() => _PlanReceiptCardState();
}

class _PlanReceiptCardState extends State<_PlanReceiptCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0.0,
            selected ? -6.0 : (_hovered ? -3.0 : 0.0),
            0.0,
          ),
          transformAlignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: selected ? 0.42 : (_hovered ? 0.32 : 0.24),
                ),
                blurRadius: selected ? 30 : 20,
                offset: Offset(0, selected ? 16 : 10),
              ),
              if (selected)
                BoxShadow(
                  color: _Ledger.stamp.withValues(alpha: 0.28),
                  blurRadius: 34,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _PaperReceipt(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            widget.icon,
                            size: 18,
                            color: selected
                                ? _Ledger.stampDeep
                                : _Ledger.paperFaded,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.plan.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _Ledger.mono(
                                12.5,
                                color: _Ledger.paperInk,
                                weight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          if (widget.isCurrent)
                            _miniTag('CURRENT', _Ledger.mint),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _Ledger.body(
                          11.5,
                          color: _Ledger.paperFaded,
                          weight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DashedRule(color: _Ledger.paperRule),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(
                                key: ValueKey(widget.price?.displayAmount),
                                widget.price?.displayAmount ?? '—',
                                style: _Ledger.mono(
                                  27,
                                  color: _Ledger.paperInk,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '/${widget.periodLabel}',
                              style: _Ledger.mono(
                                11,
                                color: _Ledger.paperFaded,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.isFree)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'NO CARD REQUIRED',
                            style: _Ledger.mono(
                              9,
                              color: _Ledger.mint.withValues(alpha: 0.9),
                              weight: FontWeight.w700,
                              letterSpacing: 1.8,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _DashedRule(color: _Ledger.paperRule),
                      const SizedBox(height: 14),
                      ...widget.features.map(
                        (feature) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '▸',
                                style: _Ledger.mono(
                                  11,
                                  color: selected
                                      ? _Ledger.stampDeep
                                      : _Ledger.paperFaded,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  UserAccessProfile.featureLabel(feature),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _Ledger.body(
                                    12,
                                    color: _Ledger.paperInk.withValues(
                                      alpha: 0.85,
                                    ),
                                    weight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _receiptFooter(selected),
                    ],
                  ),
                ),
              ),
              if (widget.popular && !widget.isCurrent)
                Positioned(
                  top: -11,
                  left: 16,
                  child: Transform.rotate(
                    angle: -0.03,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _Ledger.gold,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        'BEST VALUE',
                        style: _Ledger.mono(
                          9,
                          color: const Color(0xFF3A2C07),
                          weight: FontWeight.w700,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  top: 14,
                  right: 12,
                  child: _StampMark(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptFooter(bool selected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      height: 42,
      decoration: BoxDecoration(
        color: selected ? _Ledger.paperInk : _Ledger.paperDeep,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? _Ledger.paperInk : _Ledger.paperRule,
        ),
      ),
      child: Center(
        child: Text(
          selected
              ? 'ON THE COUNTER'
              : (widget.isFree ? 'START FREE' : 'ADD TO ORDER'),
          style: _Ledger.mono(
            10.5,
            color: selected ? _Ledger.paper : _Ledger.paperInk,
            weight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
        ),
      ),
    );
  }

  Widget _miniTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: _Ledger.mono(
          8.5,
          color: color.withValues(alpha: 0.95),
          weight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// Anchored dropdown listing the selectable markets (countries).
class _CountryPickerOverlay extends StatelessWidget {
  final LayerLink link;
  final List<SubscriptionCountry> countries;
  final String? selectedCode;
  final String Function(String) flagFor;
  final ValueChanged<SubscriptionCountry> onPick;
  final VoidCallback onDismiss;

  const _CountryPickerOverlay({
    required this.link,
    required this.countries,
    required this.selectedCode,
    required this.flagFor,
    required this.onPick,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          offset: const Offset(0, 62),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 288,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _Ledger.counterRaised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _Ledger.counterLine),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                      child: Text(
                        'SELECT MARKET',
                        style: _Ledger.mono(
                          9.5,
                          color: _Ledger.paper.withValues(alpha: 0.45),
                          weight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    for (final country in countries)
                      _CountryRow(
                        country: country,
                        flag: flagFor(country.countryCode),
                        selected: country.countryCode == selectedCode,
                        onTap: () => onPick(country),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountryRow extends StatefulWidget {
  final SubscriptionCountry country;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  const _CountryRow({
    required this.country,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_CountryRow> createState() => _CountryRowState();
}

class _CountryRowState extends State<_CountryRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? _Ledger.paper.withValues(alpha: 0.1)
                : (_hovered ? _Ledger.paper.withValues(alpha: 0.05) : Colors.transparent),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? _Ledger.stamp.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Text(widget.flag, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.country.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _Ledger.display(
                        14,
                        color: _Ledger.paper,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.country.currency.toUpperCase(),
                      style: _Ledger.mono(
                        9,
                        color: _Ledger.paper.withValues(alpha: 0.45),
                        weight: FontWeight.w600,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: _Ledger.stamp,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
