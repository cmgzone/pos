import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../application/training_controller.dart';
import '../data/training_models.dart';

class TrainingHubScreen extends ConsumerStatefulWidget {
  const TrainingHubScreen({super.key});

  @override
  ConsumerState<TrainingHubScreen> createState() => _TrainingHubScreenState();
}

class _TrainingHubScreenState extends ConsumerState<TrainingHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(trainingControllerProvider).ensureLoadedForCurrentUser();
    });
  }

  Future<void> _confirmResetProgress() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Reset Training Progress'),
        content: Text(
          'Reset the saved training progress for the current user only?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(trainingControllerProvider).resetProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Training progress reset for this user'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final training = ref.watch(trainingControllerProvider);
    final modules = training.availableModules;
    final roleLabel = RolePermissions.label(SessionService.currentUserRole);
    final progressPercent = (training.completionRatio * 100).round();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Training Hub'),
        actions: [
          if (training.completedModuleCount > 0)
            TextButton.icon(
              onPressed: _confirmResetProgress,
              icon: Icon(Icons.restart_alt, size: 18),
              label: Text('Reset Progress'),
            ),
          SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primaryLight,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.school_outlined,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Train On The Live App',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Each guide runs on top of the real screens, saves progress for ${SessionService.currentUserName}, and adapts to the current $roleLabel permissions.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _TrainingStat(
                            label: 'Completed',
                            value:
                                '${training.completedModuleCount}/${training.availableModuleCount}',
                            color: AppColors.success,
                          ),
                          _TrainingStat(
                            label: 'Progress',
                            value: '$progressPercent%',
                            color: AppColors.primary,
                          ),
                          _TrainingStat(
                            label: 'Role',
                            value: roleLabel,
                            color: AppColors.warning,
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: modules.isEmpty
                                ? null
                                : () => ref
                                      .read(trainingControllerProvider)
                                      .startFullTour(),
                            icon: Icon(Icons.play_circle_outline),
                            label: Text('Start Full Tour'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
                          ),
                          if (training.isActive)
                            OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.visibility_outlined),
                              label: Text('Resume Active Training'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  'Modules',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: modules
                      .map(
                        (module) => SizedBox(
                          width: 330,
                          child: _TrainingModuleCard(
                            module: module,
                            stepCount: module.stepCountForRole(
                              RolePermissions.normalizeRole(
                                SessionService.currentUserRole,
                              ),
                            ),
                            isCompleted: training.isModuleCompleted(module.id),
                            onStart: () => ref
                                .read(trainingControllerProvider)
                                .startModule(module.id),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrainingModuleCard extends StatelessWidget {
  final TrainingModule module;
  final int stepCount;
  final bool isCompleted;
  final VoidCallback onStart;

  const _TrainingModuleCard({
    required this.module,
    required this.stepCount,
    required this.isCompleted,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCompleted ? AppColors.success.withValues(alpha: 0.35) : context.appBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(module.icon, color: AppColors.primaryLight),
              ),
              Spacer(),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Completed',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            module.title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text(
            module.description,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          SizedBox(height: 14),
          Text(
            '$stepCount guided step${stepCount == 1 ? '' : 's'}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: Icon(isCompleted ? Icons.refresh : Icons.play_arrow),
              label: Text(isCompleted ? 'Review Module' : 'Start Module'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _TrainingStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
