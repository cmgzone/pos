import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:pos_app/core/constants/app_constants.dart';
import 'package:pos_app/core/services/backup_service.dart';
import 'package:pos_app/core/services/branch_service.dart';
import 'package:pos_app/core/services/cash_drawer_service.dart';
import 'package:pos_app/core/services/etims_service.dart';
import 'package:pos_app/core/services/external_app_launcher.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/services/support_diagnostics_service.dart';
import 'package:pos_app/core/services/sync_controller.dart';
import 'package:pos_app/core/services/sync_settings_service.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/core/providers/theme_provider.dart';
import 'package:pos_app/core/utils/error_messages.dart';
import 'package:pos_app/features/auth/data/user_repository.dart';
import 'package:pos_app/features/auth/presentation/login_screen.dart';
import 'package:pos_app/features/settings/data/custom_role_repository.dart';
import 'package:pos_app/features/settings/data/payment_method_provider.dart';
import 'package:pos_app/features/services/data/service_repository.dart';
import 'package:pos_app/features/training/application/training_controller.dart';
import 'package:pos_app/features/training/presentation/training_hub_screen.dart';
import 'package:pos_app/features/training/widgets/training_anchor.dart';
import 'package:pos_app/features/settings/presentation/audit_log_screen.dart';
import 'package:pos_app/features/settings/presentation/branch_management_screen.dart';
import 'package:pos_app/features/settings/presentation/payment_methods_section.dart';
import 'package:pos_app/features/settings/presentation/communication_settings_section.dart';
import 'package:pos_app/features/settings/presentation/custom_roles_section.dart';
import 'package:pos_app/features/settings/presentation/multi_currency_section.dart';
import 'package:pos_app/features/settings/presentation/storefront_brand_settings_section.dart';
import 'package:pos_app/features/settings/presentation/subscription_plans_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _backupExportCancelled = 'Backup export cancelled';
  static const _backupImportCancelled = 'Backup import cancelled';
  static const double _settingsTileMinWidth = 314;
  static const double _fieldPairGap = 20;
  static const double _fieldPairMinColumnWidth = 280;

  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _taxController;
  late TextEditingController _currencyController;
  late TextEditingController _footerController;
  late TextEditingController _baysController;
  late TextEditingController _cashDrawerPrinterPathController;
  late TextEditingController _kraPinController;
  late TextEditingController _etimsVatNumberController;
  late TextEditingController _etimsBranchCodeController;
  late TextEditingController _etimsDeviceSerialController;
  bool _autoSyncEnabled = true;
  bool _cashDrawerEnabled = false;
  bool _quotationsEnabled = true;
  bool _etimsEnabled = false;
  bool _etimsAutoSubmit = true;
  bool _etimsLoading = false;
  bool _etimsSaving = false;
  bool _etimsPlatformActive = false;
  String _etimsSolutionType = 'OSCU';
  String _etimsProviderName = 'KRA eTIMS';

  bool _saving = false;
  bool _hasChanges = false;
  bool _backupBusy = false;
  bool _teamLoading = false;
  bool _customRolesLoading = false;
  List<Map<String, dynamic>> _backups = [];
  List<Map<String, dynamic>> _teamMembers = [];
  List<Map<String, dynamic>> _filteredTeamMembers = [];
  List<Map<String, dynamic>> _customRoles = [];
  late TextEditingController _teamSearchController;

  bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;
  bool get _canManageOperationalSettings =>
      RolePermissions.canManageOperationalSettings(
        SessionService.currentUserRole,
      );
  bool get _canManageUsers =>
      RolePermissions.canManageUsers(SessionService.currentUserRole);
  bool get _canUseCustomRoles => LicenseService.currentSnapshot.allowsFeature(
    UserAccessProfile.featureCustomRoles,
  );

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
    _kraPinController = TextEditingController(text: ShopSettings.kraPin);
    _etimsVatNumberController = TextEditingController(
      text: ShopSettings.etimsVatNumber,
    );
    _etimsBranchCodeController = TextEditingController(
      text: ShopSettings.etimsBranchCode,
    );
    _etimsDeviceSerialController = TextEditingController(
      text: ShopSettings.etimsDeviceSerial,
    );
    _autoSyncEnabled = SyncSettingsService.autoSyncEnabled;
    _cashDrawerEnabled = ShopSettings.cashDrawerEnabled;
    _quotationsEnabled = ShopSettings.quotationsEnabled;
    _etimsEnabled = ShopSettings.etimsEnabled;
    _etimsAutoSubmit = ShopSettings.etimsAutoSubmit;
    _etimsSolutionType = ShopSettings.etimsSolutionType;
    _teamSearchController = TextEditingController()
      ..addListener(_filterTeamMembers);

    _loadBackups();
    _loadEtimsSettings();
    if (_canManageUsers) {
      _loadTeamMembers();
      _loadCustomRoles();
    }
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_markChanged);
    _addressController.removeListener(_markChanged);
    _phoneController.removeListener(_markChanged);
    _emailController.removeListener(_markChanged);
    _taxController.removeListener(_markChanged);
    _currencyController.removeListener(_markChanged);
    _footerController.removeListener(_markChanged);
    _baysController.removeListener(_markChanged);
    _cashDrawerPrinterPathController.removeListener(_markChanged);
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _taxController.dispose();
    _currencyController.dispose();
    _footerController.dispose();
    _baysController.dispose();
    _cashDrawerPrinterPathController.dispose();
    _kraPinController.dispose();
    _etimsVatNumberController.dispose();
    _etimsBranchCodeController.dispose();
    _etimsDeviceSerialController.dispose();
    _teamSearchController.removeListener(_filterTeamMembers);
    _teamSearchController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await LicenseService.ensureWriteAccess(action: 'save settings');
      await ShopSettings.setShopName(_nameController.text.trim());
      await ShopSettings.setShopAddress(_addressController.text.trim());
      await ShopSettings.setShopPhone(_phoneController.text.trim());
      await ShopSettings.setShopEmail(_emailController.text.trim());
      await ShopSettings.setTaxRate(
        double.tryParse(_taxController.text) ?? 8.0,
      );
      final normalizedCurrency = ShopSettings.normalizeCurrency(
        _currencyController.text,
      );
      await ShopSettings.setCurrency(normalizedCurrency);
      await ShopSettings.setReceiptFooter(_footerController.text.trim());
      await ShopSettings.setCarwashBaysCount(
        int.tryParse(_baysController.text) ?? 4,
      );
      await ShopSettings.setCashDrawerEnabled(_cashDrawerEnabled);
      await ShopSettings.setCashDrawerPrinterPath(
        _cashDrawerPrinterPathController.text,
      );
      await ShopSettings.setQuotationsEnabled(_quotationsEnabled);
      await SyncSettingsService.setAutoSyncEnabled(_autoSyncEnabled);
      Object? profileSyncError;
      try {
        await LicenseService.updateBusinessProfile(
          businessName: _nameController.text.trim(),
          currency: normalizedCurrency,
        );
      } catch (error) {
        profileSyncError = error;
        debugPrint(
          '[Settings] Could not update cloud business profile: $error',
        );
      }
      await ref
          .read(syncControllerProvider.notifier)
          .reloadConfiguration(
            triggerSync: _autoSyncEnabled && profileSyncError == null,
          );

      setState(() => _hasChanges = false);
      if (!mounted) {
        return;
      }
      final cloudWarning = profileSyncError == null
          ? null
          : AppErrorMessage.from(
              profileSyncError,
              fallback:
                  'Settings saved on this device, but the online business profile could not be updated.',
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                cloudWarning == null
                    ? Icons.check_circle
                    : Icons.cloud_off_outlined,
                color: Colors.white,
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(cloudWarning ?? 'Settings saved successfully'),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cloudWarning == null
              ? AppColors.success
              : AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          ),
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

  Future<void> _loadEtimsSettings() async {
    setState(() => _etimsLoading = true);
    final settings = await EtimsService.fetchSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _etimsEnabled = settings.isActive;
      _etimsAutoSubmit = settings.autoSubmit;
      _etimsPlatformActive = settings.platformActive;
      _etimsProviderName = settings.providerName;
      _etimsSolutionType = settings.solutionType;
      _kraPinController.text = settings.taxpayerPin;
      _etimsVatNumberController.text = settings.vatNumber;
      _etimsBranchCodeController.text = settings.branchCode;
      _etimsDeviceSerialController.text = settings.deviceSerial;
      _etimsLoading = false;
    });
  }

  Future<void> _saveEtimsSettings() async {
    if (_etimsSaving) {
      return;
    }
    setState(() => _etimsSaving = true);
    try {
      await LicenseService.ensureWriteAccess(action: 'save KRA eTIMS settings');
      final settings = await EtimsService.saveSettings(
        isActive: _etimsEnabled,
        autoSubmit: _etimsAutoSubmit,
        taxpayerPin: _kraPinController.text,
        vatNumber: _etimsVatNumberController.text,
        solutionType: _etimsSolutionType,
        branchCode: _etimsBranchCodeController.text,
        deviceSerial: _etimsDeviceSerialController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _etimsEnabled = settings.isActive;
        _etimsAutoSubmit = settings.autoSubmit;
        _etimsPlatformActive = settings.platformActive;
        _etimsProviderName = settings.providerName;
        _etimsSolutionType = settings.solutionType;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('KRA eTIMS settings saved'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: 'Could not save KRA settings.'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _etimsSaving = false);
      }
    }
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
      _filteredTeamMembers = List.from(users);
      _teamLoading = false;
    });
  }

  Future<void> _loadCustomRoles() async {
    if (!_canManageUsers || !_canUseCustomRoles) {
      return;
    }
    setState(() => _customRolesLoading = true);
    final roles = await CustomRoleRepository.getAll(activeOnly: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _customRoles = roles;
      _customRolesLoading = false;
    });
  }

  void _filterTeamMembers() {
    final query = _teamSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredTeamMembers = List.from(_teamMembers));
      return;
    }
    setState(() {
      _filteredTeamMembers = _teamMembers.where((user) {
        final name = (user['name'] as String? ?? '').toLowerCase();
        final email = (user['email'] as String? ?? '').toLowerCase();
        final role = (user['role'] as String? ?? '').toLowerCase();
        final customRole = (user['custom_role_name'] as String? ?? '')
            .toLowerCase();
        return name.contains(query) ||
            email.contains(query) ||
            role.contains(query) ||
            customRole.contains(query);
      }).toList();
    });
  }

  Future<void> _showAddStaffDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String role = RolePermissions.cashier;
    String customRoleId = '';
    bool saving = false;
    bool showPassword = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Add Staff Account'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.sizeOf(context).height * 0.68,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildField(
                    'Full name',
                    'e.g. Jane Njeri',
                    nameController,
                    Icons.person_outline,
                  ),
                  SizedBox(height: 16),
                  _buildField(
                    'Email',
                    'e.g. jane@example.com',
                    emailController,
                    Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(height: 16),
                  _buildField(
                    'Temporary password',
                    'Set a first login password',
                    passwordController,
                    Icons.lock_outline,
                    obscureText: !showPassword,
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
                  SizedBox(height: 16),
                  _buildSelectField<String>(
                    label: 'Role',
                    value: role,
                    icon: Icons.verified_user_outlined,
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
                        setDialogState(() {
                          role = value;
                          customRoleId = '';
                        });
                      }
                    },
                  ),
                  if (_canUseCustomRoles && _customRoles.isNotEmpty) ...[
                    SizedBox(height: 16),
                    _buildSelectField<String>(
                      label: 'Role Template',
                      value: customRoleId,
                      icon: Icons.admin_panel_settings_outlined,
                      items: [
                        DropdownMenuItem(value: '', child: Text('No template')),
                        ..._customRoles.map(
                          (template) => DropdownMenuItem(
                            value: template['id'] as String? ?? '',
                            child: Text(
                              CustomRoleRepository.roleName(template),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        final nextId = value ?? '';
                        Map<String, dynamic>? template;
                        for (final item in _customRoles) {
                          if (item['id'] == nextId) {
                            template = item;
                            break;
                          }
                        }
                        setDialogState(() {
                          customRoleId = nextId;
                          if (template != null) {
                            role = RolePermissions.normalizeRole(
                              template['base_role'] as String?,
                            );
                          }
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: Text('Cancel'),
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
                          customRoleId: customRoleId,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppErrorMessage.from(
                                  e,
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
              child: saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Create Staff Account'),
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
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _assignTeamCustomRole(String userId, String customRoleId) async {
    try {
      await UserRepository.assignCustomRole(
        userId: userId,
        customRoleId: customRoleId,
      );
      await _loadTeamMembers();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            customRoleId.trim().isEmpty
                ? 'Role template removed'
                : 'Role template assigned',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          ),
          backgroundColor: AppColors.error,
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Admin Access'),
          content: Text(
            'Admin accounts always keep full feature access, full service visibility, and both POS modes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close'),
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
    final aiSeatsWithoutThis = await UserRepository.countAiEnabledUsers(
      excludeUserId: userId,
    );
    if (!mounted) {
      return;
    }
    var posMode = UserAccessProfile.resolvePosMode(
      role: role,
      rawPosMode: user['pos_mode'] as String?,
    );
    const serviceOrderScope =
        UserAccessProfile.serviceOrderScopeAllVisibleServices;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Access for ${user['name'] as String? ?? 'Staff'}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                          style: TextStyle(
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
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: Text(
                          'Settings stays available for password and sign out',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Feature Access',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: UserAccessProfile.configurableFeatures.map((
                      featureKey,
                    ) {
                      final aiSeatBlocked =
                          featureKey == UserAccessProfile.featureAgent &&
                          !selectedFeatures.contains(featureKey) &&
                          !LicenseService.canAddWithinLimit(
                            limit: SubscriptionLimit.aiAgents,
                            currentCount: aiSeatsWithoutThis,
                          );
                      return FilterChip(
                        label: Text(UserAccessProfile.featureLabel(featureKey)),
                        selected: selectedFeatures.contains(featureKey),
                        onSelected: aiSeatBlocked
                            ? null
                            : (selected) {
                                setDialogState(() {
                                  if (selected) {
                                    selectedFeatures.add(featureKey);
                                  } else {
                                    selectedFeatures.remove(featureKey);
                                  }
                                });
                              },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'POS Mode',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  _buildPosModeSelector(posMode, setDialogState),
                  SizedBox(height: 8),
                  Text(
                    'This controls what appears inside the POS screen for this account.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Service orders are shared across staff in the same business. Use service access below to control which service types this account can use.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowAllServices,
                    title: Text(
                      'Allow all services',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Turn this off to choose specific services this staff member can see.',
                    ),
                    onChanged: (value) {
                      setDialogState(() => allowAllServices = value);
                    },
                  ),
                  if (!allowAllServices) ...[
                    SizedBox(height: 8),
                    if (services.isEmpty)
                      Text(
                        'No services created yet.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
                  SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allowAllBranches,
                    title: Text(
                      'Allow all branches',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Turn this off to choose which branches this staff member can use.',
                    ),
                    onChanged: (value) {
                      setDialogState(() => allowAllBranches = value);
                    },
                  ),
                  if (!allowAllBranches) ...[
                    SizedBox(height: 8),
                    if (branches.isEmpty)
                      Text(
                        'No branches created yet.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
              child: Text('Cancel'),
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
                              content: Text(
                                AppErrorMessage.from(
                                  e,
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
              child: saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Save Access'),
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
      return 'Full access - POS: Both - Services: All';
    }
    final templateName = (user['custom_role_name'] as String?)?.trim() ?? '';
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
    final accessParts = [
      if (templateName.isNotEmpty) 'Template: $templateName',
      '$featureCount features',
      'POS: ${_labelForPosMode(posMode)}',
      serviceSummary,
      branchSummary,
    ];
    return accessParts.join(' - ');
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Change Password'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.sizeOf(context).height * 0.68,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildField(
                    'Current password',
                    'Enter current password',
                    currentController,
                    Icons.lock_clock_outlined,
                    obscureText: !showCurrentPassword,
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
                  SizedBox(height: 16),
                  _buildField(
                    'New password',
                    'Enter new password',
                    newController,
                    Icons.lock_outline,
                    obscureText: !showNewPassword,
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
                  SizedBox(height: 16),
                  _buildField(
                    'Confirm new password',
                    'Re-enter new password',
                    confirmController,
                    Icons.verified_user_outlined,
                    obscureText: !showConfirmPassword,
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
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel'),
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
                              content: Text(
                                AppErrorMessage.from(
                                  e,
                                  fallback:
                                      'Could not update the password. Please try again.',
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Update Password'),
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
          content: Text(
            AppErrorMessage.withContext(
              e,
              prefix: 'Backup failed.',
              fallback: 'Backup could not be created. Please try again.',
            ),
          ),
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
          title: Text('Restore Backup'),
          content: Text(
            'Restore ${_fileNameFromPath(backupPath)}?\n\nYour current shop data will be replaced. A safety backup of the current database will be created automatically before restore.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child: Text('Restore'),
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
          content: Text(
            AppErrorMessage.withContext(
              e,
              prefix: 'Restore failed.',
              fallback: 'Backup could not be restored. Please try again.',
            ),
          ),
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
        title: Text('Restore Backup'),
        content: Text(
          'Restore ${backup['name']}?\n\nYour current shop data will be replaced. A safety backup of the current database will be created automatically before restore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: Text('Restore'),
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
          content: Text(
            AppErrorMessage.withContext(
              e,
              prefix: 'Restore failed.',
              fallback: 'Backup could not be restored. Please try again.',
            ),
          ),
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
      SyncIndicatorState.localOnly => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
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
      LicenseAccessStatus.localOnly => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
    };

    return _buildCard([
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_done_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cloud sync uses the app\'s built-in server configuration. End users do not need to enter a backend URL.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 18),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: SwitchListTile.adaptive(
          value: _autoSyncEnabled,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          activeThumbColor: AppColors.primaryLight,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
          title: Text('Auto Sync'),
          subtitle: Text(
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
      SizedBox(height: 18),
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
                SizedBox(width: 10),
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
              SizedBox(height: 10),
              Text(syncState.lastError!, style: TextStyle(fontSize: 12)),
            ] else if (syncState.lastMessage != null &&
                syncState.lastMessage!.trim().isNotEmpty) ...[
              SizedBox(height: 10),
              Text(syncState.lastMessage!, style: TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
      SizedBox(height: 18),
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
                SizedBox(width: 10),
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
            SizedBox(height: 10),
            Text(
              license.detail ?? 'No cloud subscription details yet.',
              style: TextStyle(fontSize: 12),
            ),
            if (license.businessId != null) ...[
              SizedBox(height: 8),
              Text(
                'Business ID: ${license.businessId}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: syncState.isSyncing ? null : _runManualSync,
            icon: syncState.isSyncing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(Icons.sync, size: 18),
            label: Text(syncState.isSyncing ? 'Syncing...' : 'Sync Now'),
          ),
          OutlinedButton.icon(
            onPressed: syncState.isSyncing
                ? null
                : () =>
                      ref.read(syncControllerProvider.notifier).refreshStatus(),
            icon: Icon(Icons.refresh, size: 18),
            label: Text('Refresh Status'),
          ),
        ],
      ),
      SizedBox(height: 18),
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
      SizedBox(height: 18),
      Text(
        'Last synced: ${_formatLastSync(syncState.lastSyncAt)}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      SizedBox(height: 6),
      Text(
        'Device ID: ${syncState.deviceId ?? 'Not created yet'}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      if (license.lastVerifiedAt != null) ...[
        SizedBox(height: 6),
        Text(
          'Subscription checked: ${_formatLastSync(license.lastVerifiedAt)}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    ]);
  }

  Widget _buildSyncStat(String label, String value) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
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
                Icon(
                  Icons.computer_outlined,
                  size: 14,
                  color: AppColors.warning,
                ),
                SizedBox(width: 6),
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
          SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Open physical cash drawer after cash sales',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Disabled until a manager or admin sets the Windows printer share or port.',
            ),
            value: _cashDrawerEnabled,
            onChanged: (value) {
              setState(() => _cashDrawerEnabled = value);
              _markChanged();
            },
          ),
          SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Enable quotations in POS',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Adds a Quotation tab next to Sale on the POS screen.',
            ),
            value: _quotationsEnabled,
            onChanged: (value) {
              setState(() => _quotationsEnabled = value);
              _markChanged();
            },
          ),
          SizedBox(height: 12),
          _buildField(
            'Drawer Printer Share / Port',
            r'e.g. \\localhost\ReceiptPrinter or LPT1:',
            _cashDrawerPrinterPathController,
            Icons.print_outlined,
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _cashDrawerEnabled ? _testCashDrawer : null,
                icon: Icon(Icons.lock_open_outlined, size: 18),
                label: Text('Test Open'),
              ),
              OutlinedButton.icon(
                onPressed: _showCashDrawerSetupGuide,
                icon: Icon(Icons.checklist_outlined, size: 18),
                label: Text('Setup Wizard'),
              ),
              Text(
                'Test open is limited to managers and admins.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCashDrawerSetupGuide() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cash Drawer Setup'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. Connect the cash drawer to the receipt printer.'),
              SizedBox(height: 8),
              Text('2. Confirm the printer can print from Windows.'),
              SizedBox(height: 8),
              Text(
                r'3. Enter the printer share, for example \\localhost\ReceiptPrinter, or a port like LPT1:.',
              ),
              SizedBox(height: 8),
              Text('4. Save settings, then use Test Open.'),
              SizedBox(height: 12),
              Text(
                'If the drawer does not open, check printer drivers, drawer cable type, and ESC/POS drawer command support.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close')),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Open Cash Drawer?'),
        content: Text(
          'This will send an open command to the configured drawer printer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(Icons.lock_open_outlined, size: 18),
            label: Text('Open Drawer'),
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

  void _openSettingsMiniPage({
    required String title,
    required IconData icon,
    required Widget child,
    double maxWidth = 840,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsMiniPage(
          title: title,
          icon: icon,
          maxWidth: maxWidth,
          child: child,
        ),
      ),
    );
  }

  Widget _buildSaveSettingsButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: _save,
        icon: Icon(Icons.save_outlined, size: 18),
        label: Text('Save settings'),
      ),
    );
  }

  Widget _buildShopProfilePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCard([
          _buildField(
            'Shop Name',
            'e.g. Downtown Electronics',
            _nameController,
            Icons.storefront,
          ),
          SizedBox(height: 20),
          _buildField(
            'Address',
            'e.g. 123 Main Street, City',
            _addressController,
            Icons.location_on_outlined,
          ),
          SizedBox(height: 20),
          _buildResponsiveFieldPair(
            first: _buildField(
              'Phone Number',
              'e.g. (555) 123-4567',
              _phoneController,
              Icons.phone_outlined,
            ),
            second: _buildField(
              'Email',
              'e.g. shop@example.com',
              _emailController,
              Icons.email_outlined,
            ),
          ),
          SizedBox(height: 20),
          _buildResponsiveFieldPair(
            first: _buildField(
              'Tax Rate (%)',
              '8.0',
              _taxController,
              Icons.percent,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              keyboardType: TextInputType.number,
            ),
            second: _buildField(
              'Currency Symbol',
              '\$',
              _currencyController,
              Icons.attach_money,
            ),
          ),
        ]),
        SizedBox(height: 16),
        _buildSaveSettingsButton(),
      ],
    );
  }

  Widget _buildAppearancePage() {
    final themeMode = ref.watch(themeProvider);
    final theme = Theme.of(context);

    final items = ThemeMode.values.map((mode) {
      final label = switch (mode) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
      return DropdownMenuItem<ThemeMode>(value: mode, child: Text(label));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCard([
          Text(
            'Theme',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Choose whether Piki POS follows your device setting or always uses light or dark mode.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 16),
          _buildSelectField<ThemeMode>(
            label: 'Appearance',
            value: themeMode,
            icon: Icons.brightness_6_outlined,
            items: items,
            onChanged: (mode) {
              if (mode != null) {
                ref.read(themeProvider.notifier).setMode(mode);
              }
            },
          ),
        ]),
      ],
    );
  }

  Widget _buildReceiptSettingsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCard([
          _buildField(
            'Receipt Footer Message',
            'Thank you for your purchase!',
            _footerController,
            Icons.message_outlined,
            maxLines: 2,
          ),
        ]),
        SizedBox(height: 16),
        _buildSaveSettingsButton(),
        SizedBox(height: 28),
        _buildSectionHeader(Icons.preview_outlined, 'Receipt Preview'),
        SizedBox(height: 16),
        _buildReceiptPreview(),
      ],
    );
  }

  Widget _buildEtimsSettingsPage() {
    if (_etimsLoading) {
      return Center(child: CircularProgressIndicator());
    }

    final statusColor = _etimsPlatformActive
        ? AppColors.success
        : AppColors.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCard([
          Row(
            children: [
              Icon(Icons.account_balance_outlined, color: statusColor),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  _etimsPlatformActive
                      ? 'Platform connector ready: $_etimsProviderName'
                      : 'Platform connector not active yet. Ask super admin to configure the certified OSCU/VSCU provider.',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'KRA/eTIMS requires a certified OSCU or VSCU setup. Shop owners enter their taxpayer details here; provider credentials stay on the backend.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 16),
          SwitchListTile.adaptive(
            value: _etimsEnabled,
            onChanged: (value) => setState(() => _etimsEnabled = value),
            contentPadding: EdgeInsets.zero,
            title: Text('Enable KRA eTIMS'),
            subtitle: Text(
              'When enabled, sales can be submitted to the configured eTIMS connector.',
            ),
          ),
          SwitchListTile.adaptive(
            value: _etimsAutoSubmit,
            onChanged: _etimsEnabled
                ? (value) => setState(() => _etimsAutoSubmit = value)
                : null,
            contentPadding: EdgeInsets.zero,
            title: Text('Auto-submit after each sale'),
            subtitle: Text(
              'If offline or not configured, the sale is marked for follow-up instead of blocking checkout.',
            ),
          ),
        ]),
        SizedBox(height: 16),
        _buildCard([
          _buildResponsiveFieldPair(
            first: _buildField(
              'KRA PIN',
              'e.g. P000000000A',
              _kraPinController,
              Icons.badge_outlined,
            ),
            second: _buildField(
              'VAT Number (optional)',
              'Leave blank if same as PIN',
              _etimsVatNumberController,
              Icons.receipt_outlined,
            ),
          ),
          SizedBox(height: 20),
          _buildResponsiveFieldPair(
            first: _buildSelectField(
              label: 'Solution Type',
              value: _etimsSolutionType == 'VSCU' ? 'VSCU' : 'OSCU',
              icon: Icons.memory_outlined,
              items: const [
                DropdownMenuItem(value: 'OSCU', child: Text('OSCU')),
                DropdownMenuItem(value: 'VSCU', child: Text('VSCU')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _etimsSolutionType = value);
              },
            ),
            second: _buildField(
              'Branch Code',
              'e.g. 00',
              _etimsBranchCodeController,
              Icons.store_outlined,
            ),
          ),
          SizedBox(height: 20),
          _buildField(
            'OSCU/VSCU Device Serial',
            'Device or virtual control unit serial',
            _etimsDeviceSerialController,
            Icons.confirmation_number_outlined,
          ),
        ]),
        SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _etimsSaving ? null : _saveEtimsSettings,
            icon: _etimsSaving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.save_outlined, size: 18),
            label: Text(_etimsSaving ? 'Saving...' : 'Save KRA eTIMS'),
          ),
        ),
      ],
    );
  }

  Widget _buildOperationalSettingsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            SizedBox(height: 20),
            _buildCashDrawerCard(),
          ],
        ]),
        SizedBox(height: 16),
        _buildSaveSettingsButton(),
      ],
    );
  }

  Widget _buildCloudSyncPage(SyncState syncState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSyncCard(syncState),
        SizedBox(height: 16),
        _buildSaveSettingsButton(),
      ],
    );
  }

  Map<String, dynamic> _syncDiagnostics(SyncState syncState) {
    return {
      'label': syncState.shortLabel,
      'online': syncState.isOnline,
      'pendingChanges': syncState.pendingChanges,
      'remoteChanges': syncState.remoteChanges,
      'conflictCount': syncState.conflictCount,
      'errorCount': syncState.errorCount,
      'lastError': syncState.lastError,
      'lastMessage': syncState.lastMessage,
    };
  }

  Future<String> _buildDiagnosticsReport(SyncState syncState) {
    return SupportDiagnosticsService.buildReport(
      sync: _syncDiagnostics(syncState),
    );
  }

  Future<void> _copyDiagnostics(SyncState syncState) async {
    final report = await _buildDiagnosticsReport(syncState);
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics copied. You can paste them into support.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _contactSupport(SyncState syncState) async {
    final report = await _buildDiagnosticsReport(syncState);
    await Clipboard.setData(ClipboardData(text: report));
    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      queryParameters: {
        'subject': 'Piki POS support - ${ShopSettings.shopName}',
        'body':
            'Hi Piki support,\n\nPlease help with this issue:\n\n\nDiagnostics have been copied to my clipboard. I can paste them here if needed.\n',
      },
    );
    if (await ExternalAppLauncher.launch(uri)) {
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Diagnostics copied. Email ${AppConstants.supportEmail} for support.',
        ),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  Widget _buildSupportPage(SyncState syncState) {
    return _buildCard([
      Text(
        'When something feels wrong, send diagnostics before changing data. The report includes app, sync, license, and database counts but not passwords.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: () => _contactSupport(syncState),
            icon: Icon(Icons.support_agent_outlined, size: 18),
            label: Text('Contact Support'),
          ),
          OutlinedButton.icon(
            onPressed: () => _copyDiagnostics(syncState),
            icon: Icon(Icons.bug_report_outlined, size: 18),
            label: Text('Copy Diagnostics'),
          ),
        ],
      ),
      SizedBox(height: 18),
      _buildSyncStat('Sync', syncState.shortLabel),
      SizedBox(height: 12),
      _buildSyncStat('Last Sync', _formatLastSync(syncState.lastSyncAt)),
      SizedBox(height: 12),
      _buildSyncStat(
        'Issues',
        '${syncState.conflictCount + syncState.errorCount}',
      ),
      SizedBox(height: 18),
      Text(
        'Support email: ${AppConstants.supportEmail}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    ]);
  }

  Widget _buildBackupGuidanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Backup guidance',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Create a backup before major edits, before restoring another file, and before moving devices. On phones, copy the backup location and save the file to Drive, WhatsApp, or another safe storage location.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopSettingsPagesSection(SyncState syncState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.tune_outlined, 'Shop Settings'),
        SizedBox(height: 4),
        Text(
          'Open one area at a time to update your shop and device setup.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns =
                constraints.maxWidth >= (_settingsTileMinWidth * 2) + 12;
            final cardWidth = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.storefront_outlined,
                    title: 'Shop Profile',
                    subtitle: 'Contact details, tax rate, and currency.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Shop Profile',
                      icon: Icons.storefront_outlined,
                      child: _buildShopProfilePage(),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.palette_outlined,
                    title: 'Online Storefront',
                    subtitle: 'Logo, cover photo, brand color, and store link.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Online Storefront',
                      icon: Icons.palette_outlined,
                      maxWidth: 920,
                      child: const StorefrontBrandSettingsSection(),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.dark_mode_outlined,
                    title: 'Appearance',
                    subtitle: 'Choose light, dark, or system theme.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Appearance',
                      icon: Icons.dark_mode_outlined,
                      child: _buildAppearancePage(),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'Receipts',
                    subtitle: 'Footer message and receipt preview.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Receipts',
                      icon: Icons.receipt_long_outlined,
                      child: _buildReceiptSettingsPage(),
                    ),
                  ),
                ),
                if (SessionService.canAccessFeature(
                  UserAccessProfile.featureMultiCurrency,
                ))
                  SizedBox(
                    width: cardWidth,
                    child: _buildFeaturePageCard(
                      icon: Icons.currency_exchange_outlined,
                      title: 'Multi-Currency',
                      subtitle: 'Secondary currency and POS dual display.',
                      onTap: () => _openSettingsMiniPage(
                        title: 'Multi-Currency',
                        icon: Icons.currency_exchange_outlined,
                        child: const MultiCurrencySection(),
                      ),
                    ),
                  ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.account_balance_outlined,
                    title: 'KRA eTIMS',
                    subtitle: 'KRA PIN, OSCU/VSCU device, and auto-submit.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'KRA eTIMS',
                      icon: Icons.account_balance_outlined,
                      child: _buildEtimsSettingsPage(),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.garage_outlined,
                    title: 'Operations',
                    subtitle: 'Car wash bays and connected cash drawer.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Operations',
                      icon: Icons.garage_outlined,
                      child: _buildOperationalSettingsPage(),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: TrainingAnchor(
                    id: 'settings.sync',
                    child: _buildFeaturePageCard(
                      icon: Icons.cloud_sync_outlined,
                      title: 'Cloud Sync',
                      subtitle: 'Review cloud status and sync this device.',
                      onTap: () => _openSettingsMiniPage(
                        title: 'Cloud Sync',
                        icon: Icons.cloud_sync_outlined,
                        child: _buildCloudSyncPage(syncState),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: TrainingAnchor(
                    id: 'settings.backup',
                    child: _buildFeaturePageCard(
                      icon: Icons.backup_outlined,
                      title: 'Backup & Restore',
                      subtitle: 'Create snapshots or restore shop data.',
                      onTap: () => _openSettingsMiniPage(
                        title: 'Backup & Restore',
                        icon: Icons.backup_outlined,
                        child: _buildBackupCard(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildTrainingHelpPage(
    TrainingController training,
    int progressPercent,
  ) {
    return _buildCard([
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
      SizedBox(height: 16),
      Text(
        'Training progress is saved separately for each signed-in staff member.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      SizedBox(height: 16),
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
            icon: Icon(Icons.play_circle_outline, size: 18),
            label: Text('Open Training Hub'),
          ),
          OutlinedButton.icon(
            onPressed: training.availableModuleCount == 0
                ? null
                : () => ref.read(trainingControllerProvider).startFullTour(),
            icon: Icon(Icons.route_outlined, size: 18),
            label: Text('Start Full Tour'),
          ),
        ],
      ),
    ]);
  }

  Widget _buildManagementPagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          Icons.dashboard_customize_outlined,
          'Business Management',
        ),
        SizedBox(height: 4),
        Text(
          'Manage billing, integrations, locations, and staff access.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns =
                constraints.maxWidth >= (_settingsTileMinWidth * 2) + 12;
            final cardWidth = twoColumns
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (_canManageUsers)
                  SizedBox(
                    width: cardWidth,
                    child: TrainingAnchor(
                      id: 'settings.team',
                      child: _buildFeaturePageCard(
                        icon: Icons.groups_outlined,
                        title: 'Team Access',
                        subtitle: 'Create staff accounts and set permissions.',
                        onTap: () => _openSettingsMiniPage(
                          title: 'Team Access',
                          icon: Icons.groups_outlined,
                          child: _buildTeamCard(),
                        ),
                      ),
                    ),
                  ),
                if (_canManageUsers && _canUseCustomRoles)
                  SizedBox(
                    width: cardWidth,
                    child: _buildFeaturePageCard(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Roles & Permissions',
                      subtitle:
                          'Reusable permission templates for staff accounts.',
                      onTap: () => _openSettingsMiniPage(
                        title: 'Roles & Permissions',
                        icon: Icons.admin_panel_settings_outlined,
                        maxWidth: 900,
                        child: CustomRolesSection(
                          onRolesChanged: () async {
                            await _loadCustomRoles();
                            await _loadTeamMembers();
                          },
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Subscription',
                    subtitle: 'Plans, billing, limits, and business type.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Subscription',
                      icon: Icons.workspace_premium_outlined,
                      maxWidth: 1180,
                      child: const SubscriptionPlansSection(),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.payment_outlined,
                    title: 'Payments',
                    subtitle: 'Checkout methods and your own sales M-Pesa.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Payments',
                      icon: Icons.payment_outlined,
                      child: const PaymentMethodsSection(),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.message_outlined,
                    title: 'Messaging',
                    subtitle: 'WhatsApp and SMS business defaults.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Messaging',
                      icon: Icons.message_outlined,
                      child: const CommunicationSettingsSection(),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.store_mall_directory_outlined,
                    title: 'Branches',
                    subtitle: 'Branch list, access, and locations.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BranchManagementScreen(),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _buildFeaturePageCard(
                    icon: Icons.manage_search_outlined,
                    title: 'Audit Logs',
                    subtitle: 'Review staff and system activity.',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AuditLogScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFeaturePageCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colors.primary, size: 21),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          if (_canManageUsers) {
            _loadTeamMembers();
            _loadCustomRoles();
          }
          ref.invalidate(paymentMethodsProvider);
          ref.invalidate(activePaymentMethodsProvider);
        }
      },
    );

    final syncState = ref.watch(syncControllerProvider);
    final training = ref.watch(trainingControllerProvider);
    final progressPercent = (training.completionRatio * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        actions: [
          if (_canManageOperationalSettings && _hasChanges)
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Icon(Icons.save, size: 18),
              label: Text('Save'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          SizedBox(width: 16),
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
                _buildSectionHeader(
                  Icons.admin_panel_settings_outlined,
                  'My Account',
                ),
                SizedBox(height: 4),
                Text(
                  'Manage your current login and password.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 16),
                TrainingAnchor(
                  id: 'settings.account',
                  child: _buildAccountCard(),
                ),
                SizedBox(height: 32),
                _buildSectionHeader(Icons.school_outlined, 'Training & Help'),
                SizedBox(height: 4),
                Text(
                  'Replay guided tours whenever a staff member needs a refresher.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 16),
                TrainingAnchor(
                  id: 'settings.training',
                  child: _buildFeaturePageCard(
                    icon: Icons.school_outlined,
                    title: 'Training Hub',
                    subtitle:
                        '${training.completedModuleCount}/${training.availableModuleCount} modules complete - $progressPercent% progress.',
                    onTap: () => _openSettingsMiniPage(
                      title: 'Training & Help',
                      icon: Icons.school_outlined,
                      child: _buildTrainingHelpPage(training, progressPercent),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                _buildFeaturePageCard(
                  icon: Icons.support_agent_outlined,
                  title: 'Support & Diagnostics',
                  subtitle:
                      'Contact support and copy a safe diagnostics report.',
                  onTap: () => _openSettingsMiniPage(
                    title: 'Support & Diagnostics',
                    icon: Icons.support_agent_outlined,
                    child: _buildSupportPage(syncState),
                  ),
                ),
                if (!_canManageOperationalSettings) ...[
                  SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    child: Text(
                      'Shop settings, backup controls, and receipt configuration are limited to managers and admins.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(height: 32),
                ] else ...[
                  SizedBox(height: 32),
                  _buildShopSettingsPagesSection(syncState),
                  SizedBox(height: 32),
                  _buildManagementPagesSection(),
                  SizedBox(height: 32),
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
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SessionService.currentUserName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  SessionService.currentUserEmail,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              style: TextStyle(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: _showChangePasswordDialog,
            icon: Icon(Icons.lock_reset_outlined, size: 18),
            label: Text('Change Password'),
          ),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: Icon(Icons.logout, size: 18),
            label: Text('Sign Out'),
          ),
        ],
      ),
    ]);
  }

  Widget _buildTeamCard() {
    final colors = Theme.of(context).colorScheme;
    return _buildCard([
      // Search + Add Member bar
      LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 560;
          final searchField = TextField(
            controller: _teamSearchController,
            decoration: InputDecoration(
              hintText: 'Search team members...',
              prefixIcon: Icon(Icons.search, color: colors.onSurfaceVariant),
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colors.outline.withValues(alpha: 0.5),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colors.outline.withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
            ),
          );
          final addButton = SizedBox(
            width: isWide ? null : double.infinity,
            child: FilledButton.icon(
              onPressed: _showAddStaffDialog,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add Member'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          );
          if (isWide) {
            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 16),
                addButton,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [searchField, const SizedBox(height: 12), addButton],
          );
        },
      ),
      const SizedBox(height: 20),
      // Directory header
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Directory (${_filteredTeamMembers.length} Members)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          IconButton(
            onPressed: _teamLoading ? null : _loadTeamMembers,
            icon: _teamLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  )
                : const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_teamLoading && _filteredTeamMembers.isEmpty)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        )
      else if (_filteredTeamMembers.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 48),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                Icons.groups_outlined,
                size: 40,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                _teamMembers.isEmpty
                    ? 'No staff accounts yet.'
                    : 'No members match your search.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        )
      else
        Column(
          children: _filteredTeamMembers.asMap().entries.map((entry) {
            final index = entry.key;
            final user = entry.value;
            return _buildTeamMemberCard(user, index);
          }).toList(),
        ),
    ]);
  }

  Widget _buildTeamMemberCard(Map<String, dynamic> user, int index) {
    final colors = Theme.of(context).colorScheme;
    final userId = user['id'] as String? ?? '';
    final name = user['name'] as String? ?? 'User';
    final email = user['email'] as String? ?? '';
    final selectedRole = (user['role'] as String? ?? RolePermissions.cashier)
        .toUpperCase();
    final normalizedRole = RolePermissions.normalizeRole(selectedRole);
    final selectedCustomRoleId = user['custom_role_id'] as String? ?? '';
    final canAssignTemplate =
        _canUseCustomRoles && normalizedRole != RolePermissions.admin;
    final customRoleItems = _customRoleDropdownItems(user);
    final initials = name.trim().isNotEmpty
        ? name
              .trim()
              .split(' ')
              .take(2)
              .map((p) => p.isNotEmpty ? p[0].toUpperCase() : '')
              .join('')
        : '?';

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outline.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: colors.primary.withValues(
                            alpha: 0.12,
                          ),
                          foregroundColor: colors.primary,
                          child: Text(
                            initials,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        if (normalizedRole == RolePermissions.admin)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Icon(
                                Icons.verified,
                                size: 14,
                                color: colors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 6,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                              _buildRoleBadge(normalizedRole),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _buildStaffAccessSummary(user),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                // Actions
                Flex(
                  direction: isWide ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: isWide
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.stretch,
                  children: [
                    // Role dropdown
                    SizedBox(
                      width: isWide ? 180 : double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel('Role'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: selectedRole,
                            isExpanded: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
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
                        ],
                      ),
                    ),
                    if (canAssignTemplate) ...[
                      if (isWide)
                        const SizedBox(width: 12)
                      else
                        const SizedBox(height: 10),
                      SizedBox(
                        width: isWide ? 230 : double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FieldLabel('Template'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: selectedCustomRoleId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: customRoleItems,
                              onChanged: _customRolesLoading
                                  ? null
                                  : (value) {
                                      if (value != null &&
                                          value != selectedCustomRoleId) {
                                        _assignTeamCustomRole(userId, value);
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isWide)
                      const SizedBox(width: 12)
                    else
                      const SizedBox(height: 10),
                    if (isWide)
                      Expanded(
                        child: OverflowBar(
                          alignment: MainAxisAlignment.end,
                          spacing: 10,
                          overflowSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showTeamAccessDialog(user),
                              icon: const Icon(Icons.tune, size: 18),
                              label: const Text('Edit Access'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: () =>
                                  _showTeamMemberProfileDialog(user),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 18,
                              ),
                              label: const Text('View Profile'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _showTeamAccessDialog(user),
                              icon: const Icon(Icons.tune, size: 18),
                              label: const Text('Edit Access'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  _showTeamMemberProfileDialog(user),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 18,
                              ),
                              label: const Text('View Profile'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    final colors = Theme.of(context).colorScheme;
    final label = RolePermissions.label(role);
    Color bg;
    Color fg;
    switch (role.toUpperCase()) {
      case RolePermissions.admin:
        bg = colors.secondaryContainer;
        fg = colors.onSecondaryContainer;
        break;
      case RolePermissions.manager:
        bg = colors.tertiaryContainer;
        fg = colors.onTertiaryContainer;
        break;
      default:
        bg = colors.surfaceContainerHighest;
        fg = colors.onSurfaceVariant;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  List<DropdownMenuItem<String>> _customRoleDropdownItems(
    Map<String, dynamic> user,
  ) {
    final selectedCustomRoleId = user['custom_role_id'] as String? ?? '';
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('No template')),
    ];
    var selectedTemplatePresent = selectedCustomRoleId.isEmpty;
    for (final template in _customRoles) {
      final templateId = template['id'] as String? ?? '';
      if (templateId.isEmpty) {
        continue;
      }
      if (templateId == selectedCustomRoleId) {
        selectedTemplatePresent = true;
      }
      items.add(
        DropdownMenuItem(
          value: templateId,
          child: Text(CustomRoleRepository.roleName(template)),
        ),
      );
    }
    if (!selectedTemplatePresent) {
      final label =
          (user['custom_role_name'] as String?)?.trim().isNotEmpty == true
          ? user['custom_role_name'] as String
          : 'Template unavailable';
      items.add(
        DropdownMenuItem(
          value: selectedCustomRoleId,
          child: Text('$label (inactive)'),
        ),
      );
    }
    return items;
  }

  Future<void> _showTeamMemberProfileDialog(Map<String, dynamic> user) async {
    final colors = Theme.of(context).colorScheme;
    final name = user['name'] as String? ?? 'User';
    final email = user['email'] as String? ?? '';
    final role = RolePermissions.normalizeRole(user['role'] as String?);
    final templateName = (user['custom_role_name'] as String?)?.trim() ?? '';
    final initials = name.trim().isNotEmpty
        ? name
              .trim()
              .split(' ')
              .take(2)
              .map((p) => p.isNotEmpty ? p[0].toUpperCase() : '')
              .join('')
        : '?';

    final allServices = await ServiceRepository.getServices();
    final allBranches = await BranchService.getBranches(activeOnly: true);
    if (!mounted) return;

    final features = UserAccessProfile.resolveFeatureAccess(
      role: role,
      rawFeatureAccessJson: user['feature_access_json'] as String?,
    );
    final allowedServiceIds = UserAccessProfile.resolveAllowedServiceIds(
      role: role,
      rawAllowedServiceIdsJson: user['allowed_service_ids_json'] as String?,
    );
    final allowedBranchIds = UserAccessProfile.resolveAllowedBranchIds(
      role: role,
      rawAllowedBranchIdsJson: user['allowed_branch_ids_json'] as String?,
    );
    final posMode = UserAccessProfile.resolvePosMode(
      role: role,
      rawPosMode: user['pos_mode'] as String?,
    );

    final serviceNames =
        allowedServiceIds.isEmpty && role == RolePermissions.admin
        ? const <String>[]
        : allServices
              .where((s) => allowedServiceIds.contains(s['id'] as String?))
              .map((s) => s['name'] as String? ?? 'Service')
              .toList();
    final branchNames =
        allowedBranchIds.isEmpty && role == RolePermissions.admin
        ? const <String>[]
        : allBranches
              .where((b) => allowedBranchIds.contains(b['id'] as String?))
              .map((b) => b['name'] as String? ?? 'Branch')
              .toList();

    final featureDisplayList = [
      UserAccessProfile.featureDashboard,
      UserAccessProfile.featurePos,
      UserAccessProfile.featureProducts,
      UserAccessProfile.featureCategories,
      UserAccessProfile.featurePurchases,
      UserAccessProfile.featureSales,
      UserAccessProfile.featureKopesha,
      UserAccessProfile.featureProfitLoss,
      UserAccessProfile.featureReports,
      UserAccessProfile.featureShifts,
      UserAccessProfile.featureServices,
      UserAccessProfile.featureAgent,
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: double.infinity,
                    color: colors.primary.withValues(alpha: 0.08),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: colors.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Text(
                            initials,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildRoleBadge(role),
                        if (templateName.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildProfileInfoChip(
                            'Template: $templateName',
                            colors,
                          ),
                        ],
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            email,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProfileSectionTitle(
                          Icons.point_of_sale_outlined,
                          'POS Mode',
                        ),
                        const SizedBox(height: 10),
                        _buildProfileInfoChip(
                          _labelForPosMode(posMode),
                          colors,
                        ),
                        const SizedBox(height: 22),
                        _buildProfileSectionTitle(
                          Icons.business_outlined,
                          'Branches',
                        ),
                        const SizedBox(height: 10),
                        _buildNamedChips(
                          names: branchNames,
                          isUnrestricted:
                              role == RolePermissions.admin ||
                              allowedBranchIds.isEmpty,
                          unrestrictedLabel: 'All branches',
                          emptyLabel: 'No branches assigned',
                          colors: colors,
                        ),
                        const SizedBox(height: 22),
                        _buildProfileSectionTitle(
                          Icons.design_services_outlined,
                          'Services',
                        ),
                        const SizedBox(height: 10),
                        _buildNamedChips(
                          names: serviceNames,
                          isUnrestricted:
                              role == RolePermissions.admin ||
                              allowedServiceIds.isEmpty,
                          unrestrictedLabel: 'All services',
                          emptyLabel: 'No services assigned',
                          colors: colors,
                        ),
                        const SizedBox(height: 22),
                        _buildProfileSectionTitle(
                          Icons.widgets_outlined,
                          'Feature Access',
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: featureDisplayList.map((feature) {
                            final hasAccess = features.contains(feature);
                            return _buildFeatureAccessChip(
                              UserAccessProfile.featureLabel(feature),
                              hasAccess,
                              colors,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSectionTitle(IconData icon, String title) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfoChip(String label, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
    );
  }

  Widget _buildNamedChips({
    required List<String> names,
    required bool isUnrestricted,
    required String unrestrictedLabel,
    required String emptyLabel,
    required ColorScheme colors,
  }) {
    if (isUnrestricted) {
      return _buildProfileInfoChip(unrestrictedLabel, colors);
    }
    if (names.isEmpty) {
      return Text(
        emptyLabel,
        style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: names
          .map((name) => _buildProfileInfoChip(name, colors))
          .toList(),
    );
  }

  Widget _buildFeatureAccessChip(
    String label,
    bool hasAccess,
    ColorScheme colors,
  ) {
    final bgColor = hasAccess
        ? AppColors.success.withValues(alpha: 0.12)
        : colors.onSurfaceVariant.withValues(alpha: 0.08);
    final fgColor = hasAccess ? AppColors.success : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fgColor.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasAccess
                ? Icons.check_circle_outline_rounded
                : Icons.block_rounded,
            size: 14,
            color: fgColor,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPosModeSelector(
    String posMode,
    void Function(void Function()) setDialogState,
  ) {
    final colors = Theme.of(context).colorScheme;
    final options = [
      (
        value: UserAccessProfile.posModeProducts,
        label: 'Products Only',
        icon: Icons.inventory_2_outlined,
      ),
      (
        value: UserAccessProfile.posModeBoth,
        label: 'Both',
        icon: Icons.view_week_outlined,
      ),
      (
        value: UserAccessProfile.posModeServices,
        label: 'Services Only',
        icon: Icons.design_services_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 420;
        if (isWide) {
          return SegmentedButton<String>(
            segments: options
                .map(
                  (option) => ButtonSegment(
                    value: option.value,
                    icon: Icon(option.icon),
                    label: Text(option.label),
                  ),
                )
                .toList(),
            selected: {posMode},
            onSelectionChanged: (selection) {
              setDialogState(() => posMode = selection.first);
            },
            showSelectedIcon: false,
          );
        }
        return DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          initialValue: posMode,
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: option.value,
                  child: Row(
                    children: [
                      Icon(
                        option.icon,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Text(option.label),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setDialogState(() => posMode = value);
            }
          },
        );
      },
    );
  }

  Widget _buildBackupCard() {
    return _buildCard([
      _buildBackupGuidanceCard(),
      SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: _backupBusy ? null : _createBackup,
            icon: _backupBusy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(Icons.save_alt, size: 18),
            label: Text(_backupBusy ? 'Working...' : 'Create Backup'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
          OutlinedButton.icon(
            onPressed: _backupBusy ? null : _loadBackups,
            icon: Icon(Icons.refresh, size: 18),
            label: Text('Refresh List'),
          ),
          if (_isMobilePlatform)
            OutlinedButton.icon(
              onPressed: _backupBusy ? null : _importBackupFromFile,
              icon: Icon(Icons.upload_file_outlined, size: 18),
              label: Text('Import Backup'),
            ),
        ],
      ),
      SizedBox(height: 20),
      if (_backups.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'No backups yet. Create your first snapshot before major changes.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    backup['name'] as String? ?? 'Backup',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '${_formatBackupDate(backup['modified_at'] as String?)} - ${_formatBackupSize(backup['size_bytes'] as int? ?? 0)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _backupBusy
                            ? null
                            : () => _copyBackupPath(backup['path'] as String),
                        icon: Icon(Icons.copy_outlined, size: 18),
                        label: Text(
                          _isMobilePlatform ? 'Copy Location' : 'Copy Path',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _backupBusy
                            ? null
                            : () => _restoreBackup(backup),
                        icon: Icon(Icons.restore_outlined, size: 18),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                        ),
                        label: Text('Restore Backup'),
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          Text(
            _nameController.text.isEmpty ? 'My Shop' : _nameController.text,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colors.onSurface,
            ),
          ),
          if (_addressController.text.isNotEmpty) ...[
            SizedBox(height: 4),
            Text(
              _addressController.text,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
          if (_phoneController.text.isNotEmpty) ...[
            SizedBox(height: 2),
            Text(
              'Phone: ${_phoneController.text}',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
          SizedBox(height: 12),
          Container(height: 1, color: colors.outline),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sample Item x2',
                style: TextStyle(fontSize: 12, color: colors.onSurface),
              ),
              Text(
                '\$19.98',
                style: TextStyle(fontSize: 12, color: colors.onSurface),
              ),
            ],
          ),
          SizedBox(height: 8),
          Container(height: 1, color: colors.outline),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              Text(
                '${_currencyController.text}19.98',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            _footerController.text.isEmpty
                ? 'Thank you for your purchase!'
                : _footerController.text,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceVariant,
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
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colors.primary),
        SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 480;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
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
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 48,
            ),
            suffixIcon: suffixIcon,
            alignLabelWithHint: maxLines > 1,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectField<T>({
    required String label,
    required T value,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        SizedBox(height: 8),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 48,
            ),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildResponsiveFieldPair({
    required Widget first,
    required Widget second,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth >=
            (_fieldPairMinColumnWidth * 2) + _fieldPairGap;
        if (!twoColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              SizedBox(height: _fieldPairGap),
              second,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            SizedBox(width: _fieldPairGap),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      softWrap: true,
      overflow: TextOverflow.visible,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SettingsMiniPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final double maxWidth;
  final Widget child;

  const _SettingsMiniPage({
    required this.title,
    required this.icon,
    this.maxWidth = 840,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
            SizedBox(width: 10),
            Flexible(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}
