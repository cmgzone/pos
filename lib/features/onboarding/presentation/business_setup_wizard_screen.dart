import 'package:flutter/material.dart';

import '../../../core/services/session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../data/business_onboarding_service.dart';

class BusinessSetupWizardScreen extends StatefulWidget {
  final String businessId;
  final String businessName;
  final String? planCode;
  final String? planName;
  final List<String> planFeatures;
  final String initialSellingFocus;
  final String initialBusinessType;
  final Widget destination;

  const BusinessSetupWizardScreen({
    super.key,
    required this.businessId,
    required this.businessName,
    required this.destination,
    this.planCode,
    this.planName,
    this.planFeatures = const [],
    this.initialSellingFocus = '',
    this.initialBusinessType = '',
  });

  @override
  State<BusinessSetupWizardScreen> createState() =>
      _BusinessSetupWizardScreenState();
}

class _BusinessSetupWizardScreenState extends State<BusinessSetupWizardScreen>
    with TickerProviderStateMixin {
  int _step = 0;
  bool _isFinishing = false;
  bool _showWelcome = false;

  String _heardFrom = '';
  String _businessType = '';
  late String _sellingFocus;
  String _stockTracking = '';
  String _creditSales = '';
  String _onlineSelling = '';

  late final AnimationController _welcomeController;

  static const _totalSteps = 6;

  @override
  void initState() {
    super.initState();
    _businessType = _normalizeBusinessType(widget.initialBusinessType);
    _sellingFocus = _normalizeSellingFocus(widget.initialSellingFocus);
    _welcomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _welcomeController.dispose();
    super.dispose();
  }

  _WizardQuestion get _currentQuestion {
    return switch (_step) {
      0 => _WizardQuestion(
        eyebrow: 'Question 1 of $_totalSteps',
        title: 'Where did you hear about us?',
        subtitle: 'This helps us understand which channels bring real owners.',
        selectedValue: _heardFrom,
        options: const [
          _WizardOption(
            value: 'google',
            label: 'Google',
            icon: Icons.search_rounded,
            color: Color(0xFF4285F4),
          ),
          _WizardOption(
            value: 'tiktok',
            label: 'TikTok',
            icon: Icons.video_library_outlined,
            color: Color(0xFF00C2A8),
          ),
          _WizardOption(
            value: 'facebook_instagram',
            label: 'Facebook / Instagram',
            icon: Icons.groups_2_outlined,
            color: Color(0xFFE94057),
          ),
          _WizardOption(
            value: 'friend',
            label: 'Friend or owner',
            icon: Icons.handshake_outlined,
            color: Color(0xFF7C5CFF),
          ),
          _WizardOption(
            value: 'whatsapp',
            label: 'WhatsApp group',
            icon: Icons.chat_outlined,
            color: Color(0xFF22C55E),
          ),
          _WizardOption(
            value: 'youtube',
            label: 'YouTube',
            icon: Icons.play_circle_outline_rounded,
            color: Color(0xFFFF3B30),
          ),
          _WizardOption(
            value: 'app_store',
            label: 'App store',
            icon: Icons.storefront_outlined,
            color: Color(0xFFFFB020),
          ),
          _WizardOption(
            value: 'other',
            label: 'Other',
            icon: Icons.more_horiz_rounded,
            color: Color(0xFF64748B),
          ),
        ],
      ),
      1 => _WizardQuestion(
        eyebrow: 'Question 2 of $_totalSteps',
        title: 'What type of business do you run?',
        subtitle: 'Piki will use this to shape the first workspace setup.',
        selectedValue: _businessType,
        options: const [
          _WizardOption(
            value: 'retail',
            label: 'Retail shop',
            icon: Icons.storefront_outlined,
            color: AppColors.primary,
          ),
          _WizardOption(
            value: 'grocery',
            label: 'Grocery / mini mart',
            icon: Icons.local_grocery_store_outlined,
            color: Color(0xFF22C55E),
          ),
          _WizardOption(
            value: 'beauty',
            label: 'Beauty / cosmetics',
            icon: Icons.spa_outlined,
            color: AppColors.brandOrange,
          ),
          _WizardOption(
            value: 'pharmacy',
            label: 'Pharmacy',
            icon: Icons.medical_services_outlined,
            color: Color(0xFF14B8A6),
          ),
          _WizardOption(
            value: 'electronics',
            label: 'Electronics',
            icon: Icons.devices_other_outlined,
            color: Color(0xFF3B82F6),
          ),
          _WizardOption(
            value: 'fashion',
            label: 'Fashion / boutique',
            icon: Icons.checkroom_outlined,
            color: Color(0xFF8B5CF6),
          ),
          _WizardOption(
            value: 'services',
            label: 'Services',
            icon: Icons.design_services_outlined,
            color: Color(0xFFFFB020),
          ),
          _WizardOption(
            value: 'wholesale',
            label: 'Wholesale / credit',
            icon: Icons.warehouse_outlined,
            color: Color(0xFF0F766E),
          ),
          _WizardOption(
            value: 'online',
            label: 'Online seller',
            icon: Icons.public_outlined,
            color: Color(0xFF06B6D4),
          ),
          _WizardOption(
            value: 'restaurant',
            label: 'Restaurant / food',
            icon: Icons.restaurant_outlined,
            color: Color(0xFFF97316),
          ),
          _WizardOption(
            value: 'other',
            label: 'Other',
            icon: Icons.business_center_outlined,
            color: Color(0xFF64748B),
          ),
        ],
      ),
      2 => _WizardQuestion(
        eyebrow: 'Question 3 of $_totalSteps',
        title: 'What do you sell?',
        subtitle: 'This decides whether products, services, or both sit first.',
        selectedValue: _sellingFocus,
        options: const [
          _WizardOption(
            value: 'products',
            label: 'Products',
            icon: Icons.inventory_2_outlined,
            color: AppColors.primary,
          ),
          _WizardOption(
            value: 'services',
            label: 'Services',
            icon: Icons.design_services_outlined,
            color: Color(0xFFFFB020),
          ),
          _WizardOption(
            value: 'both',
            label: 'Products + services',
            icon: Icons.all_inclusive_outlined,
            color: Color(0xFF7C5CFF),
          ),
        ],
      ),
      3 => _WizardQuestion(
        eyebrow: 'Question 4 of $_totalSteps',
        title: 'Do you track stock?',
        subtitle: 'Stock answers influence inventory, purchases, and alerts.',
        selectedValue: _stockTracking,
        options: const [
          _WizardOption(
            value: 'yes',
            label: 'Yes, I track stock',
            icon: Icons.inventory_outlined,
            color: Color(0xFF22C55E),
          ),
          _WizardOption(
            value: 'no',
            label: 'No stock tracking',
            icon: Icons.block_outlined,
            color: Color(0xFF64748B),
          ),
          _WizardOption(
            value: 'later',
            label: 'Not yet',
            icon: Icons.schedule_outlined,
            color: Color(0xFFFFB020),
          ),
        ],
      ),
      4 => _WizardQuestion(
        eyebrow: 'Question 5 of $_totalSteps',
        title: 'Do customers buy on credit?',
        subtitle: 'Credit answers prepare Kopesha and follow-up workflows.',
        selectedValue: _creditSales,
        options: const [
          _WizardOption(
            value: 'yes',
            label: 'Yes, use Kopesha',
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.primary,
          ),
          _WizardOption(
            value: 'no',
            label: 'No credit sales',
            icon: Icons.payments_outlined,
            color: Color(0xFF22C55E),
          ),
          _WizardOption(
            value: 'later',
            label: 'Maybe later',
            icon: Icons.update_outlined,
            color: Color(0xFF7C5CFF),
          ),
        ],
      ),
      _ => _WizardQuestion(
        eyebrow: 'Question 6 of $_totalSteps',
        title: 'Do you sell online or through WhatsApp?',
        subtitle: 'This prepares catalog, order, and sharing defaults.',
        selectedValue: _onlineSelling,
        options: const [
          _WizardOption(
            value: 'yes',
            label: 'Yes, already',
            icon: Icons.shopping_bag_outlined,
            color: Color(0xFF06B6D4),
          ),
          _WizardOption(
            value: 'no',
            label: 'Not right now',
            icon: Icons.store_mall_directory_outlined,
            color: Color(0xFF64748B),
          ),
          _WizardOption(
            value: 'later',
            label: 'Planning to',
            icon: Icons.trending_up_rounded,
            color: Color(0xFFFFB020),
          ),
        ],
      ),
    };
  }

  bool get _canContinue => _currentQuestion.selectedValue.isNotEmpty;

  void _selectOption(String value) {
    setState(() {
      switch (_step) {
        case 0:
          _heardFrom = value;
          break;
        case 1:
          _businessType = value;
          _sellingFocus = _sellingFocusForBusinessType(value);
          break;
        case 2:
          _sellingFocus = value;
          break;
        case 3:
          _stockTracking = value;
          break;
        case 4:
          _creditSales = value;
          break;
        default:
          _onlineSelling = value;
          break;
      }
    });
  }

  void _next() {
    if (!_canContinue || _isFinishing) {
      return;
    }
    if (_step < _totalSteps - 1) {
      setState(() => _step += 1);
      return;
    }
    _finish();
  }

  void _back() {
    if (_step == 0 || _isFinishing) {
      return;
    }
    setState(() => _step -= 1);
  }

  Future<void> _finish() async {
    if (_isFinishing) {
      return;
    }

    setState(() => _isFinishing = true);

    final recommendations = BusinessOnboardingService.recommendedFeatures(
      businessType: _businessType,
      sellingFocus: _sellingFocus,
      stockTracking: _stockTracking,
      creditSales: _creditSales,
      onlineSelling: _onlineSelling,
    );
    final supported = BusinessOnboardingService.planSupportedFeatures(
      recommendedFeatures: recommendations,
      planFeatures: widget.planFeatures,
    );

    await BusinessOnboardingService.save(
      BusinessOnboardingAnswers(
        businessId: widget.businessId,
        businessName: widget.businessName,
        planCode: widget.planCode,
        heardFrom: _heardFrom,
        businessType: _businessType,
        sellingFocus: _sellingFocus,
        stockTracking: _stockTracking,
        creditSales: _creditSales,
        onlineSelling: _onlineSelling,
        recommendedFeatures: supported,
        completedAt: DateTime.now(),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() => _showWelcome = true);
    _welcomeController.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 1800));

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, animation, _) => widget.destination,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 450),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = _currentQuestion;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _showWelcome
              ? _WelcomeView(
                  key: const ValueKey('business-welcome'),
                  controller: _welcomeController,
                  businessName: widget.businessName,
                )
              : _WizardBody(
                  key: const ValueKey('business-wizard'),
                  question: question,
                  currentStep: _step,
                  totalSteps: _totalSteps,
                  businessName: widget.businessName,
                  planName: widget.planName,
                  supportedFeatures: _previewSupportedFeatures(),
                  canContinue: _canContinue,
                  isFinishing: _isFinishing,
                  onSelect: _selectOption,
                  onBack: _back,
                  onNext: _next,
                ),
        ),
      ),
    );
  }

  List<String> _previewSupportedFeatures() {
    if (_businessType.isEmpty) {
      return const [];
    }
    final recommendations = BusinessOnboardingService.recommendedFeatures(
      businessType: _businessType,
      sellingFocus: _sellingFocus,
      stockTracking: _stockTracking.isEmpty ? 'later' : _stockTracking,
      creditSales: _creditSales.isEmpty ? 'later' : _creditSales,
      onlineSelling: _onlineSelling.isEmpty ? 'later' : _onlineSelling,
    );
    return BusinessOnboardingService.planSupportedFeatures(
      recommendedFeatures: recommendations,
      planFeatures: widget.planFeatures,
    ).take(5).toList();
  }

  String _sellingFocusForBusinessType(String value) {
    switch (value) {
      case 'services':
        return 'services';
      case 'restaurant':
        return 'products';
      case 'other':
        return _sellingFocus.isEmpty ? 'both' : _sellingFocus;
      default:
        return 'products';
    }
  }

  static String _normalizeSellingFocus(String value) {
    switch (value.trim()) {
      case 'products':
        return 'products';
      case 'services':
        return 'services';
      case 'combo':
      case 'both':
        return 'both';
      case 'restaurant':
        return 'products';
      default:
        return '';
    }
  }

  static String _normalizeBusinessType(String value) {
    switch (value.trim().toLowerCase()) {
      case 'products':
      case 'product':
        return 'retail';
      case 'services':
      case 'restaurant':
        return value.trim().toLowerCase();
      default:
        return '';
    }
  }
}

class _WizardBody extends StatelessWidget {
  final _WizardQuestion question;
  final int currentStep;
  final int totalSteps;
  final String businessName;
  final String? planName;
  final List<String> supportedFeatures;
  final bool canContinue;
  final bool isFinishing;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _WizardBody({
    super.key,
    required this.question,
    required this.currentStep,
    required this.totalSteps,
    required this.businessName,
    required this.planName,
    required this.supportedFeatures,
    required this.canContinue,
    required this.isFinishing,
    required this.onSelect,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 820;
    final planText = planName == null || planName!.trim().isEmpty
        ? 'Included modules follow your selected plan.'
        : '${planName!.trim()} controls which modules open today.';

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 44 : 18,
            vertical: isWide ? 34 : 18,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    businessName: businessName,
                    planText: planText,
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                  ),
                  const SizedBox(height: 24),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 28,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isWide ? 28 : 18),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        transitionBuilder: (child, animation) {
                          final offset =
                              Tween<Offset>(
                                begin: const Offset(0.02, 0.04),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                              );
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: _QuestionContent(
                          key: ValueKey(question.title),
                          question: question,
                          supportedFeatures: supportedFeatures,
                          onSelect: onSelect,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (currentStep > 0)
                        OutlinedButton.icon(
                          onPressed: isFinishing ? null : onBack,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Back'),
                        ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: canContinue && !isFinishing ? onNext : null,
                        icon: isFinishing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                currentStep == totalSteps - 1
                                    ? Icons.check_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                        label: Text(
                          currentStep == totalSteps - 1
                              ? 'Finish setup'
                              : 'Continue',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final String businessName;
  final String planText;
  final int currentStep;
  final int totalSteps;

  const _TopBar({
    required this.businessName,
    required this.planText,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (currentStep + 1) / totalSteps;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/images/piki_mark_v2.png',
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 52,
              height: 52,
              color: AppColors.primary,
              child: const Icon(Icons.point_of_sale, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                businessName.trim().isEmpty ? 'Set up Piki POS' : businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                planText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${currentStep + 1}/$totalSteps',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  color: AppColors.primary,
                  backgroundColor: scheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuestionContent extends StatelessWidget {
  final _WizardQuestion question;
  final List<String> supportedFeatures;
  final ValueChanged<String> onSelect;

  const _QuestionContent({
    super.key,
    required this.question,
    required this.supportedFeatures,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.eyebrow,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          question.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          question.subtitle,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 620 ? 2 : 1;
            const spacing = 10.0;
            final width =
                (constraints.maxWidth - (columns - 1) * spacing) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: question.options.map((option) {
                return SizedBox(
                  width: width,
                  child: _OptionTile(
                    option: option,
                    selected: question.selectedValue == option.value,
                    onTap: () => onSelect(option.value),
                  ),
                );
              }).toList(),
            );
          },
        ),
        if (supportedFeatures.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SupportedFeaturePreview(features: supportedFeatures),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final _WizardOption option;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? Colors.white : scheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? option.color
                : scheme.surfaceContainerHighest.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? option.color
                  : scheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.18)
                      : option.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  option.icon,
                  color: selected ? Colors.white : option.color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14.5,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey('selected'),
                        color: Colors.white,
                        size: 22,
                      )
                    : Icon(
                        Icons.circle_outlined,
                        key: const ValueKey('idle'),
                        color: scheme.outline,
                        size: 20,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportedFeaturePreview extends StatelessWidget {
  final List<String> features;

  const _SupportedFeaturePreview({required this.features});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                color: AppColors.success,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Plan-supported setup preview',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: features.map((feature) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Text(
                  UserAccessProfile.featureLabel(feature),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _WelcomeView extends StatelessWidget {
  final AnimationController controller;
  final String businessName;

  const _WelcomeView({
    super.key,
    required this.controller,
    required this.businessName,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = Tween<double>(
      begin: 0.72,
      end: 1,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.elasticOut));
    final fade = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: scale,
                  child: Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 36,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 62,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'Welcome to Piki POS',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    businessName.trim().isEmpty
                        ? 'Your workspace is ready.'
                        : '${businessName.trim()} is ready.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                    backgroundColor: context.appSurfaceHighlight,
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

class _WizardQuestion {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String selectedValue;
  final List<_WizardOption> options;

  const _WizardQuestion({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.selectedValue,
    required this.options,
  });
}

class _WizardOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _WizardOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
}
