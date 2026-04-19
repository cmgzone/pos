import 'package:flutter/material.dart';

import '../../../core/services/cloud_auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../app/app_shell.dart';

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
  String? _error;

  bool get _isBusinessSetupFlow => widget.initialRole.toUpperCase() == 'ADMIN';

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

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // ── Online registration (requires internet) ──
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
      );

      // ── Persist locally ──
      final now = DateTime.now().toIso8601String();
      final user = response.user;
      final userId = (user['id'] as String?) ?? '';

      if (userId.isEmpty) {
        throw Exception('Cloud registration returned an incomplete user.');
      }

      // Store user in local SQLite
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
          'password': '', // Password is hashed on the server; local login will re-verify online
          'role': (user['role'] as String?) ?? 'ADMIN',
          'created_at': (user['created_at'] as String?) ?? now,
          'updated_at': (user['updated_at'] as String?) ?? now,
          'cloud_verified_at': now,
          'sync_status': 'synced',
        });
      }

      // Persist the license/access token
      await CloudAuthService.persistCloudResponse(response);

      // Set shop settings
      if (_isBusinessSetupFlow) {
        await ShopSettings.setShopName(businessName);
        await ShopSettings.setShopPhone(phone);
        await ShopSettings.setShopEmail(email);
      }

      // Sign into local session
      final localUser = await DatabaseService.queryById('users', userId);
      await SessionService.signIn(localUser ?? user);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
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
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
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
                Container(
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
                ),
                const SizedBox(height: 28),
                Text(
                  _isBusinessSetupFlow
                      ? 'Create Account'
                      : 'Create Staff Account',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isBusinessSetupFlow
                      ? 'Register your business online to start using Velora POS'
                      : 'Create a new team member account',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),

                // Internet required notice
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
                        Icon(Icons.cloud_outlined, size: 16, color: AppColors.primary),
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
                      prefixIcon: Icon(
                        Icons.storefront_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
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
                    prefixIcon: Icon(
                      Icons.person_outline,
                      color: AppColors.textSecondary,
                    ),
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
                    prefixIcon: Icon(
                      Icons.phone_outlined,
                      color: AppColors.textSecondary,
                    ),
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
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: AppColors.textSecondary,
                    ),
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
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Create a password',
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: AppColors.textSecondary,
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
                  obscureText: true,
                  onSubmitted: (_) => _signUp(),
                  decoration: const InputDecoration(
                    hintText: 'Confirm your password',
                    prefixIcon: Icon(
                      Icons.lock_reset_outlined,
                      color: AppColors.textSecondary,
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
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
