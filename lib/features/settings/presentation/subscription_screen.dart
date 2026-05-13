import 'package:flutter/material.dart';

import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../app/app_shell.dart';
import 'subscription_plans_section.dart';

class SubscriptionScreen extends StatelessWidget {
  final bool afterSignup;
  final String? initialCountryCode;
  final String? initialProvider;
  final String? initialPlanCode;

  const SubscriptionScreen({
    super.key,
    this.afterSignup = false,
    this.initialCountryCode,
    this.initialProvider,
    this.initialPlanCode,
  });

  @override
  Widget build(BuildContext context) {
    final license = LicenseService.currentSnapshot;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Subscription'),
        automaticallyImplyLeading: !afterSignup,
        actions: [
          TextButton.icon(
            onPressed: () => _openApp(context),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(afterSignup ? 'Continue to POS' : 'Open POS'),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHero(context, license),
                  const SizedBox(height: 20),
                  SubscriptionPlansSection(
                    fullPage: true,
                    initialCountryCode: initialCountryCode,
                    initialProvider: initialProvider,
                    initialPlanCode: initialPlanCode,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, LicenseSnapshot license) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 720;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(license.shortLabel, AppColors.secondary),
                  if (license.plan != null)
                    _pill(license.plan!.toUpperCase(), AppColors.primaryLight),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                afterSignup
                    ? 'Pick the plan that fits your business'
                    : 'Manage your business plan',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Every card below is built from the live Super Admin setup, including country price, selling mode, feature access, branch limits, employee limits, AI seats, and AI rate limits.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                intro,
                const SizedBox(height: 18),
                _summaryPanel(license, fill: true),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: intro),
              const SizedBox(width: 18),
              _summaryPanel(license),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryPanel(LicenseSnapshot license, {bool fill = false}) {
    return Container(
      width: fill ? double.infinity : 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Access',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 12),
          _summaryRow(Icons.storefront_outlined, 'Branches',
              _limitText(license.entitlements.maxBranches)),
          _summaryRow(Icons.group_outlined, 'Employees',
              _limitText(license.entitlements.maxEmployees)),
          _summaryRow(Icons.auto_awesome_outlined, 'Piki seats',
              _limitText(license.entitlements.maxAiAgents)),
          _summaryRow(
            Icons.inventory_2_outlined,
            'Selling',
            _sellingModeLabel(license.entitlements.sellingMode),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _openApp(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AppShell(key: AppShell.shellKey)),
      (route) => false,
    );
  }

  String _limitText(int value) {
    if (value <= 0 || value >= 999999) return 'Unlimited';
    return value.toString();
  }

  String _sellingModeLabel(String mode) {
    switch (mode) {
      case UserAccessProfile.posModeProducts:
        return 'Products';
      case UserAccessProfile.posModeServices:
        return 'Services';
      default:
        return 'Products + Services';
    }
  }
}
