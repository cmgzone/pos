import 'package:flutter/material.dart';

import '../../../core/services/storefront_campaign_service.dart';

class StorefrontLaunchChecklist extends StatefulWidget {
  final ValueChanged<String> onStepSelected;
  final String storefrontType;

  const StorefrontLaunchChecklist({
    super.key,
    required this.onStepSelected,
    this.storefrontType = 'retail',
  });

  @override
  State<StorefrontLaunchChecklist> createState() =>
      _StorefrontLaunchChecklistState();
}

class _StorefrontLaunchChecklistState extends State<StorefrontLaunchChecklist> {
  StorefrontLaunchReadiness? _readiness;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final readiness = await StorefrontCampaignService.readiness(
        storefrontType: widget.storefrontType,
      );
      if (mounted) setState(() => _readiness = readiness);
    } catch (_) {
      // The rest of Online Store remains usable when readiness is unavailable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final readiness = _readiness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.rocket_launch_outlined,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Launch your online store',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          readiness == null
                              ? 'Follow one clear path from setup to publish.'
                              : '${readiness.readyCount} of ${readiness.totalCount} steps ready',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh checklist',
                    onPressed: _loading ? null : _load,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: readiness == null || readiness.totalCount == 0
                    ? 0
                    : readiness.readyCount / readiness.totalCount,
                minHeight: 6,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final steps = readiness?.steps ?? _fallbackSteps;
                  final columns = constraints.maxWidth >= 860
                      ? 6
                      : constraints.maxWidth >= 560
                      ? 3
                      : 2;
                  const spacing = 8.0;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (var index = 0; index < steps.length; index++)
                        SizedBox(
                          width: width,
                          child: _LaunchStepTile(
                            index: index,
                            step: steps[index],
                            onTap: () => widget.onStepSelected(steps[index].id),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchStepTile extends StatelessWidget {
  final int index;
  final StorefrontLaunchStep step;
  final VoidCallback onTap;

  const _LaunchStepTile({
    required this.index,
    required this.step,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: step.ready
          ? colors.primary.withValues(alpha: 0.08)
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: step.ready
                          ? colors.primary
                          : colors.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: step.ready
                          ? Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: colors.onPrimary,
                            )
                          : Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                step.label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                step.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _fallbackSteps = <StorefrontLaunchStep>[
  StorefrontLaunchStep(
    id: 'branding',
    label: 'Branding',
    ready: false,
    detail: 'Logo, identity, and colours',
  ),
  StorefrontLaunchStep(
    id: 'products',
    label: 'Products',
    ready: false,
    detail: 'Products customers can buy',
  ),
  StorefrontLaunchStep(
    id: 'payments',
    label: 'Payments',
    ready: false,
    detail: 'Manual or M-Pesa checkout',
  ),
  StorefrontLaunchStep(
    id: 'delivery',
    label: 'Delivery',
    ready: false,
    detail: 'Pickup and delivery choices',
  ),
  StorefrontLaunchStep(
    id: 'preview',
    label: 'Preview',
    ready: false,
    detail: 'Review the exact website',
  ),
  StorefrontLaunchStep(
    id: 'publish',
    label: 'Publish',
    ready: false,
    detail: 'Make the storefront live',
  ),
];
