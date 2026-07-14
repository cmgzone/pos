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
import 'widgets/piki_mark.dart';

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
      body: Stack(
        children: [
          Positioned(
            right: -90,
            top: -110,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.055),
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: -100,
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withValues(alpha: 0.055),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 48)
                        .clamp(0.0, double.infinity)
                        .toDouble(),
                  ),
                  child: Center(
                    child: FadeTransition(
                      opacity: _fadeIn,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const PikiMark(size: 112, showShadow: true),
                            const SizedBox(height: 30),
                            Text(
                              'Piki',
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'The calm way to run a busy shop.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 38),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _startupError == null
                                  ? Column(
                                      key: const ValueKey('startup-loading'),
                                      children: [
                                        SizedBox(
                                          width: 160,
                                          child: LinearProgressIndicator(
                                            minHeight: 3,
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          _isInitializing
                                              ? 'Preparing your workspace'
                                              : 'Opening Piki',
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ],
                                    )
                                  : Column(
                                      key: const ValueKey('startup-error'),
                                      children: [
                                        Icon(
                                          Icons.error_outline_rounded,
                                          color: theme.colorScheme.error,
                                          size: 30,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Piki could not open',
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _startupError!,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                        const SizedBox(height: 20),
                                        FilledButton.icon(
                                          onPressed: _startInitialization,
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                          ),
                                          label: const Text('Try again'),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
