import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:pos_app/core/services/backup_service.dart';
import 'package:pos_app/core/services/branch_service.dart';
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/cash_drawer_service.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/services/sync_controller.dart';
import 'package:pos_app/core/services/sync_settings_service.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/features/auth/data/user_repository.dart';
import 'package:pos_app/features/auth/presentation/login_screen.dart';
import 'package:pos_app/features/services/data/service_repository.dart';
import 'package:pos_app/features/training/application/training_controller.dart';
import 'package:pos_app/features/training/presentation/training_hub_screen.dart';
import 'package:pos_app/features/training/widgets/training_anchor.dart';
import 'package:pos_app/features/settings/presentation/payment_methods_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _backupExportCancelled = 'Backup export cancelled';
  static const _backupImportCancelled = 'Backup import cancelled';

  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _taxController;
  late TextEditingController _currencyController;
  late TextEditingController _footerController;
  late TextEditingController _baysController;
  late TextEditingController _cashDrawerPrinterPathController;
  bool _autoSyncEnabled = true;
  bool _cashDrawerEnabled = false;

  bool _saving = false;
  bool _hasChanges = false;
  bool _backupBusy = false;
  bool _teamLoading = false;
  List<Map<String, dynamic>> _backups = [];
  List<Map<String, dynamic>> _teamMembers = [];

  bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;
  bool get _canManageOperationalSettings =>
      RolePermissions.canManageOperationalSettings(
        SessionService.currentUserRole,
      );
  bool get _canManageUsers =>
      RolePermissions.canManageUsers(SessionService.currentUserRole);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: ShopSettings.shopName)
      ..addListener(_markChanged);
    _addressController = TextEditingController(text: ShopSettings.shopAddress)
      ..addListener(_markChanged);
    _phoneController = TextEditingController(text: ShopSettings.shopPhone)
      ..addListener(_markChanged);
    _emailController = TextEditingController(text: ShopSettings.shopEmail)
      ..addListener(_markChanged);
    _taxController = TextEditingController(
      text: ShopSettings.taxRate.toString(),
    )..addListener(_markChanged);
    _currencyController = TextEditingController(text: ShopSettings.currency)
      ..addListener(_markChanged);
    _footerController = TextEditingController(text: ShopSettings.receiptFooter)
      ..addListener(_markChanged);
    _baysController = TextEditingController(
      text: ShopSettings.carwashBaysCount.toString(),
    )..addListener(_markChanged);
    _cashDrawerPrinterPathController = TextEditingController(
      text: ShopSettings.cashDrawerPrinterPath,
    )..addListener(_markChanged);
    _autoSyncEnabled = SyncSettingsService.autoSyncEnabled;
    _cashDrawerEnabled = ShopSettings.cashDrawerEnabled;

    _loadBackups();
    if (_canManageUsers) {
      _loadTeamMembers();
    }
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxController.dispose();
    _currencyController.dispose();
    _footerController.dispose();
    _baysController.dispose();
    _cashDrawerPrinterPathController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ShopSettings.setShopName(_nameController.text.trim());
      await ShopSettings.setShopAddress(_addressController.text.trim());
      await ShopSettings.setShopPhone(_phoneController.text.trim());
      await ShopSettings.setShopEmail(_emailController.text.trim());
      await ShopSettings.setTaxRate(
        double.tryParse(_taxController.text) ?? 8.0,
      );
      await ShopSettings.setCurrency(_currencyController.text.trim());
      await ShopSettings.setReceiptFooter(_footerController.text.trim());
      await ShopSettings.setCarwashBaysCount(
        int.tryParse(_baysController.text) ?? 4,
      );
      await ShopSettings.setCashDrawerEnabled(_cashDrawerEnabled);
      await ShopSettings.setCashDrawerPrinterPath(
        _cashDrawerPrinterPathController.text,
      );
      await SyncSettingsService.setAutoSyncEnabled(_autoSyncEnabled);
      await ref
          .read(syncControllerProvider.notifier)
          .reloadConfiguration(triggerSync: _autoSyncEnabled);

      setState(() => _hasChanges = false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Settings saved successfully'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _loadBackups() async {
    final backups = await BackupService.listBackups();
    if (!mounted) {
      return;
    }
    setState(() => _backups = backups);
  }

  Future<void> _loadTeamMembers() async {
    if (!_canManageUsers) {
      return;
    }
    setState(() => _teamLoading = true);
    final users = await UserRepository.getAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _teamMembers = users;
      _teamLoading = false;
    });
  }

  Future<void> _showAddStaffDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String role = RolePermissions.cashier;
    bool saving = false;
    bool showPassword = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Add Staff Account'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: !showPassword,
                  decoration: InputDecoration(
                    labelText: 'Temporary password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: showPassword ? 'Hide password' : 'Show password',
                      icon: Icon(
                        showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setDialogState(() => showPassword = !showPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                  items: RolePermissions.allRoles
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(RolePermissions.label(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => role = value);
                    }
                  },
                ),
              ],
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
                        await UserRepository.createUser(
                          name: nameController.text,
                          email: emailController.text,
                          password: passwordController.text,
                          role: role,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                              backgroundColor: AppColors.error,
                            ),
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
                  : const Text('Create Staff Account'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();

    if (created == true) {
      await _loadTeamMembers();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staff account created'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _updateTeamRole(String userId, String role) async {
    try {
      await UserRepository.updateRole(userId: userId, role: role);
      await _loadTeamMembers();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User role updated'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _showTeamAccessDialog(Map<String, dynamic> user) async {
    final userId = user['id'] as String? ?? '';
    final role = RolePermissions.normalizeRole(user['role'] as String?);
    if (userId.isEmpty) {
      return;
    }

    if (role == RolePermissions.admin) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Admin Access'),
          content: const Text(
            'Admin accounts always keep full feature access, full service visibility, and both POS modes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    final services = await ServiceRepository.getServices();
    final branches = await BranchService.getBranches(activeOnly: true);
    if (!mounted) {
      return;
    }

    final initialFeatures = UserAccessProfile.resolveFeatureAccess(
      role: role,
      rawFeatureAccessJson: user['feature_access_json'] as String?,
    );
    final selectedFeatures = initialFeatures
        .where(UserAccessProfile.configurableFeatures.contains)
        .toSet();
    final initialAllowedServiceIds = UserAccessProfile.resolveAllowedServiceIds(
      role: role,
      rawAllowedServiceIdsJson: user['allowed_service_ids_json'] as String?,
    );
    final selectedServiceIds = initialAllowedServiceIds.toSet();
    var allowAllServices = initialAllowedServiceIds.isEmpty;
    final initialAllowedBranchIds = UserAccessProfile.resolveAllowedBranchIds(
      role: role,
      rawAllowedBranchIdsJson: user['allowed_branch_ids_json'] as String?,
    );
    final selectedBranchIds = initialAllowedBranchIds.toSet();
    var allowAllBranches = initialAllowedBranchIds.isEmpty;
    var posMode = UserAccessProfile.resolvePosMode(
      role: role,
      rawPosMode: user['pos_mode'] as String?,
    );
    var serviceOrderScope = UserAccessProfile.resolveServiceOrderScope(
      role: role,
      rawScope: user['service_order_scope'] as String?,
    );
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Access for ${user['name'] as String? ?? 'Staff'}'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          RolePermissions.label(role),
                          style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighlight,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'Settings stays available for password and sign out',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Feature Access',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: UserAccessProfile.configurableFeatures
                        .map(
                          (featureKey) => FilterChip(
                            label: Text(
                              UserAccessProfile.featureLabel(featureKey),
                            ),
                            selected: selectedFeatures.contains(featureKey),
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedFeatures.add(featureKey);
                                } else {
                                  selectedFeatures.remove(featureKey);
                                }
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'POS Mode',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: UserAccessProfile.posModeProducts,
                        icon: Icon(Icons.inventory_2_outlined),
                        label: Text('Products Only'),
                      ),
                      ButtonSegment(
                        value: UserAccessProfile.posModeBoth,
                        icon: Icon(Icons.view_week_outlined),
                        label: Text('Both'),
                      ),
                      ButtonSegment(
                        value: UserAccessProfile.posModeServices,
                        icon: Icon(Icons.design_services_outlined),
                        label: Text('Services Only'),
                      ),
                    ],
                    selected: {posMode},
                    onSelectionChanged: (selection) {
                      setDialogState(() => posMode = selection.first);
                    },
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This controls what appears inside the POS screen for this account.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Service Order Visibility',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: UserAccessProfile
                            .serviceOrderScopeAllVisibleServices,
                        icon: Icon(Icons.visibility_outlined),
                        label: Text('All Allowed'),
                      ),
                      ButtonSegment(
                        value: UserAccessProfile.serviceOrderScopeAssignedOnly,
                        icon: Icon(Icons.person_pin_outlined),
                        label: Text('Assigned Only'),
                      ),
                    ],
                    selected: {serviceOrderScope},
                    onSelectionChanged: (selection) {
                      setDialogState(() => serviceOrderScope = selection.first);
                    },
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Controls which service orders this staff member can see in the Services tab.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowAllServices,
                    title: const Text(
                      'Allow all services',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Turn this off to choose specific services this staff member can see.',
                    ),
                    onChanged: (value) {
                      setDialogState(() => allowAllServices = value);
                    },
                  ),
                  if (!allowAllServices) ...[
                    const SizedBox(height: 8),
                    if (services.isEmpty)
                      const Text(
                        'No services created yet.',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: services.map((service) {
                          final serviceId = service['id'] as String? ?? '';
                          final serviceName =
                              service['name'] as String? ?? 'Service';
                          return FilterChip(
                            label: Text(serviceName),
                            selected: selectedServiceIds.contains(serviceId),
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedServiceIds.add(serviceId);
                                } else {
                                  selectedServiceIds.remove(serviceId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                  ],
                  const SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowAllBranches,
                    title: const Text(
                      'Allow all branches',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Turn this off to choose which branches this staff member can use.',
                    ),
                    onChanged: (value) {
                      setDialogState(() => allowAllBranches = value);
                    },
                  ),
                  if (!allowAllBranches) ...[
                    const SizedBox(height: 8),
                    if (branches.isEmpty)
                      const Text(
                        'No branches created yet.',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: branches.map((branch) {
                          final branchId = branch['id'] as String? ?? '';
                          final branchName =
                              branch['name'] as String? ?? 'Branch';
                          return FilterChip(
                            label: Text(branchName),
                            selected: selectedBranchIds.contains(branchId),
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedBranchIds.add(branchId);
                                } else {
                                  selectedBranchIds.remove(branchId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                  ],
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Choose at least one service or enable all services.',
                            ),
                            backgroundColor: AppColors.warning,
                          ),
                        );
                        return;
                      }
                      if (!allowAllBranches &&
                          branches.isNotEmpty &&
                          selectedBranchIds.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Choose at least one branch or enable all branches.',
                            ),
                            backgroundColor: AppColors.warning,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => saving = true);
                      try {
                        await UserRepository.updateAccess(
                          userId: userId,
                          featureAccess: selectedFeatures.toList(),
                          allowedServiceIds: allowAllServices
                              ? const []
                              : selectedServiceIds.toList(),
                          allowedBranchIds: allowAllBranches
                              ? const []
                              : selectedBranchIds.toList(),
                          posMode: posMode,
                          serviceOrderScope: serviceOrderScope,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                              backgroundColor: AppColors.error,
                            ),
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
                  : const Text('Save Access'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _loadTeamMembers();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staff access updated'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  String _buildStaffAccessSummary(Map<String, dynamic> user) {
    final role = RolePermissions.normalizeRole(user['role'] as String?);
    if (role == RolePermissions.admin) {
      return 'Full access • POS: Both • Services: All';
    }
    final features = UserAccessProfile.resolveFeatureAccess(
      role: role,
      rawFeatureAccessJson: user['feature_access_json'] as String?,
    );
    final services = UserAccessProfile.resolveAllowedServiceIds(
      role: role,
      rawAllowedServiceIdsJson: user['allowed_service_ids_json'] as String?,
    );
    final branches = UserAccessProfile.resolveAllowedBranchIds(
      role: role,
      rawAllowedBranchIdsJson: user['allowed_branch_ids_json'] as String?,
    );
    final posMode = UserAccessProfile.resolvePosMode(
      role: role,
      rawPosMode: user['pos_mode'] as String?,
    );
    final featureCount = features
        .where((feature) => feature != UserAccessProfile.featureSettings)
        .length;
    final serviceSummary = services.isEmpty
        ? 'All services'
        : '${services.length} services';
    final branchSummary = branches.isEmpty
        ? 'All branches'
        : '${branches.length} branches';
    return '$featureCount features • POS: ${_labelForPosMode(posMode)} • $serviceSummary • $branchSummary';
  }

  String _labelForPosMode(String posMode) {
    switch (posMode) {
      case UserAccessProfile.posModeProducts:
        return 'Products only';
      case UserAccessProfile.posModeServices:
        return 'Services only';
      default:
        return 'Both';
    }
  }

  Widget _buildStaffBranchChips(Map<String, dynamic> user, String role) {
    final normalizedRole = RolePermissions.normalizeRole(role);

    // Admins always have full access
    if (normalizedRole == RolePermissions.admin) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined,
                    size: 12, color: AppColors.success),
                const SizedBox(width: 4),
                Text(
                  'All branches',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final branchIds = UserAccessProfile.resolveAllowedBranchIds(
      role: normalizedRole,
      rawAllowedBranchIdsJson: user['allowed_branch_ids_json'] as String?,
    );

    // Empty list means unrestricted (all branches)
    if (branchIds.isEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.business_outlined,
                    size: 12, color: AppColors.primaryLight),
                const SizedBox(width: 4),
                Text(
                  'All branches',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Show individual branch chips
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _resolveBranchNames(branchIds),
      builder: (context, snapshot) {
        final branches = snapshot.data ?? [];
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final branch in branches)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_outlined,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      branch['name'] as String? ?? branch['id'] as String,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (branches.isEmpty)
              for (final id in branchIds)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    id,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _resolveBranchNames(
    List<String> branchIds,
  ) async {
    if (branchIds.isEmpty) {
      return const [];
    }
    final placeholders = List.filled(branchIds.length, '?').join(', ');
    return DatabaseService.rawQuery(
      'SELECT id, name FROM branches WHERE id IN ($placeholders) AND deleted_at IS NULL ORDER BY name COLLATE NOCASE ASC',
      branchIds,
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool saving = false;
    bool showCurrentPassword = false;
    bool showNewPassword = false;
    bool showConfirmPassword = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Change Password'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentController,
                  obscureText: !showCurrentPassword,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    prefixIcon: const Icon(Icons.lock_clock_outlined),
                    suffixIcon: IconButton(
                      tooltip: showCurrentPassword
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        showCurrentPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setDialogState(
                        () => showCurrentPassword = !showCurrentPassword,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: !showNewPassword,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: showNewPassword
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        showNewPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setDialogState(
                        () => showNewPassword = !showNewPassword,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: !showConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    prefixIcon: const Icon(Icons.verified_user_outlined),
                    suffixIcon: IconButton(
                      tooltip: showConfirmPassword
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        showConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setDialogState(
                        () => showConfirmPassword = !showConfirmPassword,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (newController.text != confirmController.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('New passwords do not match'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await UserRepository.changePassword(
                          userId: SessionService.currentUserId,
                          currentPassword: currentController.text,
                          newPassword: newController.text,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(
                            content: Text('Password updated'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                              backgroundColor: AppColors.error,
                            ),
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
                  : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );

    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
  }

  Future<void> _signOut() async {
    await SessionService.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _createBackup() async {
    setState(() => _backupBusy = true);
    try {
      final backupPath = _isMobilePlatform
          ? await _exportBackupForMobile()
          : await BackupService.createBackup();
      await _loadBackups();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isMobilePlatform
                ? 'Backup exported: ${_fileNameFromPath(backupPath)}'
                : 'Backup created: ${_fileNameFromPath(backupPath)}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (e.toString().contains(_backupExportCancelled)) {
        return;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  Future<String> _exportBackupForMobile() async {
    final suggestedName = BackupService.buildBackupFileName();
    final targetPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Backup',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const ['db'],
      bytes: null,
    );

    if (targetPath == null || targetPath.trim().isEmpty) {
      throw Exception(_backupExportCancelled);
    }

    return BackupService.exportBackup(targetPath);
  }

  Future<void> _importBackupFromFile() async {
    setState(() => _backupBusy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose Backup File',
        type: FileType.custom,
        allowedExtensions: const ['db'],
        allowMultiple: false,
      );

      final backupPath = result?.files.single.path;
      if (backupPath == null || backupPath.trim().isEmpty) {
        throw Exception(_backupImportCancelled);
      }
      if (!mounted) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore Backup'),
          content: Text(
            'Restore ${_fileNameFromPath(backupPath)}?\n\nYour current shop data will be replaced. A safety backup of the current database will be created automatically before restore.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child: const Text('Restore'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      final safetyBackupPath = await BackupService.restoreBackup(backupPath);
      await _loadBackups();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup restored. Safety snapshot: ${_fileNameFromPath(safetyBackupPath)}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (e.toString().contains(_backupImportCancelled)) {
        return;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  String _fileNameFromPath(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }

  Future<void> _copyBackupPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Backup path copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _restoreBackup(Map<String, dynamic> backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Backup'),
        content: Text(
          'Restore ${backup['name']}?\n\nYour current shop data will be replaced. A safety backup of the current database will be created automatically before restore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _backupBusy = true);
    try {
      final safetyBackupPath = await BackupService.restoreBackup(
        backup['path'] as String,
      );
      await _loadBackups();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup restored. Safety snapshot: ${_fileNameFromPath(safetyBackupPath)}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  String _formatBackupDate(String? iso) {
    final date = DateTime.tryParse(iso ?? '');
    if (date == null) {
      return 'Unknown date';
    }
    return DateFormat('MMM d, yyyy  HH:mm').format(date);
  }

  String _formatBackupSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _runManualSync() async {
    final success = await ref.read(syncControllerProvider.notifier).syncNow();
    final syncState = ref.read(syncControllerProvider);

    if (!mounted) {
      return;
    }

    final message = syncState.lastError ?? syncState.lastMessage;
    if (message == null || message.trim().isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  String _formatLastSync(DateTime? value) {
    if (value == null) {
      return 'Not synced yet';
    }
    return DateFormat('MMM d, yyyy  HH:mm').format(value);
  }

  Widget _buildSyncCard(SyncState syncState) {
    final license = syncState.licenseSnapshot;
    final summaryColor = switch (syncState.indicator) {
      SyncIndicatorState.synced => AppColors.success,
      SyncIndicatorState.syncing => AppColors.primaryLight,
      SyncIndicatorState.localOnly => AppColors.textSecondary,
      SyncIndicatorState.updatesAvailable => AppColors.primaryLight,
      SyncIndicatorState.pending ||
      SyncIndicatorState.offline ||
      SyncIndicatorState.issues => AppColors.warning,
      SyncIndicatorState.error => AppColors.error,
    };
    final licenseColor = switch (license.accessStatus) {
      LicenseAccessStatus.active => AppColors.success,
      LicenseAccessStatus.grace => AppColors.warning,
      LicenseAccessStatus.expired ||
      LicenseAccessStatus.invalid => AppColors.error,
      LicenseAccessStatus.localOnly => AppColors.textSecondary,
    };

    return _buildCard([
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_done_outlined,
              color: AppColors.primaryLight,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cloud sync uses the app\'s built-in server configuration. End users do not need to enter a backend URL.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: SwitchListTile.adaptive(
          value: _autoSyncEnabled,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          activeThumbColor: AppColors.primaryLight,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
          title: const Text('Auto Sync'),
          subtitle: const Text(
            'Check for cloud updates and upload local changes automatically.',
            style: TextStyle(fontSize: 12),
          ),
          onChanged: (value) {
            setState(() {
              _autoSyncEnabled = value;
              _hasChanges = true;
            });
          },
        ),
      ),
      const SizedBox(height: 18),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: summaryColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: summaryColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (syncState.indicator) {
                    SyncIndicatorState.localOnly => Icons.cloud_off,
                    SyncIndicatorState.offline => Icons.cloud_off_outlined,
                    SyncIndicatorState.syncing => Icons.sync,
                    SyncIndicatorState.error => Icons.sync_problem,
                    SyncIndicatorState.issues => Icons.warning_amber_rounded,
                    SyncIndicatorState.pending => Icons.cloud_upload_outlined,
                    SyncIndicatorState.updatesAvailable =>
                      Icons.cloud_download_outlined,
                    SyncIndicatorState.synced => Icons.cloud_done,
                  },
                  color: summaryColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    syncState.shortLabel,
                    style: TextStyle(
                      color: summaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (syncState.lastError != null &&
                syncState.lastError!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(syncState.lastError!, style: const TextStyle(fontSize: 12)),
            ] else if (syncState.lastMessage != null &&
                syncState.lastMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                syncState.lastMessage!,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: licenseColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: licenseColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: licenseColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    license.shortLabel,
                    style: TextStyle(
                      color: licenseColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              license.detail ?? 'No cloud subscription details yet.',
              style: const TextStyle(fontSize: 12),
            ),
            if (license.businessId != null) ...[
              const SizedBox(height: 8),
              Text(
                'Business ID: ${license.businessId}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: syncState.isSyncing ? null : _runManualSync,
            icon: syncState.isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(syncState.isSyncing ? 'Syncing...' : 'Sync Now'),
          ),
          OutlinedButton.icon(
            onPressed: syncState.isSyncing
                ? null
                : () =>
                      ref.read(syncControllerProvider.notifier).refreshStatus(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh Status'),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _buildSyncStat('Pending', '${syncState.pendingChanges}'),
          _buildSyncStat('Remote', '${syncState.remoteChanges}'),
          _buildSyncStat(
            'Issues',
            '${syncState.conflictCount + syncState.errorCount}',
          ),
          _buildSyncStat('Cursor', syncState.cursor),
        ],
      ),
      const SizedBox(height: 18),
      Text(
        'Last synced: ${_formatLastSync(syncState.lastSyncAt)}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      const SizedBox(height: 6),
      Text(
        'Device ID: ${syncState.deviceId ?? 'Not created yet'}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      if (license.lastVerifiedAt != null) ...[
        const SizedBox(height: 6),
        Text(
          'Subscription checked: ${_formatLastSync(license.lastVerifiedAt)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    ]);
  }

  Widget _buildSyncStat(String label, String value) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildCashDrawerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Device-local label ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.computer_outlined,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  'Device-local setting — not shared across branches or devices',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Open physical cash drawer after cash sales',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Disabled until a manager or admin sets the Windows printer share or port.',
            ),
            value: _cashDrawerEnabled,
            onChanged: (value) {
              setState(() => _cashDrawerEnabled = value);
              _markChanged();
            },
          ),
          const SizedBox(height: 12),
          _buildField(
            'Drawer Printer Share / Port',
            r'e.g. \\localhost\ReceiptPrinter or LPT1:',
            _cashDrawerPrinterPathController,
            Icons.print_outlined,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _cashDrawerEnabled ? _testCashDrawer : null,
                icon: const Icon(Icons.lock_open_outlined, size: 18),
                label: const Text('Test Open'),
              ),
              const Text(
                'Test open is limited to managers and admins.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _testCashDrawer() async {
    if (_hasChanges) {
      await _save();
      if (!mounted) {
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Open Cash Drawer?'),
        content: const Text(
          'This will send an open command to the configured drawer printer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: const Text('Open Drawer'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    final result = await CashDrawerService.testOpen();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: result.success ? AppColors.success : AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncControllerProvider);
    final training = ref.watch(trainingControllerProvider);
    final progressPercent = (training.completionRatio * 100).round();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Settings'),
        actions: [
          if (_canManageOperationalSettings && _hasChanges)
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(Icons.school_outlined, 'Training & Help'),
                const SizedBox(height: 4),
                const Text(
                  'Replay guided tours for the live POS, inventory, customers, reports, and settings experience.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TrainingAnchor(
                  id: 'settings.training',
                  child: _buildCard([
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildTrainingMetric(
                          'Modules',
                          '${training.completedModuleCount}/${training.availableModuleCount}',
                          AppColors.success,
                        ),
                        _buildTrainingMetric(
                          'Progress',
                          '$progressPercent%',
                          AppColors.primary,
                        ),
                        _buildTrainingMetric(
                          'User',
                          SessionService.currentUserName,
                          AppColors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Training progress is saved separately for each signed-in staff member.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const TrainingHubScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_circle_outline, size: 18),
                          label: const Text('Open Training Hub'),
                        ),
                        OutlinedButton.icon(
                          onPressed: training.availableModuleCount == 0
                              ? null
                              : () => ref
                                    .read(trainingControllerProvider)
                                    .startFullTour(),
                          icon: const Icon(Icons.route_outlined, size: 18),
                          label: const Text('Start Full Tour'),
                        ),
                      ],
                    ),
                  ]),
                ),
                const SizedBox(height: 32),
                _buildSectionHeader(
                  Icons.admin_panel_settings_outlined,
                  'My Account',
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your current login, password, and staff access.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TrainingAnchor(
                  id: 'settings.account',
                  child: _buildAccountCard(),
                ),
                if (_canManageUsers) ...[
                  const SizedBox(height: 32),
                  _buildSectionHeader(Icons.groups_outlined, 'Team Access'),
                  const SizedBox(height: 4),
                  Text(
                    'Create staff accounts and adjust role permissions.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TrainingAnchor(id: 'settings.team', child: _buildTeamCard()),
                ],
                if (!_canManageOperationalSettings) ...[
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'Shop settings, backup controls, and receipt configuration are limited to managers and admins.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 32),
                ] else ...[
                  _buildSectionHeader(Icons.store, 'Shop Information'),
                  const SizedBox(height: 4),
                  const Text(
                    'This info appears on receipts and the app header.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCard([
                    _buildField(
                      'Shop Name',
                      'e.g. Downtown Electronics',
                      _nameController,
                      Icons.storefront,
                    ),
                    const SizedBox(height: 20),
                    _buildField(
                      'Address',
                      'e.g. 123 Main Street, City',
                      _addressController,
                      Icons.location_on_outlined,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            'Phone Number',
                            'e.g. (555) 123-4567',
                            _phoneController,
                            Icons.phone_outlined,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _buildField(
                            'Email',
                            'e.g. shop@example.com',
                            _emailController,
                            Icons.email_outlined,
                          ),
                        ),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader(
                    Icons.calculate_outlined,
                    'Tax & Currency',
                  ),
                  const SizedBox(height: 16),
                  _buildCard([
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            'Tax Rate (%)',
                            '8.0',
                            _taxController,
                            Icons.percent,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+\.?\d{0,2}'),
                              ),
                            ],
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _buildField(
                            'Currency Symbol',
                            '\$',
                            _currencyController,
                            Icons.attach_money,
                          ),
                        ),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader(
                    Icons.receipt_long_outlined,
                    'Receipt Settings',
                  ),
                  const SizedBox(height: 16),
                  _buildCard([
                    _buildField(
                      'Receipt Footer Message',
                      'Thank you for your purchase!',
                      _footerController,
                      Icons.message_outlined,
                      maxLines: 2,
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader(
                    Icons.garage_outlined,
                    'Operational Settings',
                  ),
                  const SizedBox(height: 16),
                  _buildCard([
                    _buildField(
                      'Number of Car Wash Bays',
                      'e.g. 4',
                      _baysController,
                      Icons.local_car_wash_outlined,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      keyboardType: TextInputType.number,
                    ),
                    if (Platform.isWindows) ...[
                      const SizedBox(height: 20),
                      _buildCashDrawerCard(),
                    ],
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader(
                    Icons.payment_outlined,
                    'Payment Methods',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Define custom payment options available during checkout.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const PaymentMethodsSection(),
                  const SizedBox(height: 32),
                  _buildSectionHeader(Icons.cloud_sync_outlined, 'Cloud Sync'),
                  const SizedBox(height: 4),
                  const Text(
                    'Connect this device to the sync backend, review cloud status, and trigger manual sync when needed.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TrainingAnchor(
                    id: 'settings.sync',
                    child: _buildSyncCard(syncState),
                  ),
                  const SizedBox(height: 32),
                  _buildSectionHeader(
                    Icons.backup_outlined,
                    'Backup & Restore',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Create database snapshots and restore the shop from any saved backup. Restoring automatically creates a safety backup first.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TrainingAnchor(
                    id: 'settings.backup',
                    child: _buildBackupCard(),
                  ),
                  const SizedBox(height: 32),
                  _buildSectionHeader(
                    Icons.preview_outlined,
                    'Receipt Preview',
                  ),
                  const SizedBox(height: 16),
                  _buildReceiptPreview(),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    return _buildCard([
      Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              SessionService.currentUserName.isEmpty
                  ? '?'
                  : SessionService.currentUserName
                        .substring(0, 1)
                        .toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SessionService.currentUserName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  SessionService.currentUserEmail,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              RolePermissions.label(SessionService.currentUserRole),
              style: const TextStyle(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: _showChangePasswordDialog,
            icon: const Icon(Icons.lock_reset_outlined, size: 18),
            label: const Text('Change Password'),
          ),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign Out'),
          ),
        ],
      ),
    ]);
  }

  Widget _buildTeamCard() {
    return _buildCard([
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: _showAddStaffDialog,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('Add Staff'),
          ),
          OutlinedButton.icon(
            onPressed: _teamLoading ? null : _loadTeamMembers,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (_teamLoading)
        const Center(child: CircularProgressIndicator())
      else if (_teamMembers.isEmpty)
        const Text(
          'No staff accounts yet.',
          style: TextStyle(color: AppColors.textSecondary),
        )
      else
        Column(
          children: _teamMembers.map((user) {
            final userId = user['id'] as String? ?? '';
            final selectedRole =
                (user['role'] as String? ?? RolePermissions.cashier)
                    .toUpperCase();
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name'] as String? ?? 'User',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user['email'] as String? ?? '',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _buildStaffAccessSummary(user),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStaffBranchChips(user, selectedRole),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedRole,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: RolePermissions.allRoles
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role,
                                  child: Text(RolePermissions.label(role)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null && value != selectedRole) {
                              _updateTeamRole(userId, value);
                            }
                          },
                        ),
                      ),
                      Tooltip(
                        message: selectedRole == RolePermissions.admin
                            ? 'Admins always keep full access'
                            : 'Edit feature, service, and POS access',
                        child: OutlinedButton.icon(
                          onPressed: () => _showTeamAccessDialog(user),
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('Access'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
    ]);
  }

  Widget _buildBackupCard() {
    return _buildCard([
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: _backupBusy ? null : _createBackup,
            icon: _backupBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_alt, size: 18),
            label: Text(_backupBusy ? 'Working...' : 'Create Backup'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
          OutlinedButton.icon(
            onPressed: _backupBusy ? null : _loadBackups,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh List'),
          ),
          if (_isMobilePlatform)
            OutlinedButton.icon(
              onPressed: _backupBusy ? null : _importBackupFromFile,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Import Backup'),
            ),
        ],
      ),
      const SizedBox(height: 20),
      if (_backups.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighlight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'No backups yet. Create your first snapshot before major changes.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        )
      else
        Column(
          children: _backups.map((backup) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    backup['name'] as String? ?? 'Backup',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatBackupDate(backup['modified_at'] as String?)} - ${_formatBackupSize(backup['size_bytes'] as int? ?? 0)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _backupBusy
                            ? null
                            : () => _copyBackupPath(backup['path'] as String),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: Text(
                          _isMobilePlatform ? 'Copy Location' : 'Copy Path',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _backupBusy
                            ? null
                            : () => _restoreBackup(backup),
                        icon: const Icon(Icons.restore_outlined, size: 18),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                        ),
                        label: const Text('Restore Backup'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
    ]);
  }

  Widget _buildReceiptPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            _nameController.text.isEmpty ? 'My Shop' : _nameController.text,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          if (_addressController.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _addressController.text,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          if (_phoneController.text.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Phone: ${_phoneController.text}',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sample Item x2',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              Text(
                '\$19.98',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${_currencyController.text}19.98',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _footerController.text.isEmpty
                ? 'Thank you for your purchase!'
                : _footerController.text,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black45,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingMetric(String label, String value, Color color) {
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
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primaryLight),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildField(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
          ),
        ),
      ],
    );
  }
}
