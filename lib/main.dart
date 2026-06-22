import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/navigation/app_navigator.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/branch_service.dart';
import 'core/services/database_service.dart';
import 'core/services/license_service.dart';
import 'core/services/openrouter_service.dart';
import 'core/services/preferences_recovery_service.dart';
import 'core/services/session_service.dart';
import 'core/services/shop_settings.dart';
import 'core/services/sync_settings_service.dart';
import 'core/services/background_tasks_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/error_messages.dart';
import 'features/app/app_shell.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/training/widgets/training_overlay_host.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _ensureWritableWorkingDirectory();
  ErrorWidget.builder = (_) => const _AppErrorFallback();
  runApp(const ProviderScope(child: PosApp()));
}

Future<void> _ensureWritableWorkingDirectory() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      final supportDir = await getApplicationSupportDirectory();
      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }
      Directory.current = supportDir;
    } catch (_) {
      // If we can't switch to the support directory, leave the working
      // directory as-is. Plugin data that uses absolute paths (via
      // path_provider) will still resolve correctly.
    }
  }
}

class PosApp extends ConsumerWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      navigatorKey: AppNavigator.navigatorKey,
      title: 'Piki POS',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          TrainingOverlayHost(child: child ?? const SizedBox.shrink()),
      home: const SplashScreen(),
    );
  }
}

class _AppErrorFallback extends StatelessWidget {
  const _AppErrorFallback();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Color(0xFF09090E),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFFF3B30),
                  size: 36,
                ),
                SizedBox(height: 14),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF9F9FB),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please close Piki POS and open it again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFA0A0B0),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    _startBackgroundTasksAfterFirstFrame();
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

      // Already logged in — skip onboarding entirely
      if (SessionService.isLoggedIn) {
        _navigateTo(AppShell(key: AppShell.shellKey));
        return;
      }

      // First-time user — check if onboarding is needed
      final onboarded = await hasCompletedOnboarding();
      if (!mounted || attempt != _startupAttempt) {
        return;
      }

      if (onboarded) {
        _navigateTo(const LoginScreen());
      } else {
        _navigateTo(
          OnboardingScreen(
            onComplete: (onboardingContext) async {
              Navigator.of(onboardingContext).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, animation, _) => const LoginScreen(),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                  transitionDuration: const Duration(milliseconds: 500),
                ),
              );
            },
          ),
        );
      }
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

  void _navigateTo(Widget destination) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, _) => destination,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _initializeAppServices() async {
    await PreferencesRecoveryService.repairIfNeeded();
    await DatabaseService.initialize();
    await ShopSettings.init();
    await SessionService.init();
    await BranchService.init();
    await SyncSettingsService.init();
    await LicenseService.init();
    await OpenRouterService.init();
    // Refresh AI config from server in background (non-blocking)
    OpenRouterService.refreshConfig().ignore();
  }

  void _startBackgroundTasksAfterFirstFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackgroundTasksService.init().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'background tasks',
            context: ErrorDescription(
              'while initializing Android background tasks',
            ),
          ),
        );
      }).ignore();
    });
  }

  String _formatStartupError(Object error) {
    return AppErrorMessage.from(
      error,
      fallback:
          'Piki POS could not start correctly. Please restart the app and try again.',
    );
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
                'Piki POS',
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
