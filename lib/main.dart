import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/navigation/app_navigator.dart';
import 'core/services/branch_service.dart';
import 'core/services/database_service.dart';
import 'core/services/license_service.dart';
import 'core/services/preferences_recovery_service.dart';
import 'core/services/session_service.dart';
import 'core/services/shop_settings.dart';
import 'core/services/sync_settings_service.dart';
import 'core/theme/app_theme.dart';
import 'features/app/app_shell.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/training/widgets/training_overlay_host.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: PosApp()));
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigator.navigatorKey,
      title: 'Devis POS',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          TrainingOverlayHost(child: child ?? const SizedBox.shrink()),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  int _startupAttempt = 0;
  bool _isInitializing = true;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    final attempt = ++_startupAttempt;
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _startupError = null;
      });
    }

    try {
      await _initializeAppServices();
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted || attempt != _startupAttempt) {
        return;
      }

      final Widget destination = SessionService.isLoggedIn
          ? AppShell(key: AppShell.shellKey)
          : const LoginScreen();

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, _) => destination,
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'app startup',
          context: ErrorDescription('while initializing the POS app'),
        ),
      );

      if (!mounted || attempt != _startupAttempt) {
        return;
      }

      setState(() {
        _isInitializing = false;
        _startupError = _formatStartupError(error);
      });
    }
  }

  Future<void> _initializeAppServices() async {
    await PreferencesRecoveryService.repairIfNeeded();
    await DatabaseService.initialize();
    await ShopSettings.init();
    await SessionService.init();
    await BranchService.init();
    await SyncSettingsService.init();
    await LicenseService.init();
  }

  String _formatStartupError(Object error) {
    final message = error.toString().trim();
    const prefix = 'Exception: ';
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length).trim();
    }
    return message;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.primaryColor,
                            theme.primaryColor.withValues(alpha: 0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primaryColor.withValues(alpha: 0.4),
                            blurRadius: 40,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.point_of_sale_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Devis POS',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI-Powered Point of Sale',
                style: theme.textTheme.bodyMedium?.copyWith(letterSpacing: 4),
              ),
              const SizedBox(height: 40),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _startupError == null
                    ? Column(
                        key: const ValueKey('startup-loading'),
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isInitializing
                                ? 'Preparing your workspace...'
                                : 'Opening...',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      )
                    : ConstrainedBox(
                        key: const ValueKey('startup-error'),
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.error,
                              size: 30,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Startup failed',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                _startupError!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _startInitialization,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
