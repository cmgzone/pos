import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/services/database_service.dart';
import 'core/services/license_service.dart';
import 'core/services/session_service.dart';
import 'core/services/shop_settings.dart';
import 'core/services/sync_settings_service.dart';
import 'features/app/app_shell.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/sign_up_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite database
  await DatabaseService.initialize();
  // Initialize shop settings
  await ShopSettings.init();
  // Initialize persisted session
  await SessionService.init();
  // Initialize sync preferences
  await SyncSettingsService.init();
  // Initialize cached cloud license
  await LicenseService.init();

  runApp(const ProviderScope(child: PosApp()));
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Velora POS',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
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
  late AnimationController _controller;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;

      Widget destination;
      if (SessionService.isLoggedIn) {
        destination = const AppShell();
      } else {
        // Check if any local users exist
        final userCount = await DatabaseService.rawQuery(
          'SELECT COUNT(*) as count FROM users WHERE deleted_at IS NULL',
        );
        final count = (userCount.firstOrNull?['count'] as num?)?.toInt() ?? 0;
        if (count > 0) {
          // Users exist — show login screen
          destination = const LoginScreen();
        } else {
          // No users — fresh install, require online sign up
          destination = const SignUpScreen(initialRole: 'ADMIN');
        }
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, _) => destination,
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.4),
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
              ),
              const SizedBox(height: 32),
              Text(
                'Velora POS',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI-Powered Point of Sale',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(letterSpacing: 4),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
