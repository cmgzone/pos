import 'package:flutter/material.dart';

import 'package:pos_app/core/services/branch_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/core/utils/error_messages.dart';
import 'package:pos_app/features/services/data/service_repository.dart';
import 'package:pos_app/features/settings/data/custom_role_repository.dart';

class CustomRolesSection extends StatefulWidget {
  final VoidCallback? onRolesChanged;

  const CustomRolesSection({super.key, this.onRolesChanged});

  @override
  State<CustomRolesSection> createState() => _CustomRolesSectionState();
}

class _CustomRolesSectionState extends State<CustomRolesSection> {
  bool _loading = true;
  List<Map<String, dynamic>> _roles = [];

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    setState(() => _loading = true);
    final roles = await CustomRoleRepository.getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _roles = roles;
      _loading = false;
    });
  }

  Future<void> _showRoleDialog([Map<String, dynamic>? role]) async {
    final services = await ServiceRepository.getServices();
    final branches = await BranchService.getBranches(activeOnly: true);
    if (!mounted) {
      return;
    }

    final isEditing = role != null;
    final nameController = TextEditingController(
      text: role == null ? '' : CustomRoleRepository.roleName(role),
    );
    final descriptionController = TextEditingController(
      text: role?['description'] as String? ?? '',
    );
    var baseRole = RolePermissions.normalizeRole(
      role?['base_role'] as String? ?? RolePermissions.cashier,
    );
    if (baseRole == RolePermissions.admin) {
      baseRole = RolePermissions.manager;
    }
    final selectedFeatures =
        (role == null
                ? UserAccessProfile.defaultFeatureAccessForRole(baseRole)
                : CustomRoleRepository.featureAccessForRole(role))
            .where(UserAccessProfile.configurableFeatures.contains)
            .toSet();
    final initialServiceIds = role == null
        ? <String>[]
        : CustomRoleRepository.allowedServiceIdsForRole(role);
    final selectedServiceIds = initialServiceIds.toSet();
    var allowAllServices = initialServiceIds.isEmpty;
    final initialBranchIds = role == null
        ? <String>[]
        : CustomRoleRepository.allowedBranchIdsForRole(role);
    final selectedBranchIds = initialBranchIds.toSet();
    var allowAllBranches = initialBranchIds.isEmpty;
    var posMode = UserAccessProfile.resolvePosMode(
      role: baseRole,
      rawPosMode: role?['pos_mode'] as String?,
    );
    var isActive = (role?['is_active'] as num? ?? 1).toInt() != 0;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(isEditing ? 'Edit Role Template' : 'New Role Template'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: MediaQuery.sizeOf(context).height * 0.74,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Role name',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: descriptionController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: baseRole,
                          decoration: const InputDecoration(
                            labelText: 'Base role',
                            prefixIcon: Icon(Icons.verified_user_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: RolePermissions.manager,
                              child: Text('Manager'),
                            ),
                            DropdownMenuItem(
                              value: RolePermissions.cashier,
                              child: Text('Cashier'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              baseRole = value;
                              final defaults =
                                  UserAccessProfile.defaultFeatureAccessForRole(
                                    baseRole,
                                  );
                              selectedFeatures
                                ..clear()
                                ..addAll(
                                  defaults.where(
                                    UserAccessProfile
                                        .configurableFeatures
                                        .contains,
                                  ),
                                );
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: posMode,
                          decoration: const InputDecoration(
                            labelText: 'POS mode',
                            prefixIcon: Icon(Icons.point_of_sale_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: UserAccessProfile.posModeBoth,
                              child: Text('Products + Services'),
                            ),
                            DropdownMenuItem(
                              value: UserAccessProfile.posModeProducts,
                              child: Text('Products only'),
                            ),
                            DropdownMenuItem(
                              value: UserAccessProfile.posModeServices,
                              child: Text('Services only'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => posMode = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isActive,
                    title: const Text(
                      'Active template',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Inactive templates stay on existing staff but cannot be assigned to new staff.',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => isActive = value),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle(context, Icons.widgets_outlined, 'Modules'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: UserAccessProfile.configurableFeatures.map((
                      feature,
                    ) {
                      return FilterChip(
                        label: Text(UserAccessProfile.featureLabel(feature)),
                        selected: selectedFeatures.contains(feature),
                        onSelected: (selected) {
                          setDialogState(() {
                            if (selected) {
                              selectedFeatures.add(feature);
                            } else {
                              selectedFeatures.remove(feature);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle(
                    context,
                    Icons.design_services_outlined,
                    'Service Visibility',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowAllServices,
                    title: const Text('Allow all services'),
                    onChanged: (value) =>
                        setDialogState(() => allowAllServices = value),
                  ),
                  if (!allowAllServices)
                    _choiceWrap(
                      emptyLabel: 'No services created yet.',
                      rows: services,
                      selectedIds: selectedServiceIds,
                      labelKey: 'name',
                      setDialogState: setDialogState,
                    ),
                  const SizedBox(height: 18),
                  _sectionTitle(
                    context,
                    Icons.store_mall_directory_outlined,
                    'Branch Visibility',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowAllBranches,
                    title: const Text('Allow all branches'),
                    onChanged: (value) =>
                        setDialogState(() => allowAllBranches = value),
                  ),
                  if (!allowAllBranches)
                    _choiceWrap(
                      emptyLabel: 'No branches created yet.',
                      rows: branches,
                      selectedIds: selectedBranchIds,
                      labelKey: 'name',
                      setDialogState: setDialogState,
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
                      if (!allowAllServices &&
                          services.isNotEmpty &&
                          selectedServiceIds.isEmpty) {
                        _showSnack(
                          'Choose at least one service or allow all services.',
                          isError: true,
                        );
                        return;
                      }
                      if (!allowAllBranches &&
                          branches.isNotEmpty &&
                          selectedBranchIds.isEmpty) {
                        _showSnack(
                          'Choose at least one branch or allow all branches.',
                          isError: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        if (isEditing) {
                          await CustomRoleRepository.update(
                            id: role['id'] as String,
                            name: nameController.text,
                            description: descriptionController.text,
                            baseRole: baseRole,
                            featureAccess: selectedFeatures.toList(),
                            allowedServiceIds: allowAllServices
                                ? const []
                                : selectedServiceIds.toList(),
                            allowedBranchIds: allowAllBranches
                                ? const []
                                : selectedBranchIds.toList(),
                            posMode: posMode,
                            isActive: isActive,
                          );
                        } else {
                          await CustomRoleRepository.create(
                            name: nameController.text,
                            description: descriptionController.text,
                            baseRole: baseRole,
                            featureAccess: selectedFeatures.toList(),
                            allowedServiceIds: allowAllServices
                                ? const []
                                : selectedServiceIds.toList(),
                            allowedBranchIds: allowAllBranches
                                ? const []
                                : selectedBranchIds.toList(),
                            posMode: posMode,
                            isActive: isActive,
                          );
                        }
                        if (context.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (error) {
                        if (context.mounted) {
                          _showSnack(
                            AppErrorMessage.from(
                              error,
                              fallback: 'Role template could not be saved.',
                            ),
                            isError: true,
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save Role'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    descriptionController.dispose();

    if (saved == true) {
      await _loadRoles();
      widget.onRolesChanged?.call();
      _showSnack('Role template saved');
    }
  }

  Future<void> _deleteRole(Map<String, dynamic> role) async {
    final roleName = CustomRoleRepository.roleName(role);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Role Template'),
        content: Text(
          'Delete "$roleName"? Staff using it will keep their current access, but the template will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await CustomRoleRepository.delete(role['id'] as String);
      await _loadRoles();
      widget.onRolesChanged?.call();
      _showSnack('Role template deleted');
    } catch (error) {
      _showSnack(
        AppErrorMessage.from(
          error,
          fallback: 'Role template could not be deleted.',
        ),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 560;
            final addButton = FilledButton.icon(
              onPressed: () => _showRoleDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Role'),
            );
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reusable Permission Templates',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create roles once, then assign them to staff from Team Access.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            );
            if (isWide) {
              return Row(
                children: [
                  Expanded(child: title),
                  addButton,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 12), addButton],
            );
          },
        ),
        const SizedBox(height: 18),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_roles.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 38,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 10),
                Text(
                  'No custom roles yet.',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
        else
          ..._roles.map(_roleCard),
      ],
    );
  }

  Widget _roleCard(Map<String, dynamic> role) {
    final colors = Theme.of(context).colorScheme;
    final features = CustomRoleRepository.featureAccessForRole(
      role,
    ).where((feature) => feature != UserAccessProfile.featureSettings).length;
    final services = CustomRoleRepository.allowedServiceIdsForRole(role);
    final branches = CustomRoleRepository.allowedBranchIdsForRole(role);
    final isActive = (role['is_active'] as num? ?? 1).toInt() != 0;
    final assignedCount = (role['assigned_count'] as num? ?? 0).toInt();
    final baseRole = RolePermissions.label(role['base_role'] as String?);
    final posMode = UserAccessProfile.resolvePosMode(
      role: role['base_role'] as String? ?? RolePermissions.cashier,
      rawPosMode: role['pos_mode'] as String?,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 560;
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showRoleDialog(role),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => _deleteRole(role),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
              ),
            ],
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    CustomRoleRepository.roleName(role),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  _statusChip(isActive ? 'Active' : 'Inactive', isActive),
                  _infoChip('$assignedCount staff'),
                ],
              ),
              if ((role['description'] as String? ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  role['description'] as String,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoChip(baseRole),
                  _infoChip('$features modules'),
                  _infoChip(_posModeLabel(posMode)),
                  _infoChip(
                    services.isEmpty
                        ? 'All services'
                        : '${services.length} services',
                  ),
                  _infoChip(
                    branches.isEmpty
                        ? 'All branches'
                        : '${branches.length} branches',
                  ),
                ],
              ),
            ],
          );
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: content),
                const SizedBox(width: 12),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [content, const SizedBox(height: 12), actions],
          );
        },
      ),
    );
  }

  Widget _choiceWrap({
    required String emptyLabel,
    required List<Map<String, dynamic>> rows,
    required Set<String> selectedIds,
    required String labelKey,
    required StateSetter setDialogState,
  }) {
    if (rows.isEmpty) {
      return Text(
        emptyLabel,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rows.map((row) {
        final id = row['id'] as String? ?? '';
        return FilterChip(
          label: Text(row[labelKey] as String? ?? 'Item'),
          selected: selectedIds.contains(id),
          onSelected: (selected) {
            setDialogState(() {
              if (selected) {
                selectedIds.add(id);
              } else {
                selectedIds.remove(id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _statusChip(String label, bool active) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? AppColors.success.withValues(alpha: 0.12)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? AppColors.success : colors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoChip(String label) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _posModeLabel(String posMode) {
    switch (posMode) {
      case UserAccessProfile.posModeProducts:
        return 'Products only';
      case UserAccessProfile.posModeServices:
        return 'Services only';
      default:
        return 'Products + services';
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }
}
