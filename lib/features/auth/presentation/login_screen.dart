import 'package:flutter/material.dart';

import '../../../core/services/cloud_auth_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/local_business_reset_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../app/app_shell.dart';
import '../data/auth_exception.dart';
import '../data/auth_service.dart';
import '../data/auth_password_service.dart';
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
  double? _loadingProgress;
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
      _loadingProgress = null;
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
      var allowLocalFallback = backendUrl.isEmpty;

      if (backendUrl.isNotEmpty) {
        try {
          _updateLoadingStatus('Verifying with cloud...', progress: 0.08);
          signedInUser = await _tryOnlineLogin(
            backendUrl: backendUrl,
            email: email,
            password: password,
          );
          _cloudLoginSucceeded = true;
        } on CloudAuthException catch (error) {
          if (error.kind != CloudAuthFailureKind.network) {
            rethrow;
          }
          allowLocalFallback = true;
        }
      }

      // Fallback to local auth only for offline/network cases. A rejected cloud
      // login must not open stale data from a previous business on this device.
      if (signedInUser == null) {
        if (!allowLocalFallback) {
          throw Exception('Cloud sign in is required for this account.');
        }
        signedInUser = await _tryLocalLogin(
          email: email,
          password: password,
          requireCloudVerified: backendUrl.isNotEmpty,
        );
      }
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
          _updateLoadingStatus(
            SyncSettingsService.localBusinessId.isEmpty
                ? 'Preparing this business on your device...'
                : 'Checking current business sync status...',
            progress: 0.16,
          );
          await LocalBusinessResetService.clearForBusinessSwitch();
        }

        final cloudResponse = _cloudAuthResponse;
        if (cloudResponse != null) {
          await CloudAuthService.persistCloudResponse(cloudResponse);
          authenticatedUser = await _upsertCloudUser(
            cloudUser: cloudResponse.user,
            email: email,
            passwordForLocalLogin: _cloudPasswordForLocalLogin,
          );
        }

        await SessionService.signIn(authenticatedUser);

        final productCatalogExpected =
            LicenseService.currentSnapshot.entitlements.canSellProducts;
        final shouldForceFullPull =
            businessChanged ||
            (productCatalogExpected && await _hasNoLocalProducts());
        _updateLoadingStatus(
          shouldForceFullPull
              ? 'Downloading your product catalog...'
              : 'Syncing business data...',
          progress: 0.22,
        );
        try {
          await SyncService.syncNow(
            forceFullPull: shouldForceFullPull,
            onProgress: (progress) {
              _updateLoadingStatus(progress.message, progress: progress.value);
            },
          );
          // Record which business now owns this local DB.
          await _persistCurrentBusinessContext(incomingBusinessId);
          _updateLoadingStatus(
            'Products ready. Opening Piki POS...',
            progress: 1,
          );
        } catch (error, stackTrace) {
          debugPrint('Login cloud sync failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          if (businessChanged || shouldForceFullPull) {
            await SessionService.signOut();
            if (businessChanged) {
              await SyncSettingsService.resetSyncProgress();
            }
            final reason = AppErrorMessage.from(
              error,
              fallback:
                  'The server returned business data that this device could not apply.',
            );
            throw AuthException(
              productCatalogExpected
                  ? 'Could not download your products. $reason'
                  : 'Could not download your business data. $reason',
            );
          }
          _updateLoadingStatus(
            'Using local data. Cloud sync will retry in the app.',
          );
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
      if (!mounted) return;
      setState(() {
        _loadingStatus = '';
        _loadingProgress = null;
        _error = AppErrorMessage.from(
          e,
          fallback: 'Sign in failed. Check your details and try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateLoadingStatus(String status, {double? progress}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingStatus = status;
      _loadingProgress = progress?.clamp(0, 1).toDouble();
    });
  }

  Future<bool> _hasNoLocalProducts() async {
    final rows = await DatabaseService.rawQuery(
      'SELECT COUNT(*) AS count FROM products WHERE deleted_at IS NULL',
    );
    if (rows.isEmpty) {
      return true;
    }
    final count = rows.first['count'];
    if (count is int) {
      return count == 0;
    }
    return int.tryParse(count?.toString() ?? '0') == 0;
  }

  /// Attempt to authenticate against the cloud backend.
  Future<Map<String, dynamic>> _tryOnlineLogin({
    required String backendUrl,
    required String email,
    required String password,
  }) async {
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();

    final response = await CloudAuthService.loginOnline(
      backendUrl: backendUrl,
      email: email,
      password: password,
      deviceId: deviceId,
    );

    _cloudAuthResponse = response;
    _cloudPasswordForLocalLogin = AuthPasswordService.hashPassword(password);

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

    return response.user;
  }

  /// Attempt to authenticate against the local SQLite database.
  Future<Map<String, dynamic>> _tryLocalLogin({
    required String email,
    required String password,
    required bool requireCloudVerified,
  }) async {
    final user = await AuthService.signIn(email: email, password: password);
    if (requireCloudVerified) {
      final cloudVerifiedAt = (user['cloud_verified_at'] as String?)?.trim();
      final localBusinessId = SyncSettingsService.localBusinessId.trim();
      final license = LicenseService.currentSnapshot;
      final licenseBusinessId = license.businessId?.trim() ?? '';
      final trustedLocalBusiness =
          cloudVerifiedAt != null &&
          cloudVerifiedAt.isNotEmpty &&
          localBusinessId.isNotEmpty &&
          license.hasBinding &&
          licenseBusinessId == localBusinessId &&
          license.accessStatus != LicenseAccessStatus.invalid;

      if (!trustedLocalBusiness) {
        throw const AuthException(
          'Connect to the internet and sign in with the cloud account before this device can open business data offline.',
        );
      }
    }

    /*
    if (false) {
      // Legacy user without cloud verification — allow access but warn
      // (backward compatibility for pre-SaaS accounts)
    }
    */

    return user;
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
        'allowed_branch_ids_json':
            cloudUser['allowed_branch_ids_json'] as String?,
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
          'allowed_branch_ids_json':
              cloudUser['allowed_branch_ids_json'] as String?,
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final formCard = Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(40),
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
          // Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/images/logo.png',
              width: 72,
              height: 72,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, Theme.of(context).colorScheme.secondary],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.point_of_sale_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 28),
          Text(
            'Welcome Back',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Sign in to Piki POS',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: 36),

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
                  Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Email
          Text(
            'Email',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Enter your email',
              prefixIcon: _GradientIcon(Icons.email_outlined),
            ),
          ),
          SizedBox(height: 20),

          // Password
          Text(
            'Password',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
          SizedBox(height: 8),
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
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            onSubmitted: (_) => _login(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ForgotPasswordScreen(
                            initialEmail: _emailController.text,
                          ),
                        ),
                      );
                    },
              child: Text('Forgot password?'),
            ),
          ),
          SizedBox(height: 20),

          // Sign In button
          ElevatedButton(
            onPressed: _isLoading ? null : _login,
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : Text('Sign In'),
          ),
          if (_isLoading && _loadingStatus.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outline),
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: _loadingProgress,
                      minHeight: 6,
                      backgroundColor: colors.outline.withValues(alpha: 0.5),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _loadingStatus,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          SizedBox(height: 16),
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
            child: Text('Create account'),
          ),
          SizedBox(height: 8),
          Text(
            'Need a staff login? Ask an admin to add it from Settings > Team Access.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),

          // Cloud sync info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const _GradientIcon(Icons.cloud_done_outlined, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sign in with your cloud account. Works offline after first login.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final desktopForm = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(child: formCard),
    );
    final mobileForm = SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          final minHeight = constraints.maxHeight > 40
              ? constraints.maxHeight - 40
              : 0.0;

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(child: formCard),
            ),
          );
        },
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
                    decoration: BoxDecoration(
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
                Expanded(flex: 4, child: desktopForm),
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
                mobileForm,
              ],
            );
          }
        },
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  int _step = 0;
  bool _isLoading = false;
  bool _isComplete = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _error;
  String? _sentEmail;
  String? _verificationToken;
  DateTime? _codeExpiresAt;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail.trim().toLowerCase();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  Future<String> _resolveBackendUrl() async {
    await SyncSettingsService.init();
    final configured = SyncSettingsService.backendUrl.trim();
    if (configured.isNotEmpty) return configured;
    final resolved = await SubscriptionService.resolveReachableBackendUrl();
    if (resolved.isEmpty) {
      throw Exception(
        'Cloud backend is not configured. Contact your administrator.',
      );
    }
    return resolved;
  }

  Future<void> _sendCode() async {
    if (!_email.contains('@') || !_email.contains('.')) {
      setState(() => _error = 'Enter the email used for your account.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final backendUrl = await _resolveBackendUrl();
      final response = await CloudAuthService.requestPasswordResetOtp(
        backendUrl: backendUrl,
        email: _email,
      );
      if (!mounted) return;
      setState(() {
        _sentEmail = _email;
        _verificationToken = null;
        _codeExpiresAt = response.expiresAt;
        _codeController.clear();
        _step = 1;
        _error = response.sent
            ? null
            : 'A code was already sent. Try again in ${response.retryAfterSeconds ?? 60} seconds.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = AppErrorMessage.from(
          error,
          fallback: 'Could not send reset code. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.replaceAll(RegExp(r'\D'), '');
    if (_sentEmail != _email) {
      setState(() => _error = 'Send a fresh code to this email first.');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6 digit code from your email.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final backendUrl = await _resolveBackendUrl();
      final response = await CloudAuthService.verifyPasswordResetOtp(
        backendUrl: backendUrl,
        email: _email,
        code: code,
      );
      if (response.verificationToken.isEmpty) {
        throw Exception('Verification did not return a reset token.');
      }
      if (!mounted) return;
      setState(() {
        _verificationToken = response.verificationToken;
        _codeExpiresAt = response.expiresAt;
        _step = 2;
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final token = _verificationToken;

    if (token == null || token.isEmpty) {
      setState(() => _error = 'Verify your email before resetting password.');
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
      final backendUrl = await _resolveBackendUrl();
      await CloudAuthService.completePasswordReset(
        backendUrl: backendUrl,
        email: _email,
        verificationToken: token,
        newPassword: password,
      );
      if (!mounted) return;
      setState(() {
        _isComplete = true;
        _step = 3;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = AppErrorMessage.from(
          error,
          fallback: 'Could not reset password. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePrimaryAction() async {
    switch (_step) {
      case 0:
        await _sendCode();
        break;
      case 1:
        await _verifyCode();
        break;
      case 2:
        await _resetPassword();
        break;
      default:
        if (mounted) Navigator.pop(context);
    }
  }

  String get _primaryLabel {
    if (_isComplete) return 'Back to sign in';
    return switch (_step) {
      0 => 'Send reset code',
      1 => 'Verify code',
      2 => 'Reset password',
      _ => 'Back to sign in',
    };
  }

  String? _formatExpiry(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final local = expiresAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Code expires at $hour:$minute.';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
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
                const _GradientIcon(Icons.lock_reset_rounded, size: 42),
                SizedBox(height: 18),
                Text(
                  _isComplete ? 'Password updated' : 'Forgot password?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  _isComplete
                      ? 'You can now sign in with your new password.'
                      : 'We will send a secure code to your account email.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 22),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  SizedBox(height: 18),
                ],
                if (_step == 0) _buildEmailStep(),
                if (_step == 1) _buildCodeStep(),
                if (_step == 2) _buildPasswordStep(),
                if (_step == 3) _buildSuccessStep(),
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handlePrimaryAction,
                  child: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_primaryLabel),
                ),
                if (_step == 1 && !_isComplete) ...[
                  SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _isLoading ? null : _sendCode,
                    icon: Icon(Icons.refresh_rounded),
                    label: Text('Resend code'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return TextField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _sendCode(),
      decoration: InputDecoration(
        labelText: 'Account email',
        hintText: 'Enter your email',
        prefixIcon: _GradientIcon(Icons.email_outlined),
      ),
    );
  }

  Widget _buildCodeStep() {
    final expiryText = _formatExpiry(_codeExpiresAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the code sent to $_email.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        if (expiryText != null) ...[
          SizedBox(height: 6),
          Text(
            expiryText,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
        SizedBox(height: 14),
        TextField(
          controller: _codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _verifyCode(),
          decoration: InputDecoration(
            labelText: 'Verification code',
            counterText: '',
            hintText: 'Enter 6 digit code',
            prefixIcon: _GradientIcon(Icons.password_outlined),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordController,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'New password',
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
        SizedBox(height: 16),
        TextField(
          controller: _confirmPasswordController,
          obscureText: !_showConfirmPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _resetPassword(),
          decoration: InputDecoration(
            labelText: 'Confirm password',
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

  Widget _buildSuccessStep() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.success),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your password was reset successfully.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
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
        colors: [Theme.of(context).colorScheme.secondary, AppColors.primaryLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}
