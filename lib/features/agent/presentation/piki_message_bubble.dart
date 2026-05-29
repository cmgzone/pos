import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/utils/error_messages.dart';
import '../data/piki_models.dart';
import '../data/piki_work_notes.dart';
import '../../products/data/product_repository.dart';
import '../../products/data/category_repository.dart';
import '../../../core/services/background_tasks_service.dart';
import 'piki_action_buttons.dart';
import 'piki_step_indicator.dart';
import 'piki_summary_card.dart';

/// Renders a single chat message. Display switches based on [PikiMessageType].
class PikiMessageBubble extends StatelessWidget {
  final PikiMessage message;
  final ValueChanged<String>? onSendPrompt;

  const PikiMessageBubble({
    super.key,
    required this.message,
    this.onSendPrompt,
  });

  String get _timeLabel {
    final t = message.timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (message.sender == PikiSender.user) return _buildUserBubble();

    Widget child;
    switch (message.messageType) {
      case PikiMessageType.thinking:
        child = _buildThinkingCard();
        break;
      case PikiMessageType.working:
        child = _buildWorkingCard();
        break;
      case PikiMessageType.taskComplete:
        child = _buildTaskCompleteCard();
        break;
      case PikiMessageType.productCard:
        child = _buildProductCard();
        break;
      case PikiMessageType.productDraftCard:
        child = _buildProductDraftCard(context);
        break;
      case PikiMessageType.error:
        child = _buildErrorBubble();
        break;
      case PikiMessageType.aiResponse:
        child = _buildAiResponseBubble();
        break;
      case PikiMessageType.alert:
        child = _buildAlertBubble();
        break;
      case PikiMessageType.chart:
        child = _buildChartBubble();
        break;
      case PikiMessageType.text:
        child = _buildAgentTextBubble();
        break;
    }

    if (message.suggestions != null && message.suggestions!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 12),
          _buildSuggestionChips(),
          const SizedBox(height: 12),
        ],
      );
    }

    return child;
  }

  Widget _buildSuggestionChips() {
    return Padding(
      padding: const EdgeInsets.only(left: 48),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: message.suggestions!.map((s) {
          return InkWell(
            onTap: () => onSendPrompt?.call(s),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.reply, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      s,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Alert bubble ──────────────────────────────────────────────────────────

  Widget _buildThoughtsExpander() {
    final notes = PikiWorkNote.listFromJson(
      message.attachedData?['work_notes'],
    );
    if (notes.isEmpty) return const SizedBox.shrink();

    PikiRunState? runState;
    final rawRunState = message.attachedData?['run_state'];
    if (rawRunState is Map) {
      runState = PikiRunState.fromJson(Map<String, dynamic>.from(rawRunState));
    }

    return _PikiThoughtsExpander(notes: notes, runState: runState);
  }

  Widget _buildAlertBubble() {
    final data = message.attachedData ?? {};
    final title = data['title'] as String? ?? 'Alert';
    final priority = data['priority'] as String? ?? 'medium';
    final details = data['details'] as String? ?? '';
    final suggestion = data['suggestion'] as String? ?? '';
    final action = data['action'] as String?;

    final color = priority == 'high' ? AppColors.warning : AppColors.secondary;

    return _AgentRow(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  priority == 'high' ? Icons.error_outline : Icons.info_outline,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message.content,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                details,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (suggestion.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        suggestion,
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => onSendPrompt?.call(suggestion),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text(
                    'Take Action',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Chart bubble ──────────────────────────────────────────────────────────

  Widget _buildChartBubble() {
    final data = message.attachedData ?? {};
    final results =
        (data['tool_results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final chartData = results.firstWhere(
      (r) => r['type'] == 'chart',
      orElse: () => {},
    );

    if (chartData.isEmpty) return _buildAgentTextBubble();

    final title = chartData['title'] as String? ?? 'Data Visualization';
    final labels =
        (chartData['labels'] as List?)
            ?.map((label) => label.toString())
            .toList() ??
        <String>[];
    final values =
        (chartData['values'] as List?)?.map((value) {
          if (value is num) return value;
          return num.tryParse(value.toString()) ?? 0;
        }).toList() ??
        <num>[];
    final chartItems = _chartItemsFromData(chartData, labels, values);
    final maxValue = values.fold<double>(
      0,
      (max, value) => value.toDouble() > max ? value.toDouble() : max,
    );

    return _AgentRow(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxValue <= 0 ? 10 : maxValue * 1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= labels.length) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              labels[index].length > 6
                                  ? '${labels[index].substring(0, 5)}..'
                                  : labels[index],
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(values.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i].toDouble(),
                          color: AppColors.primary,
                          width: 16,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            if (chartItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildChartProductStrip(chartItems, values),
            ],
            const SizedBox(height: 16),
            if (message.content.isNotEmpty)
              Text(
                message.content,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            _buildThoughtsExpander(),
          ],
        ),
      ),
    );
  }

  // ── Chart helpers ──────────────────────────────────────────────────────

  List<Map<String, dynamic>> _chartItemsFromData(
    Map<String, dynamic> chartData,
    List<String> labels,
    List<num> values,
  ) {
    final items =
        (chartData['items'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (items.isNotEmpty) return items;

    final count = labels.length < values.length ? labels.length : values.length;
    return List.generate(count, (index) {
      return {'label': labels[index], 'value': values[index]};
    });
  }

  Widget _buildChartProductStrip(
    List<Map<String, dynamic>> items,
    List<num> values,
  ) {
    var visibleCount = items.length < values.length
        ? items.length
        : values.length;
    if (visibleCount > 6) visibleCount = 6;
    if (visibleCount <= 0) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(visibleCount, (index) {
        final item = items[index];
        final label = item['label'] as String? ?? 'Item';
        final value = item['value'] is num
            ? item['value'] as num
            : values[index];
        final imagePath = item['image_url']?.toString();
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              children: [
                _buildChartProductImage(imagePath),
                const SizedBox(height: 6),
                Text(
                  _formatCompactNumber(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildChartProductImage(String? imagePath) {
    const size = 36.0;
    final cleanPath = imagePath?.trim();
    if (cleanPath == null || cleanPath.isEmpty) {
      return _buildChartImagePlaceholder(size);
    }

    Widget image;
    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      image = Image.network(
        cleanPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildChartImagePlaceholder(size),
      );
    } else {
      var filePath = cleanPath;
      if (cleanPath.startsWith('file://')) {
        filePath = Uri.parse(cleanPath).toFilePath();
      }

      try {
        final file = File(filePath);
        if (!file.existsSync()) return _buildChartImagePlaceholder(size);
        image = Image.file(file, width: size, height: size, fit: BoxFit.cover);
      } catch (_) {
        return _buildChartImagePlaceholder(size);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(width: size, height: size, child: image),
    );
  }

  Widget _buildChartImagePlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: const Icon(
        Icons.inventory_2_rounded,
        size: 17,
        color: AppColors.primary,
      ),
    );
  }

  String _formatCompactNumber(num value) {
    final number = value.toDouble();
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(number >= 10000000 ? 0 : 1)}M';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(number >= 10000 ? 0 : 1)}K';
    }
    if (number == number.roundToDouble()) {
      return number.toStringAsFixed(0);
    }
    return number.toStringAsFixed(1);
  }

  // ── User bubble ────────────────────────────────────────────────────────

  Widget _buildUserBubble() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 12, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFFCC2250)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSendPrompt != null)
                  InkWell(
                    onTap: () => onSendPrompt?.call(message.content),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: 8.0,
                        top: 2,
                        bottom: 2,
                        left: 2,
                      ),
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                Text(
                  _timeLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.done_all,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Agent text bubble ──────────────────────────────────────────────────

  Widget _buildAgentTextBubble() {
    return _AgentRow(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          message.content,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  // ── Thinking card ──────────────────────────────────────────────────────

  Widget _buildThinkingCard() {
    final steps = message.steps ?? [];
    return _AgentRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Row(
            children: [
              Text(
                'Thinking...',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 6),
              _AnimatedDots(),
            ],
          ),
          const SizedBox(height: 12),

          // Task list
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceHighlight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: steps.map((step) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Icon(step.icon, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              step.description,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StepStatusIcon(status: step.status),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          _buildThoughtsExpander(),
        ],
      ),
    );
  }

  // ── Working card ───────────────────────────────────────────────────────

  Widget _buildWorkingCard() {
    final steps = message.steps ?? [];
    final current = steps.indexWhere((s) => s.status == PikiStepStatus.working);

    return _AgentRow(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Working on it',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(current >= 0 ? current + 1 : steps.length)} of ${steps.length}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Text(
              message.content,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            PikiStepIndicator(steps: steps, currentIndex: current),
            _buildThoughtsExpander(),
          ],
        ),
      ),
    );
  }

  // ── Task complete card ─────────────────────────────────────────────────

  Widget _buildTaskCompleteCard() {
    final data = message.attachedData ?? {};
    final details = (data['details'] as List?)?.cast<String>() ?? <String>[];
    final results =
        data['results'] as Map<String, dynamic>? ?? <String, dynamic>{};

    return _AgentRow(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tasks completed',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                const Spacer(),
                Text(
                  _timeLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Detail list
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        detail,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (details.isNotEmpty) const SizedBox(height: 8),

            // Action buttons
            PikiActionButtons(results: results, onSendPrompt: onSendPrompt),
          ],
        ),
      ),
    );
  }

  // ── Product draft card ──────────────────────────────────────────────────

  Widget _buildProductDraftCard(BuildContext context) {
    final data = message.attachedData ?? {};
    final name = data['name'] as String? ?? 'Draft Product';
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final cost = (data['cost'] as num?)?.toDouble() ?? 0.0;
    final stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
    final imageUrl = data['image_url'] as String?;
    final draftArgs = data['draft_args'] as Map<String, dynamic>? ?? {};

    return _AgentRow(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.rate_review_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Product Draft',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120,
                    width: double.infinity,
                    color: AppColors.surface,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Price: ${ShopSettings.currency}${price.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (cost > 0)
              Text(
                'Cost: ${ShopSettings.currency}${cost.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            Text(
              'Initial Stock: $stock',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  // Dispatch product creation and WorkManager task
                  _approveAndSaveDraft(context, draftArgs, imageUrl);
                },
                icon: const Icon(Icons.check),
                label: const Text('Approve & Save'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'By saving, you verify you have the right to use this image.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _approveAndSaveDraft(
    BuildContext context,
    Map<String, dynamic> args,
    String? imageUrl,
  ) async {
    try {
      // Show loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saving product...')));

      // Create product
      final productId = await _createProductFromDraft(args);

      if (imageUrl != null && imageUrl.isNotEmpty) {
        BackgroundTasksService.scheduleImageDownload(productId, imageUrl);
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product saved successfully!')),
      );
      // Tell AI we completed it
      onSendPrompt?.call('I have approved and saved $args["name"].');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          ),
        ),
      );
    }
  }

  Future<String> _createProductFromDraft(Map<String, dynamic> args) async {
    // Fallback simple parsing
    final name = args['name'] ?? args['product_name'] ?? 'Product';
    final price = (args['price'] ?? args['unit_price'] ?? 0).toDouble();
    final cost = (args['cost'] ?? args['unit_cost'] ?? 0).toDouble();
    final stock = (args['stock'] ?? args['initial_stock'] ?? 0).toDouble();
    final unit = args['unit'] ?? args['sale_unit'] ?? 'pcs';
    final lowStock = (args['low_stock'] ?? args['lowStock'] ?? 5).toDouble();

    String? categoryId = args['category_id'];
    if (categoryId == null && args['category'] != null) {
      final categories = await CategoryRepository.getAll();
      final normalized = args['category'].toString().toLowerCase();
      for (final category in categories) {
        if ((category['name'] as String? ?? '').trim().toLowerCase() ==
            normalized) {
          categoryId = category['id'] as String?;
          break;
        }
      }
    }

    final id = await ProductRepository.create(
      name: name,
      price: price,
      cost: cost,
      brand: args['brand'],
      sku: args['sku'],
      barcode: args['barcode'],
      stock: stock,
      lowStock: lowStock,
      unit: unit,
      stockUnit: args['stock_unit'] ?? args['stockUnit'],
      saleUnit: args['sale_unit'] ?? args['saleUnit'],
      purchaseUnit: args['purchase_unit'] ?? args['purchaseUnit'],
      categoryId: categoryId,
      trackStock: args['track_stock'] ?? args['trackStock'] ?? true,
      imageUrl: args['image_url'], // Will be temporarily set to web link
    );
    return id;
  }

  // ── Product card ───────────────────────────────────────────────────────

  Widget _buildProductCard() {
    final data = message.attachedData ?? {};
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final type = data['type'] as String? ?? '';
    final isRestock = type == 'restock_list';

    // Summary-type results get a rich metric card instead of a product list
    const summaryTypes = {
      'today_summary',
      'profit_summary',
      'shift_summary',
      'expiry_check',
      'sales_report',
      'catalog_orders',
    };
    if (summaryTypes.contains(type)) {
      return _AgentRow(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighlight,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              PikiSummaryCard(data: data),
            ],
          ),
        ),
      );
    }

    return _AgentRow(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...items.take(6).map((item) {
              final name =
                  item['name'] as String? ??
                  item['product_name'] as String? ??
                  'Product';
              final stock = (item['stock'] as num? ?? 0).toDouble();
              final unit =
                  item['unit'] as String? ??
                  item['stock_unit'] as String? ??
                  'pcs';
              final lowStock = (item['low_stock'] as num? ?? 5).toDouble();
              final isLow = stock <= lowStock;
              final reorderQty = isRestock
                  ? (item['reorder_qty'] as num? ?? 0).toDouble()
                  : 0.0;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isLow
                        ? AppColors.warning.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (isLow ? AppColors.warning : AppColors.secondary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isLow
                            ? Icons.warning_amber_rounded
                            : Icons.inventory_2_rounded,
                        size: 18,
                        color: isLow ? AppColors.warning : AppColors.secondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Stock: ${stock.toStringAsFixed(stock == stock.roundToDouble() ? 0 : 1)} $unit',
                            style: TextStyle(
                              color: isLow
                                  ? AppColors.warning
                                  : AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isRestock && reorderQty > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Order ${reorderQty.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
            if (items.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ ${items.length - 6} more items',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Error bubble ───────────────────────────────────────────────────────

  Widget _buildErrorBubble() {
    return _AgentRow(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.content,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AI Response bubble ─────────────────────────────────────────────────

  Widget _buildAiResponseBubble() {
    final model = message.attachedData?['model'] as String? ?? '';
    final shortModel = model.contains('/') ? model.split('/').last : model;
    final citations =
        (message.attachedData?['citations'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    return _AgentRow(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(
            color: const Color(0xFF6B4EE6).withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6B4EE6), Color(0xFF00E5FF)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (shortModel.isNotEmpty)
                  Flexible(
                    child: Text(
                      shortModel,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  _timeLabel,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Content
            MarkdownBody(
              data: message.content,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.6,
                ),
                listBullet: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.6,
                ),
                h1: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                h2: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                h3: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                strong: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _buildThoughtsExpander(),
            // ── Dynamic tool result cards ────────────────────────────────
            ..._buildToolResultCards(),
            if (_purchaseDraftPreview != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 16,
                          color: AppColors.secondary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Purchase Draft Preview',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ..._purchaseDraftPreview!.take(3).map((group) {
                      final items =
                          (group['items'] as List?)
                              ?.whereType<Map>()
                              .map((item) => Map<String, dynamic>.from(item))
                              .toList() ??
                          const <Map<String, dynamic>>[];
                      final total = (group['estimated_total'] as num? ?? 0)
                          .toDouble();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighlight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    group['supplier_name'] as String? ??
                                        'Supplier',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${group['item_count'] ?? 0} items',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Estimated total: ${ShopSettings.currency}${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            if (items.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ...items
                                  .take(3)
                                  .map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• ${item['product_name']} - ${(item['recommended_qty'] as num? ?? 0).toString()} ${item['unit'] ?? 'pcs'}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      );
                    }),
                    if (_purchaseDraftPreview!.length > 3)
                      Text(
                        '+ ${_purchaseDraftPreview!.length - 3} more supplier groups',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_hasPendingPurchaseDraftAction) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onSendPrompt == null
                        ? null
                        : () => onSendPrompt!('confirm purchase draft'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text(
                      'Confirm Purchase Draft',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onSendPrompt == null
                        ? null
                        : () => onSendPrompt!('cancel purchase draft'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text(
                      'Cancel Draft',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            if (citations.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.fact_check_outlined,
                          size: 16,
                          color: AppColors.secondary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Sources used',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...citations
                        .take(4)
                        .map(
                          (citation) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 1),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '[${citation['index'] ?? ''}]',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        citation['label'] as String? ??
                                            'Source',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        citation['detail'] as String? ?? '',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? get _purchaseDraftResult {
    final toolResults =
        (message.attachedData?['tool_results'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    for (final result in toolResults) {
      if (result['type'] == 'purchase_draft' &&
          ((result['count'] as num? ?? 0).toInt() > 0)) {
        return result;
      }
    }
    return null;
  }

  List<Map<String, dynamic>>? get _purchaseDraftPreview {
    final result = _purchaseDraftResult;
    if (result == null) {
      return null;
    }
    final groups =
        (result['supplier_groups'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (groups.isEmpty) {
      return null;
    }
    return groups;
  }

  bool get _hasPendingPurchaseDraftAction {
    final result = _purchaseDraftResult;
    if (result == null) {
      return false;
    }
    return ((result['count'] as num? ?? 0).toInt() > 0);
  }

  List<Widget> _buildToolResultCards() {
    final toolResults =
        (message.attachedData?['tool_results'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    if (toolResults.isEmpty) return const [];

    final cards = <Widget>[];

    for (final result in toolResults) {
      final type = result['type'] as String?;
      final success = result['success'] as bool? ?? false;

      if (type == 'create_product' && success) {
        cards.add(
          _buildCard(
            icon: Icons.inventory_2,
            color: AppColors.primary,
            title: 'Product Created',
            subtitle: result['name'] as String? ?? 'New Product',
            value: result['price'] != null
                ? '${ShopSettings.currency}${result['price']}'
                : null,
          ),
        );
      } else if (type == 'create_service' && success) {
        cards.add(
          _buildCard(
            icon: Icons.handyman,
            color: AppColors.secondary,
            title: 'Service Created',
            subtitle: result['name'] as String? ?? 'New Service',
            value: result['price'] != null
                ? '${ShopSettings.currency}${result['price']}'
                : null,
          ),
        );
      } else if (type == 'record_product_sale' && success) {
        cards.add(
          _buildCard(
            icon: Icons.point_of_sale,
            color: AppColors.success,
            title: 'Product Sale Recorded',
            subtitle:
                '${result['quantity']}x ${result['product_name']} (${result['payment_type']})',
            value: result['total'] != null
                ? '${ShopSettings.currency}${result['total']}'
                : null,
          ),
        );
      } else if (type == 'record_service_sale' && success) {
        cards.add(
          _buildCard(
            icon: Icons.receipt_long,
            color: AppColors.success,
            title: 'Service Sale Recorded',
            subtitle: '${result['service_name']} (${result['payment_type']})',
            value: result['total'] != null
                ? '${ShopSettings.currency}${result['total']}'
                : null,
          ),
        );
      } else if (type == 'add_service_field' && success) {
        cards.add(
          _buildCard(
            icon: Icons.format_list_bulleted_add,
            color: AppColors.warning,
            title: 'Field Added',
            subtitle:
                '${result['field_label']} added to ${result['service_name']}',
            value: result['field_type'] as String?,
          ),
        );
      } else if (type == 'web_search' && success) {
        cards.add(_buildWebSearchCard(result));
      }
    }

    if (cards.isEmpty) return const [];

    return [
      const SizedBox(height: 12),
      ...cards.map(
        (card) =>
            Padding(padding: const EdgeInsets.only(bottom: 8.0), child: card),
      ),
    ];
  }

  Widget _buildWebSearchCard(Map<String, dynamic> result) {
    final query = result['query'] as String? ?? 'web search';
    final results =
        (result['results'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.public_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Web search used',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      query,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...results.take(3).map((item) {
              final title = item['title'] as String? ?? 'Web result';
              final source =
                  item['source'] as String? ??
                  item['displayedLink'] as String? ??
                  item['link'] as String? ??
                  '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.link_rounded,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        source.isEmpty ? title : '$title - $source',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    String? value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Wraps agent messages with the Piki avatar.
class _AgentRow extends StatelessWidget {
  final Widget child;
  const _AgentRow({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFFFF7E67)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Text(
                    'P',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PikiThoughtsExpander extends StatefulWidget {
  final List<PikiWorkNote> notes;
  final PikiRunState? runState;

  const _PikiThoughtsExpander({required this.notes, required this.runState});

  @override
  State<_PikiThoughtsExpander> createState() => _PikiThoughtsExpanderState();
}

class _PikiThoughtsExpanderState extends State<_PikiThoughtsExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes.length > 12
        ? widget.notes.sublist(widget.notes.length - 12)
        : widget.notes;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Thoughts',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.notes.length}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.runState != null)
                    _ThoughtRunStateLine(runState: widget.runState!),
                  if (widget.notes.length > notes.length)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Showing latest ${notes.length} of ${widget.notes.length}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ...notes.map((note) => _ThoughtNoteLine(note: note)),
                ],
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
          ),
        ],
      ),
    );
  }
}

class _ThoughtRunStateLine extends StatelessWidget {
  final PikiRunState runState;

  const _ThoughtRunStateLine({required this.runState});

  @override
  Widget build(BuildContext context) {
    final label = runState.completed
        ? 'Completed'
        : runState.needsUserInput
        ? 'Needs input'
        : 'Paused';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '$label after ${runState.loopCount} loop(s), ${runState.toolCount} tool(s). Reason: ${runState.stopReason}.',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}

class _ThoughtNoteLine extends StatelessWidget {
  final PikiWorkNote note;

  const _ThoughtNoteLine({required this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(
              _iconForStage(note.stage),
              size: 11,
              color: _colorForStage(note.stage),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.loop == null
                      ? note.title
                      : '${note.title} - loop ${note.loop}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (note.detail.isNotEmpty)
                  Text(
                    note.detail,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
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

  IconData _iconForStage(String stage) {
    switch (stage) {
      case 'done':
        return Icons.check_circle_outline_rounded;
      case 'error':
      case 'blocked':
        return Icons.info_outline_rounded;
      case 'tool':
        return Icons.build_circle_outlined;
      case 'result':
        return Icons.fact_check_outlined;
      case 'analysis':
        return Icons.manage_search_rounded;
      case 'planning':
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  Color _colorForStage(String stage) {
    switch (stage) {
      case 'done':
        return AppColors.success;
      case 'error':
      case 'blocked':
        return AppColors.warning;
      case 'tool':
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }
}

/// Status icon for individual steps inside the thinking card.
class _StepStatusIcon extends StatelessWidget {
  final PikiStepStatus status;
  const _StepStatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case PikiStepStatus.done:
        return const Icon(
          Icons.check_circle,
          color: AppColors.success,
          size: 20,
        );
      case PikiStepStatus.working:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        );
      case PikiStepStatus.error:
        return const Icon(Icons.error, color: AppColors.error, size: 20);
      case PikiStepStatus.pending:
        return Icon(
          Icons.circle_outlined,
          color: AppColors.textSecondary.withValues(alpha: 0.4),
          size: 20,
        );
    }
  }
}

/// Animated three-dot indicator.
class _AnimatedDots extends StatefulWidget {
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.25;
            final value = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final opacity = (value < 0.5 ? value * 2 : 2 - value * 2).clamp(
              0.3,
              1.0,
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
