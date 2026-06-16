import 'package:flutter/material.dart';
import 'package:pos_app/features/app/app_shell.dart';

import '../../../core/services/branch_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../training/widgets/training_anchor.dart';

class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  late Future<List<Map<String, dynamic>>> _branchesFuture;

  @override
  void initState() {
    super.initState();
    _branchesFuture = BranchService.getBranches();
  }

  void _refresh() {
    setState(() => _branchesFuture = BranchService.getBranches());
  }

  Future<void> _showBranchDialog([Map<String, dynamic>? branch]) async {
    final nameController = TextEditingController(
      text: branch?['name'] as String? ?? '',
    );
    final codeController = TextEditingController(
      text: branch?['code'] as String? ?? '',
    );
    final phoneController = TextEditingController(
      text: branch?['phone'] as String? ?? '',
    );
    final addressController = TextEditingController(
      text: branch?['address'] as String? ?? '',
    );
    var isActive = (branch?['is_active'] as num? ?? 1) == 1;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(branch == null ? 'Add Branch' : 'Edit Branch'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Branch Name',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Branch Code',
                      prefixIcon: Icon(Icons.tag_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: isActive,
                    onChanged: (value) =>
                        setDialogState(() => isActive = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        if (branch == null) {
                          await BranchService.createBranch(
                            name: nameController.text,
                            code: codeController.text,
                            phone: phoneController.text,
                            address: addressController.text,
                          );
                        } else {
                          await BranchService.updateBranch(
                            branch['id'] as String,
                            name: nameController.text,
                            code: codeController.text,
                            phone: phoneController.text,
                            address: addressController.text,
                            isActive: isActive,
                          );
                        }
                        if (ctx.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (error) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppErrorMessage.from(
                                  error,
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save Branch'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    codeController.dispose();
    phoneController.dispose();
    addressController.dispose();

    if (saved == true) {
      _refresh();
    }
  }

  Future<void> _switchBranch(String branchId) async {
    await BranchService.setCurrentBranch(branchId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Branch selected for new records on this device.'),
        backgroundColor: AppColors.success,
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branches'),
        leading: !Navigator.of(context).canPop() &&
                MediaQuery.of(context).size.width <= 800
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        actions: [
          FilledButton.icon(
            onPressed: () => _showBranchDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Branch'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: TrainingAnchor(
        id: 'branches.workspace',
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _branchesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final branches = snapshot.data ?? [];
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: branches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final branch = branches[index];
                final isCurrent = branch['id'] == BranchService.currentBranchId;
                final isActive = (branch['is_active'] as num? ?? 1) == 1;
                return ListTile(
                  tileColor: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                  leading: Icon(
                    isCurrent ? Icons.store_rounded : Icons.store_outlined,
                    color: isCurrent
                        ? AppColors.success
                        : AppColors.primaryLight,
                  ),
                  title: Text(branch['name'] as String? ?? 'Branch'),
                  subtitle: Text(
                    [
                      if ((branch['code'] as String?)?.trim().isNotEmpty ==
                          true)
                        'Code: ${branch['code']}',
                      if ((branch['address'] as String?)?.trim().isNotEmpty ==
                          true)
                        branch['address'] as String,
                      isActive ? 'Active' : 'Inactive',
                    ].join(' - '),
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: isCurrent
                            ? null
                            : () => _switchBranch(branch['id'] as String),
                        child: Text(isCurrent ? 'Current' : 'Use'),
                      ),
                      IconButton(
                        onPressed: () => _showBranchDialog(branch),
                        icon: const Icon(Icons.edit_outlined),
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
}
