import 'package:flutter/material.dart';

import '../core/data/spreadsheet_import_reader.dart';
import '../core/theme/app_colors.dart';

Future<bool> showSmartImportPreviewDialog(
  BuildContext context, {
  required SpreadsheetImportPlan plan,
  required String title,
  required String actionLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title),
      content: SizedBox(
        width: 620,
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
                          backgroundColor: AppColors.surfaceHighlight,
                          side: const BorderSide(color: AppColors.border),
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
                      color: AppColors.surfaceHighlight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
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
