import 'package:flutter/material.dart';

import '../../../core/services/cloud_auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/local_business_reset_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../app/app_shell.dart';
import '../data/auth_password_service.dart';
import '../../settings/presentation/subscription_screen.dart';
import 'login_screen.dart';

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

  bool _isLoading = false;
  bool _isLoadingCatalog = false;
  String? _error;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  SubscriptionCatalog? _catalog;
  String? _selectedMarketKey;
  String _selectedSellingMode = 'products';
  String _selectedCurrency = r'$';

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

  SubscriptionMarket? _marketForKey(SubscriptionCatalog catalog, String? key) {
    if (key == null) return null;
    for (final market in catalog.markets) {
      if (market.key == key) return market;
    }
    return null;
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
    if (_isBusinessSetupFlow) {
      _loadSubscriptionCatalog();
    }
  }

  Future<void> _loadSubscriptionCatalog() async {
    setState(() => _isLoadingCatalog = true);
    try {
      await SyncSettingsService.init();
      final catalog = await SubscriptionService.fetchPlans();
      final market =
          catalog.selectedMarket ??
          (catalog.markets.isNotEmpty ? catalog.markets.first : null);
      final catalogMessage = market == null
          ? 'No subscription markets are active yet. In Super Admin, enable at least one country price or payment gateway.'
          : null;
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _selectedMarketKey = market?.key;
        _selectedSellingMode = _preferredSellingModeForMarket(catalog, market);
        _selectedCurrency = ShopSettings.suggestedCurrencyForCountry(
          market?.countryCode,
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

  void _selectMarket(String? key) {
    final catalog = _catalog;
    if (catalog == null || key == null) return;
    final market = _marketForKey(catalog, key);
    setState(() {
      _selectedMarketKey = key;
      _selectedSellingMode = _preferredSellingModeForMarket(catalog, market);
      _selectedCurrency = ShopSettings.suggestedCurrencyForCountry(
        market?.countryCode,
      );
    });
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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await SyncSettingsService.init();
      final backendUrl =
          _catalog?.backendUrl ??
          await SubscriptionService.resolveReachableBackendUrl();

      if (backendUrl.isEmpty) {
        throw Exception(
          'Cloud backend is not configured. Contact your administrator.',
        );
      }

      final deviceId = await SyncSettingsService.getOrCreateDeviceId();

      final response = await CloudAuthService.registerOnline(
        backendUrl: backendUrl,
        businessName: businessName,
        ownerName: name,
        ownerEmail: email,
        phone: phone,
        password: password,
        deviceId: deviceId,
        countryCode: market?.countryCode ?? 'GLOBAL',
        currency: _selectedCurrency,
        requestedPlanCode: signupPlan?.code,
        sellingMode: _isBusinessSetupFlow ? _selectedSellingMode : null,
        provider: market?.provider,
      );

      if (backendUrl != SyncSettingsService.backendUrl) {
        await SyncSettingsService.setBackendUrl(backendUrl);
      }

      final incomingBusinessId = ((response.business['id'] as String?) ?? '')
          .trim();
      final incomingBusinessName =
          ((response.business['name'] as String?) ?? '').trim();

      if (_isBusinessSetupFlow) {
        await LocalBusinessResetService.clearForBusinessSwitch();
      }

      final now = DateTime.now().toIso8601String();
      final user = response.user;
      final userId = (user['id'] as String?) ?? '';

      if (userId.isEmpty) {
        throw Exception('Cloud registration returned an incomplete user.');
      }

      final existingLocal = await DatabaseService.rawQuery(
        'SELECT id FROM users WHERE id = ? LIMIT 1',
        [userId],
      );
      if (existingLocal.isEmpty) {
        await DatabaseService.db.insert('users', {
          'id': userId,
          'name': (user['name'] as String?) ?? name,
          'email': (user['email'] as String?) ?? email,
          'phone': (user['phone'] as String?) ?? phone,
          'password': AuthPasswordService.hashPassword(password),
          'role': (user['role'] as String?) ?? 'ADMIN',
          'feature_access_json': user['feature_access_json'] as String?,
          'allowed_service_ids_json':
              user['allowed_service_ids_json'] as String?,
          'pos_mode': (user['pos_mode'] as String?) ?? 'both',
          'service_order_scope':
              (user['service_order_scope'] as String?) ??
              'all_visible_services',
          'created_at': (user['created_at'] as String?) ?? now,
          'updated_at': (user['updated_at'] as String?) ?? now,
          'cloud_verified_at': now,
          'sync_status': 'synced',
        });
      }

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

      final localUser = await DatabaseService.queryById('users', userId);
      await SessionService.signIn(localUser ?? user);

      if (!mounted) return;

      final destination = _isBusinessSetupFlow
          ? SubscriptionScreen(
              afterSignup: true,
              initialCountryCode: market?.countryCode,
              initialProvider: market?.provider,
              initialPlanCode: _readInitialPlanCode(response),
            )
          : AppShell(key: AppShell.shellKey);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => destination),
        (route) => false,
      );
    } catch (error) {
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
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(minHeight: 2),
          SizedBox(height: 12),
          Text(
            'Loading available countries...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
            const Text(
              'No subscription markets are active.',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _loadSubscriptionCatalog,
            icon: const Icon(Icons.refresh),
            label: const Text('Load subscription plans'),
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
        const Text(
          'Country',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedMarketKey,
          decoration: const InputDecoration(
            prefixIcon: _GradientIcon(Icons.public_outlined),
          ),
          items: catalog.markets
              .map(
                (market) => DropdownMenuItem(
                  value: market.key,
                  child: Text(market.displayLabel),
                ),
              )
              .toList(),
          onChanged: _isLoading ? null : _selectMarket,
        ),
        const SizedBox(height: 20),
        const Text(
          'Display Currency',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(_selectedCurrency),
          initialValue: _selectedCurrency,
          decoration: const InputDecoration(
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
        const SizedBox(height: 20),
        const Text(
          'Business Type',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (modes.isEmpty)
          const Text(
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
        const SizedBox(height: 12),
        Text(
          market == null || signupPlan == null
              ? 'Your plan will be selected after account creation.'
              : 'Your account starts with ${_sellingModeLabel(_selectedSellingMode)} on ${signupPlan.name}. You can adjust the plan after creating the account.',
          style: const TextStyle(
            color: AppColors.textSecondary,
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
    _businessNameController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = SingleChildScrollView(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/logo.png',
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.secondary, AppColors.primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 36,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _isBusinessSetupFlow ? 'Create Account' : 'Create Staff Account',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isBusinessSetupFlow
                  ? 'Register your business online to start using Piki POS'
                  : 'Create a new team member account',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

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
                child: const Row(
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
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isBusinessSetupFlow) ...[
              const Text(
                'Business Name',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _businessNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Enter your business name',
                  prefixIcon: _GradientIcon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 20),
              _buildSubscriptionChooser(),
              const SizedBox(height: 20),
            ],
            const Text(
              'Full Name',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Enter your full name',
                prefixIcon: _GradientIcon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Phone Number',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Enter your phone number',
                prefixIcon: _GradientIcon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Email',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Enter your email',
                prefixIcon: _GradientIcon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Password',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'Create a password',
                prefixIcon: const _GradientIcon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Confirm Password',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmPasswordController,
              obscureText: !_showConfirmPassword,
              onSubmitted: (_) => _signUp(),
              decoration: InputDecoration(
                hintText: 'Confirm your password',
                prefixIcon: const _GradientIcon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  tooltip: _showConfirmPassword
                      ? 'Hide password'
                      : 'Show password',
                  icon: Icon(
                    _showConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(
                    () => _showConfirmPassword = !_showConfirmPassword,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create Account'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _isLoading ? null : _goToSignIn,
              child: const Text('Back to sign in'),
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
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/images/pos_users.png'),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          Colors.black26,
                          BlendMode.darken,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(flex: 4, child: Center(child: form)),
              ],
            );
          } else {
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/pos_users.png',
                  fit: BoxFit.cover,
                  color: Colors.black54,
                  colorBlendMode: BlendMode.darken,
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

class _GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const _GradientIcon(this.icon, {this.size = 24});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [AppColors.secondary, AppColors.primaryLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}
