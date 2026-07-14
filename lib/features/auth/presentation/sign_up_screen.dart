import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/cloud_auth_service.dart';
import '../../../core/services/country_detector.dart';
import '../../../core/services/local_business_reset_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/piki_mark.dart';
import '../../app/app_shell.dart';
import '../../onboarding/presentation/business_setup_wizard_screen.dart';
import '../data/auth_password_service.dart';
import '../data/user_repository.dart';
import '../../settings/presentation/subscription_screen.dart';
import 'login_screen.dart';

const _reservedStoreLinks = {
  'admin',
  'api',
  'app',
  'assets',
  'cdn',
  'help',
  'mail',
  'pikipos',
  'shop',
  'status',
  'store',
  'support',
  'www',
};

String signupStoreSlugPreview(String businessName) {
  var slug = businessName
      .trim()
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) slug = 'your-business';
  if (RegExp(r'^\d+$').hasMatch(slug)) slug = 'shop-$slug';
  if (_reservedStoreLinks.contains(slug)) slug = '$slug-shop';
  if (slug.length > 48) {
    slug = slug.substring(0, 48).replaceAll(RegExp(r'-+$'), '');
  }
  return slug;
}

class SignUpScreen extends StatefulWidget {
  final String initialRole;

  const SignUpScreen({super.key, this.initialRole = 'ADMIN'});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _businessNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailOtpController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingCatalog = false;
  String? _error;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  SubscriptionCatalog? _catalog;
  String? _selectedMarketKey;
  Country _selectedCountry = Country.parse('KE');
  String _selectedSellingMode = 'products';
  String _selectedCurrency = 'KSh';
  int _currentStep = 0;
  String? _emailOtpSentToEmail;
  String? _verifiedEmail;
  String? _emailVerificationToken;
  DateTime? _emailOtpExpiresAt;

  bool get _isBusinessSetupFlow => widget.initialRole.toUpperCase() == 'ADMIN';

  static const _sellingModeOrder = ['products', 'services', 'combo'];

  SubscriptionMarket? get _selectedMarket {
    final catalog = _catalog;
    if (catalog == null) return null;
    for (final market in catalog.markets) {
      if (market.key == _selectedMarketKey) return market;
    }
    return catalog.selectedMarket ??
        (catalog.markets.isEmpty ? null : catalog.markets.first);
  }

  List<String> _availableSellingModesForMarket(
    SubscriptionCatalog catalog,
    SubscriptionMarket? market,
  ) {
    if (market == null) return const [];
    final modes = <String>[];
    for (final mode in _sellingModeOrder) {
      final supported = catalog.plans.any((plan) {
        final price = plan.priceFor(market);
        return plan.sellingModes.contains(mode) &&
            price != null &&
            (price.amountMinor == 0 || market.paymentActive);
      });
      if (supported) {
        modes.add(mode);
      }
    }
    return modes;
  }

  SubscriptionPlanSummary? _signupPlanForSellingMode(
    SubscriptionCatalog? catalog,
    SubscriptionMarket? market,
    String mode,
  ) {
    if (catalog == null || market == null) return null;
    SubscriptionPlanSummary? firstMatch;
    for (final plan in catalog.plans) {
      final price = plan.priceFor(market);
      if (price == null || !plan.sellingModes.contains(mode)) {
        continue;
      }
      if (price.amountMinor > 0 && !market.paymentActive) {
        continue;
      }
      firstMatch ??= plan;
      if (price.amountMinor == 0) {
        return plan;
      }
    }
    return firstMatch;
  }

  String _preferredSellingModeForMarket(
    SubscriptionCatalog catalog,
    SubscriptionMarket? market,
  ) {
    final modes = _availableSellingModesForMarket(catalog, market);
    if (modes.contains(_selectedSellingMode)) {
      return _selectedSellingMode;
    }
    return modes.isEmpty ? 'products' : modes.first;
  }

  @override
  void initState() {
    super.initState();
    _businessNameController.addListener(_refreshStoreLinkPreview);
    _emailController.addListener(_clearEmailVerificationIfEmailChanged);
    if (_isBusinessSetupFlow) {
      _loadSubscriptionCatalog();
    }
    _applyDetectedCountry();
  }

  Future<void> _applyDetectedCountry() async {
    final detected = await CountryDetector.detect();
    if (detected == null || detected.toUpperCase() == 'KE') return;
    if (!mounted) return;
    final parsed = Country.parse(detected);
    setState(() {
      _selectedCountry = parsed;
      _selectedCurrency = ShopSettings.suggestedCurrencyForCountry(detected);
      _selectedMarketKey = null;
    });
    if (_isBusinessSetupFlow) {
      _loadSubscriptionCatalog();
    }
  }

  void _refreshStoreLinkPreview() {
    if (mounted) setState(() {});
  }

  void _clearEmailVerificationIfEmailChanged() {
    final email = _normalizedSignupEmail;
    if ((_emailOtpSentToEmail == null || _emailOtpSentToEmail == email) &&
        (_verifiedEmail == null || _verifiedEmail == email) &&
        _emailVerificationToken == null) {
      return;
    }
    if (_emailOtpSentToEmail == email && _verifiedEmail == email) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _emailOtpSentToEmail = null;
      _verifiedEmail = null;
      _emailVerificationToken = null;
      _emailOtpExpiresAt = null;
      _emailOtpController.clear();
    });
  }

  String get _normalizedSignupEmail =>
      _emailController.text.trim().toLowerCase();

  String get _storeLinkPreview {
    final slug = signupStoreSlugPreview(_businessNameController.text);
    return '$slug.pikipos.com';
  }

  bool _validateBusinessStep() {
    if (_businessNameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter your business name to continue.');
      return false;
    }
    if (_isLoadingCatalog) {
      setState(() => _error = 'Please wait while business options load.');
      return false;
    }
    final market = _selectedMarket;
    if (market == null) {
      setState(() => _error = 'Choose a country with an available plan.');
      return false;
    }
    if (_signupPlanForSellingMode(_catalog, market, _selectedSellingMode) ==
        null) {
      setState(
        () => _error =
            'Choose a business type that is available for this country.',
      );
      return false;
    }
    return true;
  }

  bool _validateAccountStep() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      setState(() => _error = 'Complete all account details to continue.');
      return false;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Enter a valid email address.');
      return false;
    }
    if (phone.length < 7) {
      setState(() => _error = 'Enter a valid phone number.');
      return false;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return false;
    }
    if (password != confirmPassword) {
      setState(() => _error = 'Passwords do not match.');
      return false;
    }
    return true;
  }

  Future<void> _continueWizard() async {
    final valid = switch (_currentStep) {
      0 => _validateBusinessStep(),
      1 => _validateAccountStep(),
      2 => _validateEmailOtpStep(),
      _ => true,
    };
    if (!valid) return;
    if (_currentStep == 1) {
      await _sendSignupOtp();
      return;
    }
    if (_currentStep == 2) {
      await _verifySignupOtp();
      return;
    }
    setState(() {
      _error = null;
      _currentStep = (_currentStep + 1).clamp(0, 3);
    });
  }

  void _previousWizardStep() {
    setState(() {
      _error = null;
      _currentStep = (_currentStep - 1).clamp(0, 3);
    });
  }

  bool _validateEmailOtpStep() {
    final code = _emailOtpController.text.replaceAll(RegExp(r'\D'), '');
    if (_emailOtpSentToEmail != _normalizedSignupEmail) {
      setState(() => _error = 'Send a fresh code to this email first.');
      return false;
    }
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6 digit code from your email.');
      return false;
    }
    return true;
  }

  Future<String> _resolveSignupBackendUrl() async {
    await SyncSettingsService.init();
    final backendUrl =
        _catalog?.backendUrl ??
        await SubscriptionService.resolveReachableBackendUrl();

    if (backendUrl.isEmpty) {
      throw Exception(
        'Cloud backend is not configured. Contact your administrator.',
      );
    }
    return backendUrl;
  }

  Future<void> _sendSignupOtp() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final email = _normalizedSignupEmail;
      final backendUrl = await _resolveSignupBackendUrl();
      final response = await CloudAuthService.requestSignupEmailOtp(
        backendUrl: backendUrl,
        email: email,
      );
      if (!mounted) return;
      setState(() {
        _emailOtpSentToEmail = email;
        _verifiedEmail = null;
        _emailVerificationToken = null;
        _emailOtpExpiresAt = response.expiresAt;
        _emailOtpController.clear();
        _currentStep = 2;
        _error = response.sent
            ? null
            : 'A code was already sent. Try again in ${response.retryAfterSeconds ?? 60} seconds.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = AppErrorMessage.from(
          error,
          fallback: 'Could not send verification code. Please try again.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifySignupOtp() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final email = _normalizedSignupEmail;
      final backendUrl = await _resolveSignupBackendUrl();
      final response = await CloudAuthService.verifySignupEmailOtp(
        backendUrl: backendUrl,
        email: email,
        code: _emailOtpController.text,
      );
      if (response.verificationToken.isEmpty) {
        throw Exception('Email verification did not return a token.');
      }
      if (!mounted) return;
      setState(() {
        _verifiedEmail = email;
        _emailVerificationToken = response.verificationToken;
        _emailOtpExpiresAt = response.expiresAt;
        _currentStep = 3;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = AppErrorMessage.from(
          error,
          fallback: 'Could not verify the code. Please try again.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSubscriptionCatalog() async {
    setState(() => _isLoadingCatalog = true);
    try {
      await SyncSettingsService.init();
      final catalog = await SubscriptionService.fetchPlans(
        countryCode: _selectedCountry.countryCode,
      );
      final market = _preferredMarket(catalog);
      final catalogMessage = market == null
          ? 'No subscription markets are active yet. In Super Admin, enable at least one country price or payment gateway.'
          : null;
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _selectedMarketKey = market?.key;
        _selectedSellingMode = _preferredSellingModeForMarket(catalog, market);
        _selectedCurrency = ShopSettings.suggestedCurrencyForCountry(
          _selectedCountry.countryCode,
        );
        _error = catalogMessage;
        _isLoadingCatalog = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMessage.withContext(
          error,
          prefix: 'Could not load subscription plans.',
          fallback: AppErrorMessage.loadFailed,
        );
        _isLoadingCatalog = false;
      });
    }
  }

  SubscriptionMarket? _preferredMarket(SubscriptionCatalog catalog) {
    if (catalog.markets.isEmpty) return null;
    final preferredProvider = SubscriptionService.currentPlatform == 'windows'
        ? (_selectedCountry.countryCode == 'KE' ? 'flutterwave' : 'paypal')
        : 'google_play';
    return catalog.markets
            .where((market) => market.provider == preferredProvider)
            .firstOrNull ??
        catalog.selectedMarket ??
        catalog.markets.first;
  }

  Future<void> _selectCountry() async {
    showCountryPicker(
      context: context,
      favorite: const ['KE', 'US', 'GB', 'CA', 'AU', 'ZA', 'NG', 'TZ', 'UG'],
      showPhoneCode: false,
      countryListTheme: CountryListThemeData(
        textStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        searchTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        inputDecoration: InputDecoration(
          labelText: 'Search country',
          prefixIcon: Icon(Icons.search),
        ),
        bottomSheetHeight: MediaQuery.sizeOf(context).height * 0.75,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      onSelect: (country) {
        setState(() {
          _selectedCountry = country;
          _selectedCurrency = ShopSettings.suggestedCurrencyForCountry(
            country.countryCode,
          );
          _selectedMarketKey = null;
        });
        _loadSubscriptionCatalog();
      },
    );
  }

  String? _readInitialPlanCode(CloudAuthResponse response) {
    final checkoutContext = response.checkoutContext;
    final checkoutPlan = checkoutContext?['planCode']?.toString().trim();
    if (checkoutPlan != null && checkoutPlan.isNotEmpty) {
      return checkoutPlan;
    }
    final selectedPlan = response.selectedPlan['code']?.toString().trim();
    return selectedPlan == null || selectedPlan.isEmpty ? null : selectedPlan;
  }

  void _goToSignIn() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _signUp() async {
    final businessName = _businessNameController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if ((_isBusinessSetupFlow && businessName.isEmpty) ||
        name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      setState(() => _error = 'Please fill in all required fields.');
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    if (phone.length < 7) {
      setState(() => _error = 'Enter a valid phone number.');
      return;
    }

    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    if (password != confirmPassword) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    final market = _selectedMarket;
    if (_isBusinessSetupFlow && market == null) {
      setState(() => _error = 'Choose your country.');
      return;
    }
    final signupPlan = _isBusinessSetupFlow
        ? _signupPlanForSellingMode(_catalog, market, _selectedSellingMode)
        : null;
    if (_isBusinessSetupFlow && signupPlan == null) {
      setState(
        () => _error =
            'Choose a business type that is available for this country.',
      );
      return;
    }
    if (_isBusinessSetupFlow &&
        (_verifiedEmail != email || _emailVerificationToken == null)) {
      setState(() => _error = 'Verify your email before creating account.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final backendUrl = await _resolveSignupBackendUrl();

      // Protect the existing business before the registration request creates
      // and binds a new cloud account. The candidate ID is not persisted until
      // registration succeeds, so a rejected request cannot break the current
      // account's device binding.
      await LocalBusinessResetService.prepareForBusinessSwitch();
      final deviceId = SyncSettingsService.generateFreshDeviceId();

      final response = await CloudAuthService.registerOnline(
        backendUrl: backendUrl,
        businessName: businessName,
        ownerName: name,
        ownerEmail: email,
        phone: phone,
        password: password,
        deviceId: deviceId,
        countryCode: _selectedCountry.countryCode,
        currency: _selectedCurrency,
        requestedPlanCode: signupPlan?.code,
        sellingMode: _isBusinessSetupFlow ? _selectedSellingMode : null,
        provider: market?.provider,
        platform: SubscriptionService.currentPlatform,
        emailVerificationToken: _emailVerificationToken,
      );

      final incomingBusinessId = ((response.business['id'] as String?) ?? '')
          .trim();
      final incomingBusinessName =
          ((response.business['name'] as String?) ?? '').trim();

      if (_isBusinessSetupFlow) {
        await LocalBusinessResetService.clearForBusinessSwitch();
      }

      if (backendUrl != SyncSettingsService.backendUrl) {
        await SyncSettingsService.setBackendUrl(backendUrl);
      }
      await SyncSettingsService.setDeviceId(deviceId);

      final user = response.user;
      final localUser = await UserRepository.upsertCloudAuthenticatedUser(
        cloudUser: user,
        fallbackEmail: email,
        passwordHash: AuthPasswordService.hashPassword(password),
      );

      await CloudAuthService.persistCloudResponse(response);
      if (incomingBusinessId.isNotEmpty) {
        await SyncSettingsService.setLocalBusinessId(incomingBusinessId);
      }

      if (_isBusinessSetupFlow) {
        await ShopSettings.init();
        await ShopSettings.setShopName(
          incomingBusinessName.isNotEmpty ? incomingBusinessName : businessName,
        );
        await ShopSettings.setShopPhone(phone);
        await ShopSettings.setShopEmail(email);
        await ShopSettings.setCurrency(_selectedCurrency);
      }

      await SessionService.signIn(localUser);

      if (!mounted) return;

      final destination = _isBusinessSetupFlow
          ? SubscriptionScreen(
              afterSignup: true,
              initialCountryCode: _selectedCountry.countryCode,
              initialProvider: market?.provider,
              initialPlanCode: _readInitialPlanCode(response),
            )
          : AppShell(key: AppShell.shellKey);
      final registrationDestination = _isBusinessSetupFlow
          ? BusinessSetupWizardScreen(
              businessId: incomingBusinessId,
              businessName: incomingBusinessName.isNotEmpty
                  ? incomingBusinessName
                  : businessName,
              planCode: signupPlan?.code ?? _readInitialPlanCode(response),
              planName: signupPlan?.name,
              planFeatures: signupPlan?.features ?? const [],
              initialSellingFocus: _selectedSellingMode,
              destination: destination,
            )
          : destination;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => registrationDestination),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = AppErrorMessage.from(
          error,
          fallback: 'Could not create your account. Please try again.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSubscriptionChooser() {
    if (_isLoadingCatalog) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(minHeight: 2),
          SizedBox(height: 12),
          Text(
            'Loading available countries...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    final catalog = _catalog;
    if (catalog == null || catalog.markets.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (catalog != null && catalog.markets.isEmpty) ...[
            Text(
              'No subscription markets are active.',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
            SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _loadSubscriptionCatalog,
            icon: Icon(Icons.refresh),
            label: Text('Load subscription plans'),
          ),
        ],
      );
    }

    final market = _selectedMarket;
    final modes = _availableSellingModesForMarket(catalog, market);
    final signupPlan = _signupPlanForSellingMode(
      catalog,
      market,
      _selectedSellingMode,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Country',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        SizedBox(height: 8),
        InkWell(
          onTap: _isLoading ? null : _selectCountry,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: _GradientIcon(Icons.public_outlined),
              suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
            ),
            child: Row(
              children: [
                Text(
                  _selectedCountry.flagEmoji,
                  style: TextStyle(fontSize: 24),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${_selectedCountry.name} (${_selectedCountry.countryCode})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (market != null) ...[
          SizedBox(height: 8),
          Text(
            SubscriptionService.currentPlatform == 'android'
                ? 'Subscriptions are billed securely through Google Play.'
                : '${market.providerLabel} will be selected first. You can switch payment method on the plans screen.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
        SizedBox(height: 20),
        Text(
          'Display Currency',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(_selectedCurrency),
          initialValue: _selectedCurrency,
          decoration: InputDecoration(
            prefixIcon: _GradientIcon(Icons.currency_exchange_outlined),
          ),
          items: ShopSettings.currencyOptions
              .map(
                (currency) => DropdownMenuItem(
                  value: currency.prefix,
                  child: Text(currency.label),
                ),
              )
              .toList(),
          onChanged: _isLoading
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _selectedCurrency = value);
                  }
                },
        ),
        SizedBox(height: 20),
        Text(
          'Business Type',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        SizedBox(height: 8),
        if (modes.isEmpty)
          Text(
            'No business types are available for this country yet.',
            style: TextStyle(color: AppColors.error, fontSize: 12),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: modes.map((mode) {
              return ChoiceChip(
                selected: _selectedSellingMode == mode,
                avatar: Icon(_sellingModeIcon(mode), size: 18),
                label: Text(_sellingModeLabel(mode)),
                onSelected: _isLoading
                    ? null
                    : (_) => setState(() => _selectedSellingMode = mode),
              );
            }).toList(),
          ),
        SizedBox(height: 12),
        Text(
          market == null || signupPlan == null
              ? 'Your plan will be selected after account creation.'
              : 'Your account starts with ${_sellingModeLabel(_selectedSellingMode)} on ${signupPlan.name}. You can adjust the plan after creating the account.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
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

  @override
  void dispose() {
    _businessNameController.removeListener(_refreshStoreLinkPreview);
    _emailController.removeListener(_clearEmailVerificationIfEmailChanged);
    _businessNameController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailOtpController.dispose();
    super.dispose();
  }

  Widget _buildWizardProgress() {
    const steps = [
      ('Business', Icons.storefront_outlined),
      ('Your account', Icons.person_outline_rounded),
      ('Verify email', Icons.mark_email_read_outlined),
      ('Review', Icons.fact_check_outlined),
    ];

    return Row(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isActive = index == _currentStep;
        final isComplete = index < _currentStep;
        final color = isActive || isComplete
            ? AppColors.primary
            : Theme.of(context).colorScheme.onSurfaceVariant;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary
                            : isComplete
                            ? AppColors.success.withValues(alpha: 0.16)
                            : context.appSurfaceHighlight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive || isComplete
                              ? color
                              : context.appBorder,
                        ),
                      ),
                      child: Icon(
                        isComplete ? Icons.check_rounded : step.$2,
                        size: 19,
                        color: isActive ? Colors.white : color,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      step.$1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isActive
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (index < steps.length - 1)
                Container(
                  width: 28,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 22),
                  color: isComplete ? AppColors.success : context.appBorder,
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepHeading(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 6),
        Text(
          description,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessStep() {
    return Column(
      key: const ValueKey('signup-business-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepHeading(
          'Tell us about your business',
          'We use this to prepare your POS, currency, billing method, and online catalog.',
        ),
        SizedBox(height: 24),
        Text(
          'Business Name',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        SizedBox(height: 8),
        TextField(
          key: const Key('signup-business-name'),
          controller: _businessNameController,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'Example: Amina Fashion',
            prefixIcon: _GradientIcon(Icons.storefront_outlined),
          ),
        ),
        SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.secondary.withValues(alpha: 0.09),
                AppColors.primary.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _GradientIcon(Icons.language_rounded, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your online store link',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 3),
                    SelectableText(
                      _storeLinkPreview,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'If this link is already used, Piki POS adds a short unique code automatically.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 24),
        _buildSubscriptionChooser(),
      ],
    );
  }

  Widget _buildAccountStep() {
    return Column(
      key: const ValueKey('signup-account-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isBusinessSetupFlow) ...[
          _buildStepHeading(
            'Create your owner account',
            'These details let you sign in and recover access to your business.',
          ),
          SizedBox(height: 24),
        ],
        Text(
          'Full Name',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        SizedBox(height: 8),
        TextField(
          key: const Key('signup-full-name'),
          controller: _nameController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'Enter your full name',
            prefixIcon: _GradientIcon(Icons.person_outline),
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Phone Number',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        SizedBox(height: 8),
        TextField(
          key: const Key('signup-phone'),
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'Enter your phone number',
            prefixIcon: _GradientIcon(Icons.phone_outlined),
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Email',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        SizedBox(height: 8),
        TextField(
          key: const Key('signup-email'),
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'Enter your email',
            prefixIcon: _GradientIcon(Icons.email_outlined),
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Password',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        SizedBox(height: 8),
        TextField(
          key: const Key('signup-password'),
          controller: _passwordController,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'At least 6 characters',
            prefixIcon: const _GradientIcon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        SizedBox(height: 18),
        Text(
          'Confirm Password',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        SizedBox(height: 8),
        TextField(
          key: const Key('signup-confirm-password'),
          controller: _confirmPasswordController,
          obscureText: !_showConfirmPassword,
          onSubmitted: (_) =>
              _isBusinessSetupFlow ? _continueWizard() : _signUp(),
          decoration: InputDecoration(
            hintText: 'Enter the same password again',
            prefixIcon: const _GradientIcon(Icons.lock_reset_outlined),
            suffixIcon: IconButton(
              tooltip: _showConfirmPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showConfirmPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () =>
                  setState(() => _showConfirmPassword = !_showConfirmPassword),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailVerificationStep() {
    final email = _emailOtpSentToEmail ?? _normalizedSignupEmail;
    final expiryText = _formatOtpExpiry(_emailOtpExpiresAt);
    return Column(
      key: const ValueKey('signup-email-otp-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepHeading(
          'Verify your email',
          'We sent a 6 digit code to $email. Enter it here to protect your business account.',
        ),
        SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const _GradientIcon(Icons.mail_outline_rounded, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  expiryText == null
                      ? 'Check your inbox and spam folder for the Piki POS code.'
                      : 'Check your inbox and spam folder. $expiryText',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20),
        Text(
          'Verification Code',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        SizedBox(height: 8),
        TextField(
          key: const Key('signup-email-otp'),
          controller: _emailOtpController,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _continueWizard(),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Enter 6 digit code',
            prefixIcon: _GradientIcon(Icons.password_outlined),
          ),
        ),
        SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _sendSignupOtp,
          icon: Icon(Icons.refresh_rounded),
          label: Text('Resend code'),
        ),
      ],
    );
  }

  String? _formatOtpExpiry(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final local = expiresAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Code expires at $hour:$minute.';
  }

  Widget _buildReviewStep() {
    final market = _selectedMarket;
    final plan = _signupPlanForSellingMode(
      _catalog,
      market,
      _selectedSellingMode,
    );
    return Column(
      key: const ValueKey('signup-review-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepHeading(
          'Review and create your account',
          'Check the important details below. You can go back to make changes.',
        ),
        SizedBox(height: 22),
        _ReviewCard(
          title: 'Business',
          icon: Icons.storefront_outlined,
          rows: [
            ('Name', _businessNameController.text.trim()),
            ('Store link', _storeLinkPreview),
            (
              'Country',
              '${_selectedCountry.flagEmoji} ${_selectedCountry.name}',
            ),
            ('Business type', _sellingModeLabel(_selectedSellingMode)),
            ('Currency', _selectedCurrency),
          ],
          onEdit: () => setState(() {
            _error = null;
            _currentStep = 0;
          }),
        ),
        SizedBox(height: 12),
        _ReviewCard(
          title: 'Owner account',
          icon: Icons.person_outline_rounded,
          rows: [
            ('Name', _nameController.text.trim()),
            (
              'Email',
              _verifiedEmail == _normalizedSignupEmail
                  ? '$_normalizedSignupEmail (verified)'
                  : _normalizedSignupEmail,
            ),
            ('Phone', _phoneController.text.trim()),
          ],
          onEdit: () => setState(() {
            _error = null;
            _currentStep = 1;
          }),
        ),
        SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Row(
            children: [
              const _GradientIcon(Icons.credit_card_outlined, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  SubscriptionService.currentPlatform == 'android'
                      ? 'Plan: ${plan?.name ?? 'Available plan'} • Billing: Google Play'
                      : 'Plan: ${plan?.name ?? 'Available plan'} • Billing: ${market?.providerLabel ?? 'Selected after signup'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWizardActions() {
    final isReview = _currentStep == 3;
    final actionLabel = isReview
        ? 'Create my account'
        : _currentStep == 1
        ? 'Send verification code'
        : _currentStep == 2
        ? 'Verify email'
        : 'Continue';
    return Row(
      children: [
        if (_currentStep > 0) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _isLoading ? null : _previousWizardStep,
              child: Text('Back'),
            ),
          ),
          SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: ElevatedButton(
            key: Key(isReview ? 'signup-submit' : 'signup-continue'),
            onPressed: _isLoading
                ? null
                : isReview
                ? _signUp
                : _continueWizard,
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(actionLabel),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 520;
    final form = SingleChildScrollView(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 560),
        margin: EdgeInsets.all(compact ? 14 : 24),
        padding: EdgeInsets.all(compact ? 24 : 36),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outline),
          boxShadow: [
            ...context.appPanelShadow,
            if (!context.isDarkMode)
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.08),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: PikiMark(size: 72, showShadow: true),
            ),
            SizedBox(height: 28),
            Text(
              _isBusinessSetupFlow ? 'Set up Piki POS' : 'Create Staff Account',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              _isBusinessSetupFlow
                  ? 'A guided setup for your business and owner account'
                  : 'Create a new team member account',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: 18),

            if (_isBusinessSetupFlow)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    _GradientIcon(Icons.cloud_outlined, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Internet connection required for account creation.',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isBusinessSetupFlow) ...[
              _buildWizardProgress(),
              SizedBox(height: 28),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_currentStep) {
                  0 => _buildBusinessStep(),
                  1 => _buildAccountStep(),
                  2 => _buildEmailVerificationStep(),
                  _ => _buildReviewStep(),
                },
              ),
              SizedBox(height: 28),
              _buildWizardActions(),
            ] else ...[
              _buildAccountStep(),
              SizedBox(height: 28),
              ElevatedButton(
                onPressed: _isLoading ? null : _signUp,
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Create Account'),
              ),
            ],
            SizedBox(height: 16),
            TextButton(
              onPressed: _isLoading ? null : _goToSignIn,
              child: Text('Back to sign in'),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return Row(
              children: [
                Expanded(flex: 5, child: const _SignUpStoryPanel()),
                Expanded(flex: 4, child: Center(child: form)),
              ],
            );
          } else {
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: theme.scaffoldBackgroundColor),
                Positioned(
                  right: -82,
                  top: -94,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.07),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: -72,
                  bottom: -86,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Center(child: form),
              ],
            );
          }
        },
      ),
    );
  }
}

class _SignUpStoryPanel extends StatelessWidget {
  const _SignUpStoryPanel();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.ink,
      child: Stack(
        children: [
          Positioned(
            right: -110,
            top: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandCoral.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            right: 70,
            top: 124,
            child: Container(
              width: 15,
              height: 15,
              decoration: const BoxDecoration(
                color: AppColors.signal,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 96)
                        .clamp(0.0, double.infinity)
                        .toDouble(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          PikiMark(size: 58),
                          SizedBox(width: 14),
                          Text(
                            'Piki',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: constraints.maxHeight > 700 ? 126 : 68),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SET UP ONCE. TRADE WITH CONFIDENCE.',
                              style: TextStyle(
                                color: AppColors.darkAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Start with the shop\nyou already know.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Tell Piki the essentials. You can refine branches, payments, stock, and roles whenever the business grows.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 16,
                                height: 1.55,
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _SignUpPoint(label: 'Business'),
                                _SignUpPoint(label: 'Owner'),
                                _SignUpPoint(label: 'Ready to trade'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _SignUpPoint extends StatelessWidget {
  final String label;

  const _SignUpPoint({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.signal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const _GradientIcon(this.icon, {this.size = 24});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          Theme.of(context).colorScheme.secondary,
          AppColors.primaryLight,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<(String, String)> rows;
  final VoidCallback onEdit;

  const _ReviewCard({
    required this.title,
    required this.icon,
    required this.rows,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _GradientIcon(icon, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(onPressed: onEdit, child: Text('Edit')),
            ],
          ),
          Divider(height: 22, color: Theme.of(context).colorScheme.outline),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 105,
                    child: Text(
                      row.$1,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
