import 'package:flutter/material.dart';

import '../../../core/services/cloud_auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/local_business_reset_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../app/app_shell.dart';
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
  String? _selectedPlanCode;

  bool get _isBusinessSetupFlow => widget.initialRole.toUpperCase() == 'ADMIN';

  SubscriptionMarket? get _selectedMarket {
    final catalog = _catalog;
    if (catalog == null) return null;
    for (final market in catalog.markets) {
      if (market.key == _selectedMarketKey) return market;
    }
    return catalog.selectedMarket ??
        (catalog.markets.isEmpty ? null : catalog.markets.first);
  }

  SubscriptionPlanSummary? get _selectedPlan {
    final catalog = _catalog;
    if (catalog == null) return null;
    for (final plan in catalog.plans) {
      if (plan.code == _selectedPlanCode) return plan;
    }
    return null;
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
      final plan = market == null ? null : _firstPlanForMarket(catalog, market);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _selectedMarketKey = market?.key;
        _selectedPlanCode = plan?.code;
        _isLoadingCatalog = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load subscription plans: $error';
        _isLoadingCatalog = false;
      });
    }
  }

  SubscriptionPlanSummary? _firstPlanForMarket(
    SubscriptionCatalog catalog,
    SubscriptionMarket market,
  ) {
    for (final plan in catalog.plans) {
      if (plan.priceFor(market) != null) return plan;
    }
    return null;
  }

  void _selectMarket(String? key) {
    final catalog = _catalog;
    if (catalog == null || key == null) return;
    final market = catalog.markets.firstWhere(
      (item) => item.key == key,
      orElse: () => catalog.markets.first,
    );
    final plan = _firstPlanForMarket(catalog, market);
    setState(() {
      _selectedMarketKey = key;
      _selectedPlanCode = plan?.code;
    });
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
    final plan = _selectedPlan;
    if (_isBusinessSetupFlow && (market == null || plan == null)) {
      setState(() => _error = 'Choose your country and subscription plan.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await SyncSettingsService.init();
      final backendUrl = SyncSettingsService.backendUrl;

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
        requestedPlanCode: plan?.code ?? 'trial',
        provider: market?.provider,
      );

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
          'password':
              '', // Password is hashed on the server; local login will re-verify online
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

      if (response.checkoutRequired && response.checkoutContext != null) {
        await _startRegistrationCheckout(response, phone);
      }

      if (_isBusinessSetupFlow) {
        await ShopSettings.init();
        await ShopSettings.setShopName(
          incomingBusinessName.isNotEmpty ? incomingBusinessName : businessName,
        );
        await ShopSettings.setShopPhone(phone);
        await ShopSettings.setShopEmail(email);
      }

      final localUser = await DatabaseService.queryById('users', userId);
      await SessionService.signIn(localUser ?? user);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => AppShell(key: AppShell.shellKey)),
        (route) => false,
      );
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startRegistrationCheckout(
    CloudAuthResponse response,
    String phone,
  ) async {
    final checkoutContext =
        response.checkoutContext ?? const <String, dynamic>{};
    final planCode = checkoutContext['planCode']?.toString() ?? '';
    final countryCode = checkoutContext['countryCode']?.toString() ?? '';
    final provider = checkoutContext['provider']?.toString() ?? '';
    if (planCode.isEmpty || countryCode.isEmpty || provider.isEmpty) return;

    try {
      final checkout = await SubscriptionService.startCheckout(
        planCode: planCode,
        countryCode: countryCode,
        provider: provider,
        phoneNumber: provider == 'mpesa' ? phone : null,
      );
      if (!mounted) return;
      final message =
          checkout.message ??
          (provider == 'mpesa'
              ? 'M-Pesa checkout started. Paid features unlock after confirmation.'
              : 'Checkout started. Complete payment from Subscription settings.');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account created, but checkout could not start: $error',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
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
            'Loading available countries and plans...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      );
    }

    final catalog = _catalog;
    if (catalog == null || catalog.markets.isEmpty) {
      return OutlinedButton.icon(
        onPressed: _loadSubscriptionCatalog,
        icon: const Icon(Icons.refresh),
        label: const Text('Load subscription plans'),
      );
    }

    final market = _selectedMarket;
    final visiblePlans = market == null
        ? <SubscriptionPlanSummary>[]
        : catalog.plans.where((plan) => plan.priceFor(market) != null).toList();

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
          'Plan',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (visiblePlans.isEmpty)
          const Text(
            'No active plans are configured for this country.',
            style: TextStyle(color: AppColors.error, fontSize: 12),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visiblePlans.map((plan) {
              final price = market == null ? null : plan.priceFor(market);
              final selected = plan.code == _selectedPlanCode;
              return ChoiceChip(
                selected: selected,
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name),
                    Text(
                      price?.displayAmount ?? 'No price',
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? Colors.white70
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                onSelected: _isLoading
                    ? null
                    : (_) => setState(() => _selectedPlanCode = plan.code),
              );
            }).toList(),
          ),
        if (_selectedPlan != null) ...[
          const SizedBox(height: 10),
          Text(
            '${_selectedPlan!.entitlements.maxBranches} branch(es), '
            '${_selectedPlan!.entitlements.maxEmployees} employee(s), '
            '${_selectedPlan!.entitlements.maxAiAgents} AI seat(s)',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
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
                  ? 'Register your business online to start using Devis POS'
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
