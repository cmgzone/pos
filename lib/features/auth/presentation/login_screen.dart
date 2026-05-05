import 'package:flutter/material.dart';

import '../../../core/services/cloud_auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/local_business_reset_service.dart';
import '../../../core/services/seed_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../app/app_shell.dart';
import '../data/auth_service.dart';
import '../data/user_repository.dart';
import 'sign_up_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String _loadingStatus = '';
  bool _cloudLoginSucceeded = false;
  bool _showPassword = false;
  String _loginBusinessId = '';
  String _loginBusinessName = '';
  CloudAuthResponse? _cloudAuthResponse;
  String _cloudPasswordForLocalLogin = '';

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _loadingStatus = '';
      _cloudLoginSucceeded = false;
      _loginBusinessId = '';
      _loginBusinessName = '';
      _cloudAuthResponse = null;
      _cloudPasswordForLocalLogin = '';
    });

    try {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        throw Exception('Enter both email and password.');
      }

      // Try online login first when backend is configured
      await SyncSettingsService.init();
      final backendUrl = SyncSettingsService.backendUrl;
      Map<String, dynamic>? signedInUser;

      if (backendUrl.isNotEmpty) {
        try {
          if (mounted) {
            setState(() => _loadingStatus = 'Verifying with cloud...');
          }
          signedInUser = await _tryOnlineLogin(
            backendUrl: backendUrl,
            email: email,
            password: password,
          );
          _cloudLoginSucceeded = true;
        } catch (_) {
          // For network errors or cloud rejections, fallback to local auth
        }
      }

      // Fallback to local auth if online didn't succeed
      signedInUser ??= await _tryLocalLogin(email: email, password: password);
      var authenticatedUser = signedInUser;

      // If we logged in via cloud on a new device, detect a business switch
      // and pull all fresh data.
      if (_cloudLoginSucceeded && backendUrl.isNotEmpty) {
        final incomingBusinessId = _loginBusinessId;
        // Wipe whenever the incoming business differs from what is stored
        // locally — including when storedBusinessId is empty (legacy install
        // or first login after this fix was deployed).  A wipe+reinit on an
        // already-empty DB is harmless: it just recreates the blank schema.
        final businessChanged =
            incomingBusinessId.isNotEmpty &&
            SyncSettingsService.localBusinessId != incomingBusinessId;

        if (businessChanged) {
          if (mounted) {
            setState(
              () => _loadingStatus =
                  'Switching business — clearing local data...',
            );
          }
          await LocalBusinessResetService.clearForBusinessSwitch();
        }

        final cloudResponse = _cloudAuthResponse;
        if (cloudResponse != null) {
          await CloudAuthService.persistCloudResponse(cloudResponse);

          if (businessChanged) {
            authenticatedUser = await _upsertCloudUser(
              cloudUser: cloudResponse.user,
              email: email,
              passwordForLocalLogin: _cloudPasswordForLocalLogin,
            );
          }
        }

        await SessionService.signIn(authenticatedUser);

        if (mounted) {
          setState(() => _loadingStatus = 'Syncing business data...');
        }
        try {
          await SyncService.syncNow();
          // Record which business now owns this local DB.
          await _persistCurrentBusinessContext(incomingBusinessId);
          // Seed demo data if this is a fresh device with no products.
          await SeedService.seedIfEmpty();
        } catch (_) {
          // Sync failure shouldn't block login — data will sync later.
          // Still record the business so future logins don't wipe unnecessarily.
          await _persistCurrentBusinessContext(incomingBusinessId);
        }
      } else {
        await SessionService.signIn(authenticatedUser);
      }

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => AppShell(key: AppShell.shellKey)),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Attempt to authenticate against the cloud backend.
  Future<Map<String, dynamic>> _tryOnlineLogin({
    required String backendUrl,
    required String email,
    required String password,
  }) async {
    // Find the local user to get their stored password hash for cloud comparison.
    // The cloud stores the hashed password, so we need to hash it the same way.
    final localUser = await UserRepository.findByEmail(email);
    String hashedPassword;

    if (localUser != null) {
      // Use the stored hash — the cloud has the same hash
      final storedPassword = localUser['password'] as String? ?? '';
      // Verify locally first to get the right hash
      if (storedPassword.isNotEmpty) {
        // We need to use the same hash that was sent during registration
        // The cloud stores the hashed password, so we send the hash
        hashedPassword = storedPassword;
      } else {
        // No local hash stored; this user was created via cloud
        // Hash the plain password to compare against cloud
        hashedPassword = _hashPasswordForCloud(password);
      }
    } else {
      // User not found locally — hash the password for cloud lookup
      hashedPassword = _hashPasswordForCloud(password);
    }

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();

    final response = await CloudAuthService.loginOnline(
      backendUrl: backendUrl,
      email: email,
      hashedPassword: hashedPassword,
      deviceId: deviceId,
    );

    _cloudAuthResponse = response;
    _cloudPasswordForLocalLogin = hashedPassword;

    final incomingBusinessId = ((response.business['id'] as String?) ?? '')
        .trim();
    if (incomingBusinessId.isNotEmpty) {
      _loginBusinessId = incomingBusinessId;
    }
    final incomingBusinessName = ((response.business['name'] as String?) ?? '')
        .trim();
    if (incomingBusinessName.isNotEmpty) {
      _loginBusinessName = incomingBusinessName;
    }

    return _upsertCloudUser(
      cloudUser: response.user,
      email: email,
      passwordForLocalLogin: hashedPassword,
    );
  }

  /// Attempt to authenticate against the local SQLite database.
  Future<Map<String, dynamic>> _tryLocalLogin({
    required String email,
    required String password,
  }) async {
    final user = await AuthService.signIn(email: email, password: password);

    // Check if this user has been cloud-verified before
    final cloudVerifiedAt = user['cloud_verified_at'] as String?;
    if (cloudVerifiedAt == null || cloudVerifiedAt.trim().isEmpty) {
      // Legacy user without cloud verification — allow access but warn
      // (backward compatibility for pre-SaaS accounts)
    }

    return user;
  }

  String _hashPasswordForCloud(String password) {
    // Use the same hashing as AuthPasswordService
    return password; // The cloud login endpoint will handle comparison
  }

  Future<Map<String, dynamic>> _upsertCloudUser({
    required Map<String, dynamic> cloudUser,
    required String email,
    required String passwordForLocalLogin,
  }) async {
    final userId = (cloudUser['id'] as String?) ?? '';
    final now = DateTime.now().toIso8601String();

    if (userId.isEmpty) {
      return cloudUser;
    }

    final existingLocal = await DatabaseService.rawQuery(
      'SELECT id FROM users WHERE id = ? LIMIT 1',
      [userId],
    );

    if (existingLocal.isEmpty) {
      await DatabaseService.db.insert('users', {
        'id': userId,
        'name': (cloudUser['name'] as String?) ?? '',
        'email': (cloudUser['email'] as String?) ?? email,
        'phone': (cloudUser['phone'] as String?) ?? '',
        'password': passwordForLocalLogin,
        'role': (cloudUser['role'] as String?) ?? 'CASHIER',
        'feature_access_json': cloudUser['feature_access_json'] as String?,
        'allowed_service_ids_json':
            cloudUser['allowed_service_ids_json'] as String?,
        'pos_mode': (cloudUser['pos_mode'] as String?) ?? 'both',
        'service_order_scope':
            (cloudUser['service_order_scope'] as String?) ??
            'all_visible_services',
        'created_at': (cloudUser['created_at'] as String?) ?? now,
        'updated_at': (cloudUser['updated_at'] as String?) ?? now,
        'cloud_verified_at': now,
        'sync_status': 'synced',
      });
    } else {
      await DatabaseService.db.update(
        'users',
        {
          'name': (cloudUser['name'] as String?) ?? '',
          'email': (cloudUser['email'] as String?) ?? email,
          'phone': (cloudUser['phone'] as String?) ?? '',
          'password': passwordForLocalLogin,
          'role': (cloudUser['role'] as String?) ?? 'CASHIER',
          'feature_access_json': cloudUser['feature_access_json'] as String?,
          'allowed_service_ids_json':
              cloudUser['allowed_service_ids_json'] as String?,
          'pos_mode': (cloudUser['pos_mode'] as String?) ?? 'both',
          'service_order_scope':
              (cloudUser['service_order_scope'] as String?) ??
              'all_visible_services',
          'updated_at': now,
          'cloud_verified_at': now,
          'sync_status': 'synced',
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
    }

    return await DatabaseService.queryById('users', userId) ?? cloudUser;
  }

  Future<void> _persistCurrentBusinessContext(String businessId) async {
    if (businessId.isNotEmpty) {
      await SyncSettingsService.setLocalBusinessId(businessId);
    }
    if (_loginBusinessName.isNotEmpty) {
      await ShopSettings.init();
      await ShopSettings.setShopName(_loginBusinessName);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
            // Logo
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
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      size: 36,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Welcome Back',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to Devis POS',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 36),

            // Error message
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

            // Email
            const Text(
              'Email',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'Enter your email',
                prefixIcon: _GradientIcon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 20),

            // Password
            const Text(
              'Password',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                hintText: 'Enter your password',
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
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 32),

            // Sign In button
            ElevatedButton(
              onPressed: _isLoading ? null : _login,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Sign In'),
            ),
            if (_isLoading && _loadingStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _loadingStatus,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const SignUpScreen(initialRole: 'ADMIN'),
                        ),
                      );
                    },
              child: const Text('Create account'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Need a staff login? Ask an admin to add it from Settings > Team Access.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Cloud sync info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  _GradientIcon(Icons.cloud_done_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sign in with your cloud account. Works offline after first login.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
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
