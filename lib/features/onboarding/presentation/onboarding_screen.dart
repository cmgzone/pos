import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../widgets/piki_mark.dart';

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
      title: 'A faster counter, without the noise',
      subtitle:
          'Scan, take payment, and move the queue along. Piki keeps the important controls close and the rest out of your way.',
      accent: AppColors.primary,
    ),
    _OnboardingPageData(
      icon: Icons.forum_rounded,
      title: 'Ask the shop, get a useful answer',
      subtitle:
          'Piki can surface sales trends, flag low stock, and help with everyday work in plain language.',
      accent: AppColors.secondary,
    ),
    _OnboardingPageData(
      icon: Icons.inventory_2_rounded,
      title: 'Stock you can trust at a glance',
      subtitle:
          'Track branches, variants, expiry dates, and reorder points without turning inventory into a second job.',
      accent: AppColors.warning,
    ),
    _OnboardingPageData(
      icon: Icons.analytics_rounded,
      title: 'Know what happened, and what to do next',
      subtitle:
          'Follow profit, popular products, customer balances, and every shift from one clear business story.',
      accent: AppColors.metricMonth,
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
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
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
                onPageChanged: (index) => setState(() => _currentPage = index),
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
                                textStyle: const TextStyle(
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
                                backgroundColor: _pages[_currentPage].accent,
                                foregroundColor:
                                    _pages[_currentPage].accent ==
                                        const Color(0xFF00FFC2)
                                    ? context.appBackground
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                textStyle: const TextStyle(
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
  final String title;
  final String subtitle;
  final Color accent;

  const _OnboardingPageData({
    required this.icon,
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
    final theme = Theme.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: isActive ? 1.0 : 0.0,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 64 : 22,
            vertical: 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 32)
                  .clamp(0.0, double.infinity)
                  .toDouble(),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: pulseAnimation,
                      builder: (context, child) => Transform.scale(
                        scale: isActive
                            ? 0.96 + (pulseAnimation.value * 0.04)
                            : 0.96,
                        child: child,
                      ),
                      child: PikiMark(size: isWide ? 88 : 74, showShadow: true),
                    ),
                    SizedBox(height: isWide ? 28 : 20),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isWide ? 32 : 24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.8,
                          ),
                        ),
                        boxShadow: context.appPanelShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: data.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                                child: Icon(
                                  data.icon,
                                  size: 23,
                                  color: data.accent,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'BUILT FOR THE COUNTER',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: data.accent,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            data.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              height: 1.12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            data.subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.55,
                            ),
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
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
            : null,
      ),
    );
  }
}
