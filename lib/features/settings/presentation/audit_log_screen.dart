import 'package:flutter/material.dart';


import '../../../core/services/audit_log_service.dart';
import '../../../core/services/branch_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../training/widgets/training_anchor.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  late Future<List<Map<String, dynamic>>> _logsFuture;
  bool _currentBranchOnly = false;

  /// Cache of branch_id → branch_name, populated once at load time.
  Map<String, String> _branchNames = {};

  @override
  void initState() {
    super.initState();
    _loadBranchNames();
    _logsFuture = _loadLogs();
  }

  Future<void> _loadBranchNames() async {
    final branches = await BranchService.getBranches();
    if (!mounted) return;
    final map = <String, String>{};
    for (final b in branches) {
      final id = b['id'] as String? ?? '';
      final name = b['name'] as String? ?? id;
      if (id.isNotEmpty) map[id] = name;
    }
    setState(() => _branchNames = map);
  }

  String _branchLabel(String? branchId) {
    if (branchId == null || branchId.isEmpty) return 'Main';
    if (branchId == DatabaseService.defaultBranchId) return 'Main';
    return _branchNames[branchId] ?? branchId;
  }

  Future<List<Map<String, dynamic>>> _loadLogs() {
    return AuditLogService.getRecent(
      branchId: _currentBranchOnly ? BranchService.currentBranchId : null,
      limit: 150,
    );
  }

  void _refresh() {
    setState(() => _logsFuture = _loadLogs());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentBranchLabel = _branchLabel(BranchService.currentBranchId);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Audit Logs'),
            SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.store_outlined,
                    size: 12,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 4),
                  Text(
                    currentBranchLabel,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Text('Current branch only', style: TextStyle(fontSize: 12)),
              Switch(
                value: _currentBranchOnly,
                onChanged: (value) {
                  setState(() {
                    _currentBranchOnly = value;
                    _logsFuture = _loadLogs();
                  });
                },
              ),
            ],
          ),
          IconButton(onPressed: _refresh, icon: Icon(Icons.refresh)),
          SizedBox(width: 8),
        ],
      ),
      body: TrainingAnchor(
        id: 'auditLogs.workspace',
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _logsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            final logs = snapshot.data ?? [];
            if (logs.isEmpty) {
              return Center(
                child: Text(
                  'No audit activity yet.',
                  style: theme.textTheme.bodyMedium,
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: logs.length,
              separatorBuilder: (_, _) => SizedBox(height: 10),
              itemBuilder: (context, index) {
                final log = logs[index];
                final action = log['action'] as String? ?? 'change';
                final branchId = log['branch_id'] as String?;
                final branchName = _branchLabel(branchId);
                final color = switch (action) {
                  'create' => AppColors.success,
                  'update' => AppColors.warning,
                  'delete' => AppColors.error,
                  _ => AppColors.primaryLight,
                };
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.outline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_iconFor(action), color: color, size: 20),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${action.toUpperCase()} ${log['entity_table'] ?? ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  log['user_name'] as String? ?? 'Unknown user',
                                  style: theme.textTheme.bodySmall,
                                ),
                                if ((log['user_role'] as String? ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  Text(
                                    '(${log['user_role']})',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                // Branch chip
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.store_outlined,
                                        size: 10,
                                        color: AppColors.primaryLight,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        branchName,
                                        style: TextStyle(
                                          color: AppColors.primaryLight,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDate(log['created_at']),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  IconData _iconFor(String action) {
    return switch (action) {
      'create' => Icons.add_circle_outline,
      'update' => Icons.edit_outlined,
      'delete' => Icons.delete_outline,
      _ => Icons.history,
    };
  }

  String _formatDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      return '';
    }
    return '${parsed.month}/${parsed.day}/${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }
}
