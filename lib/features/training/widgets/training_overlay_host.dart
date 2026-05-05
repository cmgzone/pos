import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/training_controller.dart';
import '../data/training_models.dart';
import 'training_anchor.dart';

class TrainingOverlayHost extends ConsumerStatefulWidget {
  final Widget child;

  const TrainingOverlayHost({required this.child, super.key});

  @override
  ConsumerState<TrainingOverlayHost> createState() =>
      _TrainingOverlayHostState();
}

class _TrainingOverlayHostState extends ConsumerState<TrainingOverlayHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final training = ref.watch(trainingControllerProvider);
    final step = training.currentStep;
    final module = training.activeModule;

    if (!training.isActive || step == null || module == null) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final targetRect = _spotlightRectFor(step.anchorId);
                return CustomPaint(
                  painter: _TrainingSpotlightPainter(
                    targetRect: targetRect,
                    pulseValue: _pulseController.value,
                  ),
                );
              },
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final targetRect = _spotlightRectFor(step.anchorId);
                return _buildTrainingCard(
                  context: context,
                  constraints: constraints,
                  training: training,
                  module: module,
                  step: step,
                  targetRect: targetRect,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Rect? _spotlightRectFor(String? anchorId) {
    if (anchorId == null || anchorId.isEmpty) {
      return null;
    }
    return TrainingAnchorRegistry.instance.rectFor(anchorId)?.inflate(10);
  }

  Widget _buildTrainingCard({
    required BuildContext context,
    required BoxConstraints constraints,
    required TrainingController training,
    required TrainingModule module,
    required TrainingStep step,
    required Rect? targetRect,
  }) {
    final cardWidth = math.min(380.0, constraints.maxWidth - 32);
    final card = _TrainingPanel(
      key: ValueKey('${module.id}:${step.id}'),
      moduleTitle: module.title,
      stepNumber: training.currentStepNumber,
      totalSteps: training.totalStepCount,
      title: step.title,
      description: step.description,
      canGoBack: training.canGoBack,
      nextLabel: training.nextButtonLabel,
      showReplayAction: step.action != TrainingStepAction.none,
      replayLabel: training.actionLabelFor(step),
      anchorMissing: step.anchorId != null && targetRect == null,
      onClose: () => ref.read(trainingControllerProvider).cancelTraining(),
      onBack: training.canGoBack
          ? () => ref.read(trainingControllerProvider).previousStep()
          : null,
      onNext: () => ref.read(trainingControllerProvider).nextStep(),
      onReplay: step.action != TrainingStepAction.none
          ? () => ref.read(trainingControllerProvider).replayCurrentStepAction()
          : null,
    );

    if (targetRect == null) {
      return Center(
        child: SizedBox(
          width: cardWidth,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: card,
          ),
        ),
      );
    }

    final left = targetRect.left.clamp(
      16.0,
      constraints.maxWidth - cardWidth - 16.0,
    );
    final roomBelow = constraints.maxHeight - targetRect.bottom;
    final showBelow =
        roomBelow > 240 || targetRect.center.dy < constraints.maxHeight * 0.45;
    final top = showBelow
        ? math.min(targetRect.bottom + 18, constraints.maxHeight - 240)
        : math.max(16.0, targetRect.top - 230);

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: cardWidth,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: card,
          ),
        ),
      ],
    );
  }
}

class _TrainingPanel extends StatelessWidget {
  final String moduleTitle;
  final int stepNumber;
  final int totalSteps;
  final String title;
  final String description;
  final bool canGoBack;
  final String nextLabel;
  final bool showReplayAction;
  final String replayLabel;
  final bool anchorMissing;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback? onReplay;

  const _TrainingPanel({
    required this.moduleTitle,
    required this.stepNumber,
    required this.totalSteps,
    required this.title,
    required this.description,
    required this.canGoBack,
    required this.nextLabel,
    required this.showReplayAction,
    required this.replayLabel,
    required this.anchorMissing,
    required this.onClose,
    this.onBack,
    required this.onNext,
    this.onReplay,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF151D2D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        moduleTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$stepNumber / $totalSteps',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (anchorMissing) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'The highlighted control is not visible yet. You can keep navigating the live app, or reopen this step action below.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            OverflowBar(
              spacing: 8,
              overflowSpacing: 8,
              alignment: MainAxisAlignment.start,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                TextButton(onPressed: onClose, child: const Text('Close')),
                if (canGoBack)
                  OutlinedButton(onPressed: onBack, child: const Text('Back')),
                if (showReplayAction && onReplay != null)
                  OutlinedButton(onPressed: onReplay, child: Text(replayLabel)),
                FilledButton(onPressed: onNext, child: Text(nextLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingSpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final double pulseValue;

  const _TrainingSpotlightPainter({
    required this.targetRect,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayRect = Offset.zero & size;
    canvas.saveLayer(overlayRect, Paint());

    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.72);
    canvas.drawRect(overlayRect, overlayPaint);

    final rect = targetRect;
    if (rect != null) {
      final hole = RRect.fromRectAndRadius(rect, const Radius.circular(18));
      canvas.drawRRect(hole, Paint()..blendMode = BlendMode.clear);

      final ringRect = rect.inflate(8 + (pulseValue * 12));
      final ring = RRect.fromRectAndRadius(ringRect, const Radius.circular(24));
      canvas.drawRRect(
        ring,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.16 + (pulseValue * 0.16))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TrainingSpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.pulseValue != pulseValue;
  }
}
