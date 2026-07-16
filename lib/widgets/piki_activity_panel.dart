import 'package:flutter/material.dart';

import '../core/services/piki_ai_job_service.dart';
import '../core/theme/app_colors.dart';

/// A live view of Piki's current backend stage.
///
/// The event history remains available to the job system for diagnostics, but
/// this surface deliberately presents only the newest event. Each real backend
/// update replaces the previous stage with a fade-and-slide transition.
class PikiActivityPanel extends StatefulWidget {
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
  State<PikiActivityPanel> createState() => _PikiActivityPanelState();
}

class _PikiActivityPanelState extends State<PikiActivityPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PikiActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job?.isRunning != widget.job?.isRunning) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _pulseController.stop();
        _pulseController.value = 0;
      } else {
        _syncAnimation();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (animationsDisabled) {
      _pulseController.stop();
      _pulseController.value = 0;
    } else {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.job?.isRunning ?? true) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final job = widget.job;
    final event = widget.events.isEmpty ? null : widget.events.last;
    final progress =
        ((job?.progress ?? event?.progress ?? 0).clamp(0, 100)) / 100.0;
    final isRunning = job?.isRunning ?? true;
    final isFailed = job?.isFailed == true || event?.isError == true;
    final isComplete =
        !isFailed &&
        (job?.status == 'completed' || job?.isWaitingForReview == true);
    final accent = isFailed
        ? colors.error
        : isComplete
        ? AppColors.success
        : colors.primary;
    final stageTitle = _stageTitle(job, event);
    final stageMessage = _stageMessage(job, event);
    final stageKey = ValueKey(
      '${job?.id}:${event?.id}:${job?.status}:${job?.currentStep}',
    );
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration = animationsDisabled
        ? Duration.zero
        : const Duration(milliseconds: 520);

    return Semantics(
      liveRegion: true,
      label: '$stageTitle. $stageMessage',
      child: AnimatedContainer(
        duration: transitionDuration,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: isFailed || isComplete ? 0.045 : 0.025),
            colors.surface,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.055),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AnimatedPikiOrb(
                  controller: _pulseController,
                  active: isRunning,
                  color: accent,
                  icon: _eventIcon(event, job),
                  duration: transitionDuration,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: transitionDuration,
                    reverseDuration: animationsDisabled
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.16),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: _CurrentPikiStage(
                      key: stageKey,
                      eyebrow: _statusLabel(job, isFailed, isComplete),
                      title: stageTitle,
                      message: stageMessage,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: progress),
                  duration: transitionDuration,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Text(
                    '${(value * 100).round()}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: transitionDuration,
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: isRunning && progress <= 0 ? null : value,
                  minHeight: 7,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: 0.1),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  isRunning
                      ? Icons.cloud_sync_outlined
                      : isComplete
                      ? Icons.cloud_done_outlined
                      : Icons.info_outline_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    isRunning
                        ? 'Working securely in Piki Cloud — you can leave this page or close the app.'
                        : isComplete
                        ? 'The result is saved and ready for your review.'
                        : 'The request is saved. You can retry without starting over.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if ((job?.totalSteps ?? 0) > 0) ...[
                  const SizedBox(width: 12),
                  Text(
                    isComplete
                        ? 'Complete'
                        : 'Stage ${(job!.completedSteps + 1).clamp(1, job.totalSteps)} of ${job.totalSteps}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _stageTitle(PikiAiJob? job, PikiAiJobEvent? event) {
    if (job?.isFailed == true) return 'Piki needs your attention';
    if (event?.title.trim().isNotEmpty == true) return event!.title.trim();
    if (job?.currentStep?.trim().isNotEmpty == true) {
      return job!.currentStep!.trim();
    }
    return widget.title;
  }

  String _stageMessage(PikiAiJob? job, PikiAiJobEvent? event) {
    if (job?.isFailed == true && job?.errorMessage?.trim().isNotEmpty == true) {
      return job!.errorMessage!.trim();
    }
    if (event?.message?.trim().isNotEmpty == true) {
      return event!.message!.trim();
    }
    return switch (job?.jobType) {
      'storefront_theme' =>
        'Piki is composing your storefront from the latest saved brief.',
      'storefront_page' =>
        'Piki is composing the layout and content for this page.',
      'marketing_content' || 'storefront_marketing' =>
        'Piki is preparing your campaign from verified store information.',
      _ => 'Piki is processing the latest saved information.',
    };
  }

  static String _statusLabel(PikiAiJob? job, bool isFailed, bool isComplete) {
    if (isFailed) return 'ACTION NEEDED';
    if (isComplete) return 'PIKI FINISHED';
    if (job?.status == 'queued') return 'QUEUED IN PIKI CLOUD';
    return 'PIKI IS WORKING NOW';
  }
}

class _AnimatedPikiOrb extends StatelessWidget {
  final AnimationController controller;
  final bool active;
  final Color color;
  final IconData icon;
  final Duration duration;

  const _AnimatedPikiOrb({
    required this.controller,
    required this.active,
    required this.color,
    required this.icon,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final pulse = active ? controller.value : 0.0;
        return Transform.scale(
          scale: 1 + (pulse * 0.045),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.07 + (pulse * 0.05)),
              border: Border.all(
                color: color.withValues(alpha: 0.18 + (pulse * 0.16)),
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: AnimatedSwitcher(
                duration: duration,
                child: Icon(icon, key: ValueKey(icon), color: color, size: 23),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CurrentPikiStage extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String message;
  final Color color;

  const _CurrentPikiStage({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                eyebrow,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

IconData _eventIcon(PikiAiJobEvent? event, PikiAiJob? job) {
  if (job?.isFailed == true || event?.isError == true) {
    return Icons.error_outline_rounded;
  }
  if (event?.isWarning == true) return Icons.warning_amber_outlined;
  return switch (event?.eventType) {
    'file_received' => Icons.upload_file_outlined,
    'file_parsed' => Icons.description_outlined,
    'ai_extracting' => Icons.auto_awesome,
    'products_found' => Icons.inventory_2_outlined,
    'duplicate_check' => Icons.manage_search_outlined,
    'product_prepared' => Icons.playlist_add_check,
    'review_required' => Icons.fact_check_outlined,
    'job_queued' => Icons.cloud_queue_outlined,
    'storefront_brief' || 'page_brief' => Icons.notes_rounded,
    'storefront_planning' || 'page_planning' => Icons.account_tree_outlined,
    'storefront_designing' => Icons.auto_awesome_rounded,
    'storefront_validating' || 'page_validating' => Icons.fact_check_outlined,
    'storefront_saving' => Icons.cloud_upload_outlined,
    'storefront_ready' => Icons.web_asset_rounded,
    'page_ready' => Icons.web_stories_outlined,
    'marketing_context' => Icons.inventory_2_outlined,
    'marketing_writing' => Icons.edit_note_rounded,
    'marketing_validating' => Icons.fact_check_outlined,
    'marketing_ready' => Icons.campaign_outlined,
    'completed' => Icons.check_circle_outline,
    _ when job?.status == 'queued' => Icons.cloud_queue_outlined,
    _ => Icons.bolt_outlined,
  };
}
