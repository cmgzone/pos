import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/license_service.dart';
import '../../../core/services/piki_ai_job_service.dart';
import '../../products/presentation/catalog_orders_screen.dart';
import '../../products/presentation/catalog_publish_section.dart';
import '../../products/presentation/product_list_screen.dart';
import '../../settings/presentation/payment_methods_section.dart';
import '../../settings/presentation/storefront_brand_settings_section.dart';
import '../../settings/presentation/storefront_theme_settings_section.dart';
import 'storefront_campaigns_section.dart';
import 'storefront_delivery_section.dart';
import 'storefront_launch_checklist.dart';
import 'storefront_marketing_section.dart';

enum OnlineStoreSection {
  overview,
  products,
  orders,
  campaigns,
  marketing,
  branding,
  website,
  payments,
  delivery,
}

class OnlineStoreScreen extends StatefulWidget {
  final bool embeddedInAppShell;
  final VoidCallback? onOpenPos;
  final OnlineStoreSection initialSection;
  final int navigationRevision;

  const OnlineStoreScreen({
    super.key,
    this.embeddedInAppShell = false,
    this.onOpenPos,
    this.initialSection = OnlineStoreSection.overview,
    this.navigationRevision = 0,
  });

  @override
  State<OnlineStoreScreen> createState() => _OnlineStoreScreenState();
}

class _OnlineStoreScreenState extends State<OnlineStoreScreen> {
  late OnlineStoreSection _selectedSection;
  late final String _storefrontType;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
    final sellingMode = LicenseService.currentSnapshot.entitlements.sellingMode
        .trim()
        .toLowerCase();
    _storefrontType = sellingMode == 'restaurant'
        ? 'restaurant'
        : sellingMode == 'services' || sellingMode == 'service'
        ? 'services'
        : 'retail';
  }

  @override
  void didUpdateWidget(covariant OnlineStoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection ||
        oldWidget.navigationRevision != widget.navigationRevision) {
      _selectedSection = widget.initialSection;
    }
  }

  void _selectSection(OnlineStoreSection section) {
    if (_selectedSection == section) return;
    setState(() => _selectedSection = section);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _buildWorkspace(context);
    if (widget.embeddedInAppShell) return workspace;

    return Scaffold(
      appBar: AppBar(title: const Text('Online Store')),
      body: workspace,
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OnlineStoreHeader(selectedSection: _selectedSection),
            _OnlineStorePikiStatusBar(
              selectedSection: _selectedSection,
              onOpenSection: _selectSection,
            ),
            if (isWide)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OnlineStoreNavigation(
                      selectedSection: _selectedSection,
                      onSelected: _selectSection,
                    ),
                    VerticalDivider(width: 1, thickness: 1),
                    Expanded(child: _buildSelectedContent()),
                  ],
                ),
              )
            else ...[
              _OnlineStoreSectionPicker(
                selectedSection: _selectedSection,
                onSelected: _selectSection,
              ),
              Divider(height: 1),
              Expanded(child: _buildSelectedContent()),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSelectedContent() {
    return switch (_selectedSection) {
      OnlineStoreSection.overview => _OnlineStoreOverview(
        onSelected: _selectSection,
        storefrontType: _storefrontType,
      ),
      OnlineStoreSection.products => ProductListScreen(
        onOpenCatalogOrders: () => _selectSection(OnlineStoreSection.orders),
      ),
      OnlineStoreSection.orders => CatalogOrdersScreen(
        onOpenPos: widget.onOpenPos,
      ),
      OnlineStoreSection.campaigns => StorefrontCampaignsSection(
        storefrontType: _storefrontType,
      ),
      OnlineStoreSection.marketing => StorefrontMarketingSection(
        storefrontType: _storefrontType,
      ),
      OnlineStoreSection.branding => const _ScrollableSettingsSection(
        child: StorefrontBrandSettingsSection(),
      ),
      OnlineStoreSection.website => const _ScrollableSettingsSection(
        child: StorefrontThemeSettingsSection(),
      ),
      OnlineStoreSection.payments => const PaymentMethodsSection(),
      OnlineStoreSection.delivery => StorefrontDeliverySection(
        storefrontType: _storefrontType,
      ),
    };
  }
}

class _OnlineStorePikiStatusBar extends StatefulWidget {
  final OnlineStoreSection selectedSection;
  final ValueChanged<OnlineStoreSection> onOpenSection;

  const _OnlineStorePikiStatusBar({
    required this.selectedSection,
    required this.onOpenSection,
  });

  @override
  State<_OnlineStorePikiStatusBar> createState() =>
      _OnlineStorePikiStatusBarState();
}

class _OnlineStorePikiStatusBarState extends State<_OnlineStorePikiStatusBar> {
  List<PikiAiJob> _jobs = const [];
  Timer? _timer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final jobs = await PikiAiJobService.listActiveJobs();
      final onlineStoreJobs = jobs
          .where(
            (job) => const {
              'storefront_theme',
              'storefront_site',
              'storefront_page',
              'marketing_content',
              'storefront_marketing',
            }.contains(job.jobType),
          )
          .toList();
      if (!mounted) return;
      setState(() => _jobs = onlineStoreJobs);
    } catch (_) {
      // Online Store remains usable when cloud activity cannot refresh.
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    PikiAiJob? job;
    for (final candidate in _jobs) {
      if (_sectionForJob(candidate) != widget.selectedSection) {
        job = candidate;
        break;
      }
    }
    if (job == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final destination = _sectionForJob(job);
    final area = destination == OnlineStoreSection.marketing
        ? 'marketing'
        : 'website';
    final currentStep = job.currentStep?.trim();
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.72),
      child: InkWell(
        onTap: () => widget.onOpenSection(destination),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 9, 24, 10),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: job.progress <= 0 ? null : job.progress / 100,
                  strokeWidth: 2.5,
                  color: colors.primary,
                  backgroundColor: colors.primary.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Piki is working on your $area',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (currentStep?.isNotEmpty == true)
                      Text(
                        currentStep!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onPrimaryContainer.withValues(
                            alpha: 0.78,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${job.progress}%',
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () => widget.onOpenSection(destination),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('View progress'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.onPrimaryContainer,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 1120) ...[
                const SizedBox(width: 8),
                Text(
                  'Safe to close the app',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  OnlineStoreSection _sectionForJob(PikiAiJob job) {
    return switch (job.jobType) {
      'marketing_content' ||
      'storefront_marketing' => OnlineStoreSection.marketing,
      _ => OnlineStoreSection.website,
    };
  }
}

class _OnlineStoreHeader extends StatelessWidget {
  final OnlineStoreSection selectedSection;

  const _OnlineStoreHeader({required this.selectedSection});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _sectionDetails[selectedSection]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.storefront_rounded,
              color: theme.colorScheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Online Store',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${selected.label} · ${selected.description}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineStoreNavigation extends StatelessWidget {
  final OnlineStoreSection selectedSection;
  final ValueChanged<OnlineStoreSection> onSelected;

  const _OnlineStoreNavigation({
    required this.selectedSection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 248,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          for (final section in OnlineStoreSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _OnlineStoreNavButton(
                section: section,
                selected: selectedSection == section,
                onTap: () => onSelected(section),
              ),
            ),
        ],
      ),
    );
  }
}

class _OnlineStoreNavButton extends StatelessWidget {
  final OnlineStoreSection section;
  final bool selected;
  final VoidCallback onTap;

  const _OnlineStoreNavButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = _sectionDetails[section]!;
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(details.icon, color: foreground, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  details.label,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.chevron_right_rounded, color: foreground, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineStoreSectionPicker extends StatelessWidget {
  final OnlineStoreSection selectedSection;
  final ValueChanged<OnlineStoreSection> onSelected;

  const _OnlineStoreSectionPicker({
    required this.selectedSection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _sectionDetails[selectedSection]!;
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: PopupMenuButton<OnlineStoreSection>(
          key: const ValueKey('online-store-section-selector'),
          tooltip: 'Choose store section',
          initialValue: selectedSection,
          onSelected: onSelected,
          itemBuilder: (context) => [
            for (final section in OnlineStoreSection.values)
              PopupMenuItem(
                value: section,
                child: Row(
                  children: [
                    Icon(_sectionDetails[section]!.icon, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_sectionDetails[section]!.label)),
                    if (section == selectedSection)
                      Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(selected.icon, size: 19, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selected.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'Change section',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnlineStoreOverview extends StatelessWidget {
  final ValueChanged<OnlineStoreSection> onSelected;
  final String storefrontType;

  const _OnlineStoreOverview({
    required this.onSelected,
    required this.storefrontType,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CatalogPublishSection(),
                StorefrontLaunchChecklist(
                  storefrontType: storefrontType,
                  onStepSelected: (step) => onSelected(switch (step) {
                    'branding' => OnlineStoreSection.branding,
                    'products' => OnlineStoreSection.products,
                    'payments' => OnlineStoreSection.payments,
                    'delivery' => OnlineStoreSection.delivery,
                    _ => OnlineStoreSection.website,
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage your store',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Everything customers browse, order, and pay for is managed here.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 850
                          ? 3
                          : constraints.maxWidth >= 540
                          ? 2
                          : 1;
                      const spacing = 12.0;
                      final cardWidth =
                          (constraints.maxWidth - spacing * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final section in OnlineStoreSection.values.skip(
                            1,
                          ))
                            SizedBox(
                              width: cardWidth,
                              child: _OnlineStoreOverviewCard(
                                section: section,
                                onTap: () => onSelected(section),
                              ),
                            ),
                        ],
                      );
                    },
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

class _OnlineStoreOverviewCard extends StatelessWidget {
  final OnlineStoreSection section;
  final VoidCallback onTap;

  const _OnlineStoreOverviewCard({required this.section, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = _sectionDetails[section]!;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  details.icon,
                  size: 21,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      details.label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollableSettingsSection extends StatelessWidget {
  final Widget child;

  const _ScrollableSettingsSection({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: child,
        ),
      ),
    );
  }
}

class _OnlineStoreSectionDetails {
  final String label;
  final String description;
  final IconData icon;

  const _OnlineStoreSectionDetails({
    required this.label,
    required this.description,
    required this.icon,
  });
}

const _sectionDetails = <OnlineStoreSection, _OnlineStoreSectionDetails>{
  OnlineStoreSection.overview: _OnlineStoreSectionDetails(
    label: 'Overview',
    description: 'Open, share, and manage your customer website.',
    icon: Icons.dashboard_outlined,
  ),
  OnlineStoreSection.products: _OnlineStoreSectionDetails(
    label: 'Products',
    description: 'Choose what customers can browse and buy online.',
    icon: Icons.inventory_2_outlined,
  ),
  OnlineStoreSection.orders: _OnlineStoreSectionDetails(
    label: 'Orders',
    description: 'Review and fulfil orders placed on your website.',
    icon: Icons.receipt_long_outlined,
  ),
  OnlineStoreSection.campaigns: _OnlineStoreSectionDetails(
    label: 'Campaigns',
    description: 'Create focused landing pages with reusable share links.',
    icon: Icons.campaign_outlined,
  ),
  OnlineStoreSection.marketing: _OnlineStoreSectionDetails(
    label: 'Marketing',
    description: 'Generate social, WhatsApp, and product marketing copy.',
    icon: Icons.auto_awesome_outlined,
  ),
  OnlineStoreSection.branding: _OnlineStoreSectionDetails(
    label: 'Branding',
    description: 'Manage your store name, logo, cover, and brand colors.',
    icon: Icons.branding_watermark_outlined,
  ),
  OnlineStoreSection.website: _OnlineStoreSectionDetails(
    label: 'Website & Checkout',
    description:
        'Choose premium themes, customize design, preview, and publish.',
    icon: Icons.web_outlined,
  ),
  OnlineStoreSection.payments: _OnlineStoreSectionDetails(
    label: 'Payments',
    description: 'Configure how customers pay for their online orders.',
    icon: Icons.payments_outlined,
  ),
  OnlineStoreSection.delivery: _OnlineStoreSectionDetails(
    label: 'Delivery',
    description: 'Configure pickup, delivery, and checkout instructions.',
    icon: Icons.local_shipping_outlined,
  ),
};
