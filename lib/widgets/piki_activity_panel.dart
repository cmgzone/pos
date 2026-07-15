import 'package:flutter/material.dart';

import '../core/services/piki_ai_job_service.dart';
import '../core/theme/app_colors.dart';

class PikiActivityPanel extends StatelessWidget {
  final PikiAiJob? job;
  final List<PikiAiJobEvent> events;
  final String title;

  const PikiActivityPanel({
    super.key,
    required this.job,
    required this.events,
    this.title = 'Piki is working',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = ((job?.progress ?? 0).clamp(0, 100)) / 100;
    final currentStep = job?.currentStep?.trim();
    final visibleEvents = events.length > 8
        ? events.sublist(events.length - 8)
        : events;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PikiPulseIcon(active: job?.isRunning ?? true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      currentStep?.isNotEmpty == true
                          ? currentStep!
                          : job?.jobType == 'storefront_theme'
                          ? 'Preparing your storefront'
                          : 'Preparing your import',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress <= 0 || (job?.isRunning ?? false)
                  ? progress == 0
                        ? null
                        : progress
                  : progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surface.withValues(
                alpha: 0.75,
              ),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: visibleEvents.isEmpty
                ? _ActivityLine(
                    key: const ValueKey('empty'),
                    icon: Icons.hourglass_top,
                    color: theme.colorScheme.primary,
                    title: 'Waiting for Piki activity',
                    message: 'The backend worker is getting ready.',
                    isCurrent: true,
                  )
                : Column(
                    key: ValueKey(visibleEvents.map((e) => e.id).join('|')),
                    children: [
                      for (var index = 0; index < visibleEvents.length; index++)
                        _ActivityLine(
                          event: visibleEvents[index],
                          isCurrent:
                              index == visibleEvents.length - 1 &&
                              (job?.isRunning ?? false),
                        ),
                    ],
                  ),
          ),
          if (job?.errorMessage?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              job!.errorMessage!,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PikiPulseIcon extends StatelessWidget {
  final bool active;

  const _PikiPulseIcon({required this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: active ? 1.06 : 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primaryContainer,
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.32),
          ),
        ),
        child: Icon(
          Icons.auto_awesome,
          color: theme.colorScheme.primary,
          size: 22,
        ),
      ),
    );
  }
}

class _ActivityLine extends StatelessWidget {
  final PikiAiJobEvent? event;
  final IconData? icon;
  final Color? color;
  final String? title;
  final String? message;
  final bool isCurrent;

  const _ActivityLine({
    super.key,
    this.event,
    this.icon,
    this.color,
    this.title,
    this.message,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor = color ?? _eventColor(theme, event);
    final resolvedIcon = icon ?? _eventIcon(event);
    final resolvedTitle = title ?? event?.title ?? 'Piki activity';
    final resolvedMessage = message ?? event?.message;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: isCurrent ? 1 : 0.72,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: resolvedColor.withValues(alpha: 0.12),
              ),
              child: Icon(resolvedIcon, color: resolvedColor, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resolvedTitle,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (resolvedMessage?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      resolvedMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _eventIcon(PikiAiJobEvent? event) {
    if (event == null) return Icons.more_horiz;
    if (event.isError) return Icons.error_outline;
    if (event.isWarning) return Icons.warning_amber_outlined;
    return switch (event.eventType) {
      'file_received' => Icons.upload_file_outlined,
      'file_parsed' => Icons.description_outlined,
      'ai_extracting' => Icons.auto_awesome,
      'products_found' => Icons.inventory_2_outlined,
      'duplicate_check' => Icons.manage_search_outlined,
      'product_prepared' => Icons.playlist_add_check,
      'review_required' => Icons.fact_check_outlined,
      'job_queued' => Icons.cloud_queue_outlined,
      'storefront_brief' => Icons.notes_rounded,
      'storefront_planning' => Icons.account_tree_outlined,
      'storefront_designing' => Icons.auto_awesome_rounded,
      'storefront_validating' => Icons.fact_check_outlined,
      'storefront_saving' => Icons.cloud_upload_outlined,
      'storefront_ready' => Icons.web_asset_rounded,
      'marketing_context' => Icons.inventory_2_outlined,
      'marketing_writing' => Icons.edit_note_rounded,
      'marketing_validating' => Icons.fact_check_outlined,
      'marketing_ready' => Icons.campaign_outlined,
      'completed' => Icons.check_circle_outline,
      _ => Icons.bolt_outlined,
    };
  }

  static Color _eventColor(ThemeData theme, PikiAiJobEvent? event) {
    if (event?.isError == true) return AppColors.error;
    if (event?.isWarning == true) return AppColors.warning;
    if (event?.eventType == 'review_required' ||
        event?.eventType == 'completed' ||
        event?.eventType == 'storefront_ready') {
      return AppColors.success;
    }
    return theme.colorScheme.primary;
  }
}
