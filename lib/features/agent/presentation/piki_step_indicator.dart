import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../data/piki_models.dart';

/// Horizontal step-progress indicator used inside the "Working on it" card.
class PikiStepIndicator extends StatelessWidget {
  final List<PikiStep> steps;
  final int currentIndex;

  const PikiStepIndicator({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Circles + lines ──────────────────────────────────────────────
        Row(
          children: List.generate(steps.length * 2 - 1, (i) {
            if (i.isOdd) {
              // Connector line
              final stepBefore = i ~/ 2;
              final done = steps[stepBefore].status == PikiStepStatus.done;
              return Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: done
                        ? AppColors.primary
                        : context.appBorder,
                  ),
                ),
              );
            }

            final stepIndex = i ~/ 2;
            final step = steps[stepIndex];
            return _StepCircle(step: step);
          }),
        ),

        const SizedBox(height: 8),

        // ── Labels ───────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: steps.map((step) {
            final isDone = step.status == PikiStepStatus.done;
            final isActive = step.status == PikiStepStatus.working;
            return Expanded(
              child: Text(
                step.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: (isDone || isActive)
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: isDone
                      ? Theme.of(context).colorScheme.onSurface
                      : isActive
                          ? AppColors.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Individual circle ──────────────────────────────────────────────────────

class _StepCircle extends StatelessWidget {
  final PikiStep step;
  const _StepCircle({required this.step});

  @override
  Widget build(BuildContext context) {
    const size = 28.0;

    switch (step.status) {
      case PikiStepStatus.done:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
          ),
          child: const Icon(Icons.check, size: 16, color: Colors.white),
        );

      case PikiStepStatus.working:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: 0.15),
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: const Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          ),
        );

      case PikiStepStatus.error:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.error,
          ),
          child: const Icon(Icons.close, size: 16, color: Colors.white),
        );

      case PikiStepStatus.pending:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 2),
          ),
        );
    }
  }
}
