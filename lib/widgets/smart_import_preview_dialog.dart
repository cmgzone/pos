import 'package:flutter/material.dart';

import '../core/data/spreadsheet_import_reader.dart';
import '../core/theme/app_colors.dart';

Future<bool> showSmartImportPreviewDialog(
  BuildContext context, {
  required SpreadsheetImportPlan plan,
  required String title,
  required String actionLabel,
  required List<String> minimumRequirements,
  List<String> optionalColumns = const [],
  String? defaultsNote,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width < 800
              ? MediaQuery.of(context).size.width - 32
              : 620,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Piki AI found ${plan.dataRowCount} data row${plan.dataRowCount == 1 ? '' : 's'}'
                '${plan.fileName == null ? '' : ' in ${plan.fileName}'} and selected row ${plan.headerRowNumber} as the header.',
              ),
              const SizedBox(height: 14),
              _ImportRequirementsCard(
                minimumRequirements: minimumRequirements,
                optionalColumns: optionalColumns,
                defaultsNote: defaultsNote,
              ),
              const SizedBox(height: 14),
              const Text(
                'Column Mapping',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (plan.mappedColumns.isEmpty)
                const Text(
                  'No useful columns were detected.',
                  style: TextStyle(color: AppColors.warning),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: plan.mappedColumns.entries
                      .map(
                        (entry) => Chip(
                          label: Text('${entry.key} -> ${entry.value}'),
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (plan.warnings.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Warnings',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                ...plan.warnings
                    .take(6)
                    .map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppColors.warning,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(warning)),
                          ],
                        ),
                      ),
                    ),
              ],
              if (plan.sampleRows.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Preview',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                ...plan.sampleRows.map(
                  (row) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    child: Text(
                      row.entries
                          .where((entry) => entry.value.trim().isNotEmpty)
                          .take(5)
                          .map((entry) => '${entry.key}: ${entry.value}')
                          .join('  |  '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.check),
          label: Text(actionLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _ImportRequirementsCard extends StatelessWidget {
  final List<String> minimumRequirements;
  final List<String> optionalColumns;
  final String? defaultsNote;

  const _ImportRequirementsCard({
    required this.minimumRequirements,
    required this.optionalColumns,
    required this.defaultsNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Minimum columns',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...minimumRequirements.map(
            (requirement) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(requirement)),
                ],
              ),
            ),
          ),
          if (optionalColumns.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Optional: ${optionalColumns.join(', ')}',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (defaultsNote != null && defaultsNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              defaultsNote!,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
