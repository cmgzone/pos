import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';

/// Key used to persist whether the user has completed onboarding.
const _kOnboardingCompleteKey = 'onboarding_complete';

/// Check if onboarding has already been completed.
Future<bool> hasCompletedOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingCompleteKey) ?? false;
}

/// Mark onboarding as complete.
Future<void> markOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingCompleteKey, true);
}

class OnboardingScreen extends StatefulWidget {
  final Future<void> Function(BuildContext context) onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: Icons.point_of_sale_rounded,
      iconGradient: [Color(0xFFFF2A5F), Color(0xFFFF7E67)],
      title: 'Smart Point of Sale',
      subtitle:
          'Ring up sales instantly with barcode scanning, multi-payment support, and a blazing-fast checkout experience.',
      accent: Color(0xFFFF2A5F),
    ),
    _OnboardingPageData(
      icon: Icons.auto_awesome_rounded,
      iconGradient: [Color(0xFF00FFC2), Color(0xFF00B4D8)],
      title: 'Meet Piki — Your AI Agent',
      subtitle:
          'Ask Piki anything: sales trends, low stock alerts, or let it handle transactions hands-free with voice commands.',
      accent: Color(0xFF00FFC2),
    ),
    _OnboardingPageData(
      icon: Icons.inventory_2_rounded,
      iconGradient: [Color(0xFFFF9F0A), Color(0xFFFFD60A)],
      title: 'Effortless Inventory',
      subtitle:
          'Track stock across branches in real-time, get expiry alerts, manage variants, and automate reorder points.',
      accent: Color(0xFFFF9F0A),
    ),
    _OnboardingPageData(
      icon: Icons.analytics_rounded,
      iconGradient: [Color(0xFF7B61FF), Color(0xFFCF9FFF)],
      title: 'Insights That Drive Growth',
      subtitle:
          'Profit & loss reports, top-selling products, debtor tracking, and shift analytics — all at your fingertips.',
      accent: Color(0xFF7B61FF),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_isFinishing) {
      return;
    }

    setState(() => _isFinishing = true);

    try {
      await markOnboardingComplete();
      if (!mounted) {
        return;
      }
      await widget.onComplete(context);
    } finally {
      if (mounted) {
        setState(() => _isFinishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 16, right: 20),
                child: TextButton(
                  onPressed: _isFinishing ? null : _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return _OnboardingPage(
                    data: page,
                    isActive: _currentPage == index,
                    pulseAnimation: _pulseAnimation,
                    isWide: isWide,
                  );
                },
              ),
            ),

            // Bottom controls
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Column(
                children: [
                  // Dot indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => _DotIndicator(
                        isActive: index == _currentPage,
                        color: _pages[_currentPage].accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Action button
                  SizedBox(
                    width: isWide ? 340 : double.infinity,
                    height: 56,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _currentPage == _pages.length - 1
                          ? FilledButton(
                              key: const ValueKey('get-started'),
                              onPressed: _isFinishing ? null : _finish,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Get Started'),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 20),
                                ],
                              ),
                            )
                          : FilledButton(
                              key: const ValueKey('next'),
                              onPressed: _isFinishing ? null : _onNext,
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    _pages[_currentPage].accent,
                                foregroundColor:
                                    _pages[_currentPage].accent ==
                                            const Color(0xFF00FFC2)
                                        ? context.appBackground
                                        : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Next'),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 20),
                                ],
                              ),
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
  }
}

// ─── Page Data ──────────────────────────────────────────────────────────────

class _OnboardingPageData {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String subtitle;
  final Color accent;

  const _OnboardingPageData({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.subtitle,
    required this.accent,
  });
}

// ─── Single Page Widget ─────────────────────────────────────────────────────

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;
  final bool isActive;
  final Animation<double> pulseAnimation;
  final bool isWide;

  const _OnboardingPage({
    required this.data,
    required this.isActive,
    required this.pulseAnimation,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: isActive ? 1.0 : 0.0,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isWide ? 80 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            AnimatedBuilder(
              animation: pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: isActive ? pulseAnimation.value : 0.85,
                  child: child,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: isWide ? 120 : 100,
                  height: isWide ? 120 : 100,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: isWide ? 120 : 100,
                      height: isWide ? 120 : 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: data.iconGradient),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Icon(
                        data.icon,
                        size: 48,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Feature icon in a glowing circle
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: data.iconGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: data.accent.withValues(alpha: 0.35),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                data.icon,
                size: 36,
                color: data.accent == const Color(0xFF00FFC2)
                    ? context.appBackground
                    : Colors.white,
              ),
            ),
            const SizedBox(height: 40),

            // Title
            Text(
              data.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: isWide ? 32 : 26,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),

            // Subtitle
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                data.subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: isWide ? 16 : 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dot Indicator ──────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  final bool isActive;
  final Color color;

  const _DotIndicator({required this.isActive, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 28 : 8,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: isActive ? color : context.appSurfaceHighlight,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
    );
  }
}
