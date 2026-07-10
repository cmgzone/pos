import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../data/piki_models.dart';
import '../data/piki_work_notes.dart';
import 'piki_step_indicator.dart';

/// A task-oriented surface for Piki. It intentionally presents the active
/// mission, execution trace, and latest output instead of a chat transcript.
class PikiAgentWorkspace extends StatelessWidget {
  final List<PikiMessage> messages;
  final AgentStatus status;
  final PikiMode mode;
  final ValueChanged<String> onSendPrompt;

  const PikiAgentWorkspace({
    super.key,
    required this.messages,
    required this.status,
    required this.mode,
    required this.onSendPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final state = _WorkspaceState.fromMessages(messages);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1120;
        final content = isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 292,
                    child: _MissionPanel(
                      state: state,
                      status: status,
                      mode: mode,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _OutputPanel(
                      state: state,
                      status: status,
                      onSendPrompt: onSendPrompt,
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(width: 292, child: _ActivityPanel(state: state)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _MissionPanel(state: state, status: status, mode: mode),
                  const SizedBox(height: 14),
                  _OutputPanel(
                    state: state,
                    status: status,
                    onSendPrompt: onSendPrompt,
                  ),
                  const SizedBox(height: 14),
                  _ActivityPanel(state: state),
                ],
              );

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: content,
        );
      },
    );
  }
}

class _WorkspaceState {
  final PikiMessage? mission;
  final PikiMessage? liveMessage;
  final PikiMessage? output;
  final List<PikiWorkNote> notes;
  final List<Map<String, dynamic>> toolResults;

  const _WorkspaceState({
    required this.mission,
    required this.liveMessage,
    required this.output,
    required this.notes,
    required this.toolResults,
  });

  factory _WorkspaceState.fromMessages(List<PikiMessage> messages) {
    PikiMessage? mission;
    PikiMessage? liveMessage;
    PikiMessage? output;

    for (final message in messages.reversed) {
      if (mission == null && message.sender == PikiSender.user) {
        mission = message;
      }
      if (liveMessage == null &&
          message.sender == PikiSender.agent &&
          (message.messageType == PikiMessageType.thinking ||
              message.messageType == PikiMessageType.working)) {
        liveMessage = message;
      }
      if (output == null &&
          message.sender == PikiSender.agent &&
          message.messageType != PikiMessageType.thinking &&
          message.messageType != PikiMessageType.working) {
        output = message;
      }
      if (mission != null && liveMessage != null && output != null) break;
    }

    final metadata = liveMessage?.attachedData ?? output?.attachedData;
    final notes = PikiWorkNote.listFromJson(metadata?['work_notes']);
    return _WorkspaceState(
      mission: mission,
      liveMessage: liveMessage,
      output: output,
      notes: notes,
      toolResults: _toolResultsFrom(output),
    );
  }

  bool get isLive => liveMessage != null;

  static List<Map<String, dynamic>> _toolResultsFrom(PikiMessage? output) {
    final data = output?.attachedData;
    final direct = data?['tool_results'];
    if (direct is List) {
      return direct
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    final legacy = data?['results'];
    if (legacy is Map) {
      return legacy.values
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }
}

class _MissionPanel extends StatelessWidget {
  final _WorkspaceState state;
  final AgentStatus status;
  final PikiMode mode;

  const _MissionPanel({
    required this.state,
    required this.status,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _modeColor(context, mode);
    final steps = state.liveMessage?.steps ?? const <PikiStep>[];
    return _WorkspacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PanelGlyph(icon: Icons.hub_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mission control',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusDot(status: status),
            ],
          ),
          const SizedBox(height: 20),
          Text('CURRENT TASK', style: _eyebrowStyle(context)),
          const SizedBox(height: 8),
          Text(
            state.mission?.content.trim().isNotEmpty == true
                ? state.mission!.content
                : 'Assign Piki a task to start an agent run.',
            maxLines: 7,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.45,
              fontWeight: state.mission == null
                  ? FontWeight.w400
                  : FontWeight.w600,
              color: state.mission == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 18),
          Divider(color: theme.colorScheme.outlineVariant, height: 1),
          const SizedBox(height: 18),
          Text('OPERATING MODE', style: _eyebrowStyle(context)),
          const SizedBox(height: 8),
          _ModeStrip(mode: mode),
          const SizedBox(height: 20),
          Text('EXECUTION PLAN', style: _eyebrowStyle(context)),
          const SizedBox(height: 10),
          if (steps.isEmpty)
            _EmptyPlan(
              isLive: state.isLive,
              message: state.liveMessage?.content,
            )
          else
            ...steps.map(
              (step) => _PlanStepRow(step: step, isLive: state.isLive),
            ),
        ],
      ),
    );
  }
}

class _OutputPanel extends StatelessWidget {
  final _WorkspaceState state;
  final AgentStatus status;
  final ValueChanged<String> onSendPrompt;

  const _OutputPanel({
    required this.state,
    required this.status,
    required this.onSendPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final output = state.output;
    final liveSteps = state.liveMessage?.steps ?? const <PikiStep>[];
    final isError = output?.messageType == PikiMessageType.error;
    return _WorkspacePanel(
      accent: isError ? AppColors.error : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PanelGlyph(
                icon: state.isLive
                    ? Icons.memory_rounded
                    : output == null
                    ? Icons.auto_awesome_rounded
                    : isError
                    ? Icons.error_outline_rounded
                    : Icons.outbox_rounded,
                color: state.isLive
                    ? AppColors.primary
                    : isError
                    ? AppColors.error
                    : theme.colorScheme.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.isLive
                      ? 'Agent run in progress'
                      : output == null
                      ? 'Ready for a mission'
                      : isError
                      ? 'Run needs attention'
                      : 'Latest output',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (state.isLive) const _LivePill(),
              if (!state.isLive && output != null)
                Text(
                  _timeLabel(output.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (state.isLive) ...[
            Text(
              state.liveMessage?.content ?? 'Piki is executing the plan.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (liveSteps.isNotEmpty) ...[
              const SizedBox(height: 22),
              PikiStepIndicator(
                steps: liveSteps,
                currentIndex: liveSteps.indexWhere(
                  (step) => step.status == PikiStepStatus.working,
                ),
              ),
            ],
            const SizedBox(height: 22),
            _LiveExecutionList(steps: liveSteps),
          ] else if (output == null)
            const _ReadyOutput()
          else ...[
            if (isError)
              _ErrorOutput(message: output.content)
            else
              MarkdownBody(
                data: output.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  listBullet: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  h1: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  h2: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  h3: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (state.toolResults.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('GROUNDING', style: _eyebrowStyle(context)),
              const SizedBox(height: 8),
              _ToolResults(results: state.toolResults),
            ],
            if (output.suggestions?.isNotEmpty == true) ...[
              const SizedBox(height: 18),
              Text('NEXT BEST ACTIONS', style: _eyebrowStyle(context)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: output.suggestions!
                    .map(
                      (suggestion) => ActionChip(
                        avatar: const Icon(
                          Icons.arrow_outward_rounded,
                          size: 15,
                        ),
                        label: Text(suggestion),
                        onPressed: () => onSendPrompt(suggestion),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  final _WorkspaceState state;

  const _ActivityPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = state.notes.length > 8
        ? state.notes.sublist(state.notes.length - 8)
        : state.notes;
    return _WorkspacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PanelGlyph(
                icon: Icons.account_tree_outlined,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 10),
              Text(
                'Run trace',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (notes.isEmpty)
            Text(
              'Piki will show the plan, local checks, and safety stops here while it works.',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...notes.map((note) => _TraceRow(note: note)),
        ],
      ),
    );
  }
}

class _WorkspacePanel extends StatelessWidget {
  final Widget child;
  final Color? accent;

  const _WorkspacePanel({required this.child, this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (accent ?? theme.colorScheme.outlineVariant).withValues(
            alpha: accent == null ? 1 : 0.45,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PanelGlyph extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _PanelGlyph({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final AgentStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AgentStatus.idle => Theme.of(context).colorScheme.onSurfaceVariant,
      AgentStatus.thinking => AppColors.warning,
      AgentStatus.working => AppColors.primary,
      AgentStatus.completed => AppColors.success,
    };
    return Tooltip(
      message: status.name,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _ModeStrip extends StatelessWidget {
  final PikiMode mode;

  const _ModeStrip({required this.mode});

  @override
  Widget build(BuildContext context) {
    final color = _modeColor(context, mode);
    final (icon, label, detail) = switch (mode) {
      PikiMode.plan => (
        Icons.route_rounded,
        'Plan mode',
        'Breaks work into grounded steps',
      ),
      PikiMode.fast => (
        Icons.bolt_rounded,
        'Fast mode',
        'Runs concise local checks',
      ),
      PikiMode.sell => (
        Icons.point_of_sale_rounded,
        'Sell mode',
        'Prepares POS actions for confirmation',
      ),
      PikiMode.advice => (
        Icons.lightbulb_rounded,
        'Advice mode',
        'Turns data into business guidance',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  detail,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
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

class _EmptyPlan extends StatelessWidget {
  final bool isLive;
  final String? message;

  const _EmptyPlan({required this.isLive, this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      isLive
          ? message ?? 'Piki is preparing the execution plan.'
          : 'The plan will appear here as soon as Piki receives a task.',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        height: 1.45,
      ),
    );
  }
}

class _PlanStepRow extends StatelessWidget {
  final PikiStep step;
  final bool isLive;

  const _PlanStepRow({required this.step, required this.isLive});

  @override
  Widget build(BuildContext context) {
    final color = switch (step.status) {
      PikiStepStatus.done => AppColors.success,
      PikiStepStatus.working => AppColors.primary,
      PikiStepStatus.error => AppColors.error,
      PikiStepStatus.pending => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final icon = switch (step.status) {
      PikiStepStatus.done => Icons.check_circle_rounded,
      PikiStepStatus.working => Icons.sync_rounded,
      PikiStepStatus.error => Icons.error_outline_rounded,
      PikiStepStatus.pending => step.icon,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: step.status == PikiStepStatus.pending
                        ? FontWeight.w600
                        : FontWeight.w800,
                  ),
                ),
                if (step.description.isNotEmpty)
                  Text(
                    step.description,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.35,
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

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 9,
            height: 9,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveExecutionList extends StatelessWidget {
  final List<PikiStep> steps;

  const _LiveExecutionList({required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    return Column(
      children: steps
          .map(
            (step) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(step.icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (step.status == PikiStepStatus.working)
                    const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (step.status == PikiStepStatus.done)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 18,
                    ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ReadyOutput extends StatelessWidget {
  const _ReadyOutput();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 42,
            color: AppColors.primary,
          ),
          const SizedBox(height: 14),
          Text(
            'What should Piki own next?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Give Piki a business goal. It will show its plan, run grounded checks, and ask before every data-changing action.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorOutput extends StatelessWidget {
  final String message;

  const _ErrorOutput({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ToolResults extends StatelessWidget {
  final List<Map<String, dynamic>> results;

  const _ToolResults({required this.results});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: results.take(6).map((result) {
        final failed = result['success'] == false || result['error'] != null;
        final title = (result['title'] ?? result['tool'] ?? 'Local check')
            .toString()
            .replaceAll('_', ' ');
        final summary = (result['summary'] ?? result['error'] ?? '')
            .toString()
            .trim();
        final color = failed ? AppColors.error : AppColors.success;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                failed ? Icons.error_outline_rounded : Icons.verified_outlined,
                color: color,
                size: 17,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleCase(title),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    if (summary.isNotEmpty)
                      Text(
                        summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TraceRow extends StatelessWidget {
  final PikiWorkNote note;

  const _TraceRow({required this.note});

  @override
  Widget build(BuildContext context) {
    final color = switch (note.stage) {
      'error' => AppColors.error,
      'blocked' => AppColors.warning,
      'done' => AppColors.success,
      'tool' || 'result' => AppColors.primary,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.loop == null
                      ? note.title
                      : '${note.title} · ${note.loop}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (note.detail.isNotEmpty)
                  Text(
                    note.detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.35,
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

TextStyle _eyebrowStyle(BuildContext context) => TextStyle(
  color: Theme.of(context).colorScheme.onSurfaceVariant,
  fontSize: 10,
  letterSpacing: 1.05,
  fontWeight: FontWeight.w800,
);

Color _modeColor(BuildContext context, PikiMode mode) => switch (mode) {
  PikiMode.plan => Theme.of(context).colorScheme.secondary,
  PikiMode.fast => AppColors.warning,
  PikiMode.sell => const Color(0xFF00A878),
  PikiMode.advice => const Color(0xFF8E4EC6),
};

String _timeLabel(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _titleCase(String value) => value
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
