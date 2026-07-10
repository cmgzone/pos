import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'license_service.dart';

class SessionService {
  static SharedPreferences? _prefs;

  static const _keyCurrentUserId = 'current_user_id';
  static const _keyCurrentUserName = 'current_user_name';
  static const _keyCurrentUserEmail = 'current_user_email';
  static const _keyCurrentUserRole = 'current_user_role';
  static const _keyCurrentFeatureAccessJson = 'current_feature_access_json';
  static const _keyCurrentAllowedServiceIdsJson =
      'current_allowed_service_ids_json';
  static const _keyCurrentAllowedBranchIdsJson =
      'current_allowed_branch_ids_json';
  static const _keyCurrentPosMode = 'current_pos_mode';
  static const _keyCurrentServiceOrderScope = 'current_service_order_scope';

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static bool get isLoggedIn => currentUserId.isNotEmpty;

  static String get currentUserId => _prefs?.getString(_keyCurrentUserId) ?? '';

  static String get currentUserName =>
      _prefs?.getString(_keyCurrentUserName) ?? 'Unknown Cashier';

  static String get currentUserEmail =>
      _prefs?.getString(_keyCurrentUserEmail) ?? '';

  static String get currentUserRole =>
      RolePermissions.normalizeRole(_prefs?.getString(_keyCurrentUserRole));

  static String? get currentFeatureAccessJson =>
      _prefs?.getString(_keyCurrentFeatureAccessJson);

  static String? get currentAllowedServiceIdsJson =>
      _prefs?.getString(_keyCurrentAllowedServiceIdsJson);

  static String? get currentAllowedBranchIdsJson =>
      _prefs?.getString(_keyCurrentAllowedBranchIdsJson);

  static String get currentPosMode => UserAccessProfile.resolvePosMode(
    role: currentUserRole,
    rawPosMode: _prefs?.getString(_keyCurrentPosMode),
  );

  static String get currentServiceOrderScope =>
      UserAccessProfile.resolveServiceOrderScope(
        role: currentUserRole,
        rawScope: _prefs?.getString(_keyCurrentServiceOrderScope),
      );

  static List<String> get currentFeatureAccess =>
      UserAccessProfile.resolveFeatureAccess(
        role: currentUserRole,
        rawFeatureAccessJson: currentFeatureAccessJson,
      );

  static List<String> get currentAllowedServiceIds =>
      UserAccessProfile.resolveAllowedServiceIds(
        role: currentUserRole,
        rawAllowedServiceIdsJson: currentAllowedServiceIdsJson,
      );

  static List<String> get currentAllowedBranchIds =>
      UserAccessProfile.resolveAllowedBranchIds(
        role: currentUserRole,
        rawAllowedBranchIdsJson: currentAllowedBranchIdsJson,
      );

  static List<int> get currentNavigationIndices =>
      UserAccessProfile.navigationIndicesForFeatures(currentFeatureAccess);

  static bool canAccessFeature(String featureKey) {
    return currentFeatureAccess.contains(featureKey);
  }

  static bool canAccessNavigationIndex(int index) {
    return currentNavigationIndices.contains(index);
  }

  static bool canAccessServiceId(String? serviceId) {
    if (RolePermissions.normalizeRole(currentUserRole) ==
        RolePermissions.admin) {
      return true;
    }
    final cleanId = serviceId?.trim() ?? '';
    if (cleanId.isEmpty) {
      return true;
    }
    final allowedIds = currentAllowedServiceIds;
    return allowedIds.isEmpty || allowedIds.contains(cleanId);
  }

  static bool canAccessBranchId(String? branchId) {
    if (RolePermissions.normalizeRole(currentUserRole) ==
        RolePermissions.admin) {
      return true;
    }
    final cleanId = branchId?.trim() ?? '';
    if (cleanId.isEmpty) {
      return true;
    }
    final allowedIds = currentAllowedBranchIds;
    return allowedIds.isEmpty || allowedIds.contains(cleanId);
  }

  static bool get canUseProductPos =>
      currentPosMode != UserAccessProfile.posModeServices &&
      LicenseService.currentSnapshot.entitlements.canSellProducts;

  static bool get canUseServicePos =>
      currentPosMode != UserAccessProfile.posModeProducts &&
      LicenseService.currentSnapshot.entitlements.canSellServices;

  static bool get limitsServiceOrdersToAssigned =>
      currentServiceOrderScope ==
      UserAccessProfile.serviceOrderScopeAssignedOnly;

  static Future<void> signIn(Map<String, dynamic> user) async {
    await init();
    await _prefs!.setString(_keyCurrentUserId, user['id'] as String? ?? '');
    await _prefs!.setString(
      _keyCurrentUserName,
      (user['name'] as String?)?.trim().isNotEmpty == true
          ? (user['name'] as String).trim()
          : 'Unknown Cashier',
    );
    await _prefs!.setString(
      _keyCurrentUserEmail,
      (user['email'] as String?)?.trim() ?? '',
    );
    await _prefs!.setString(
      _keyCurrentUserRole,
      RolePermissions.normalizeRole(user['role'] as String?),
    );
    await _writeOptionalString(
      _keyCurrentFeatureAccessJson,
      user['feature_access_json'] as String?,
    );
    await _writeOptionalString(
      _keyCurrentAllowedServiceIdsJson,
      user['allowed_service_ids_json'] as String?,
    );
    await _writeOptionalString(
      _keyCurrentAllowedBranchIdsJson,
      user['allowed_branch_ids_json'] as String?,
    );
    await _writeOptionalString(_keyCurrentPosMode, user['pos_mode'] as String?);
    await _writeOptionalString(
      _keyCurrentServiceOrderScope,
      user['service_order_scope'] as String?,
    );
  }

  static Future<void> updateRole(String role) async {
    await init();
    await _prefs!.setString(
      _keyCurrentUserRole,
      RolePermissions.normalizeRole(role),
    );
  }

  static Future<void> updateAccess({
    String? featureAccessJson,
    String? allowedServiceIdsJson,
    String? allowedBranchIdsJson,
    String? posMode,
    String? serviceOrderScope,
  }) async {
    await init();
    await _writeOptionalString(_keyCurrentFeatureAccessJson, featureAccessJson);
    await _writeOptionalString(
      _keyCurrentAllowedServiceIdsJson,
      allowedServiceIdsJson,
    );
    await _writeOptionalString(
      _keyCurrentAllowedBranchIdsJson,
      allowedBranchIdsJson,
    );
    await _writeOptionalString(_keyCurrentPosMode, posMode);
    await _writeOptionalString(_keyCurrentServiceOrderScope, serviceOrderScope);
  }

  static Future<void> updateName(String name) async {
    await init();
    await _prefs!.setString(
      _keyCurrentUserName,
      name.trim().isEmpty ? 'Unknown Cashier' : name.trim(),
    );
  }

  static Future<void> signOut() async {
    await init();
    await _prefs!.remove(_keyCurrentUserId);
    await _prefs!.remove(_keyCurrentUserName);
    await _prefs!.remove(_keyCurrentUserEmail);
    await _prefs!.remove(_keyCurrentUserRole);
    await _prefs!.remove(_keyCurrentFeatureAccessJson);
    await _prefs!.remove(_keyCurrentAllowedServiceIdsJson);
    await _prefs!.remove(_keyCurrentAllowedBranchIdsJson);
    await _prefs!.remove(_keyCurrentPosMode);
    await _prefs!.remove(_keyCurrentServiceOrderScope);
  }

  static Future<void> _writeOptionalString(String key, String? value) async {
    final cleanValue = value?.trim() ?? '';
    if (cleanValue.isEmpty) {
      await _prefs!.remove(key);
      return;
    }
    await _prefs!.setString(key, cleanValue);
  }
}

class RolePermissions {
  static const admin = 'ADMIN';
  static const manager = 'MANAGER';
  static const cashier = 'CASHIER';

  static const allRoles = [admin, manager, cashier];

  static String normalizeRole(String? role) {
    final normalized = role?.trim().toUpperCase();
    if (normalized == admin || normalized == manager || normalized == cashier) {
      return normalized!;
    }
    return cashier;
  }

  static String label(String? role) {
    switch (normalizeRole(role)) {
      case admin:
        return 'Admin';
      case manager:
        return 'Manager';
      default:
        return 'Cashier';
    }
  }

  static List<int> navigationIndicesForRole(String? role) {
    return UserAccessProfile.navigationIndicesForFeatures(
      UserAccessProfile.defaultFeatureAccessForRole(normalizeRole(role)),
    );
  }

  static bool canAccessNavigation(String? role, int index) {
    return navigationIndicesForRole(role).contains(index);
  }

  static bool canManageUsers(String? role) {
    return normalizeRole(role) == admin;
  }

  static bool canManageOperationalSettings(String? role) {
    final normalized = normalizeRole(role);
    return normalized == admin || normalized == manager;
  }

  static bool canRefundSales(String? role) {
    final normalized = normalizeRole(role);
    return normalized == admin || normalized == manager;
  }
}

class UserAccessProfile {
  static const featurePos = 'pos';
  static const featureProducts = 'products';
  static const featureCategories = 'categories';
  static const featurePurchases = 'purchases';
  static const featureSales = 'sales';
  static const featureDashboard = 'dashboard';
  static const featureKopesha = 'kopesha';
  static const featureProfitLoss = 'profit_loss';
  static const featureReports = 'reports';
  static const featureSettings = 'settings';
  static const featureShifts = 'shifts';
  static const featureServices = 'services';
  static const featureAgent = 'agent';
  static const featureStockList = 'stock_list';
  static const featureTransfers = 'transfers';
  static const featureBranches = 'branches';
  static const featureAuditLogs = 'audit_logs';
  static const featureProactivePiki = 'proactive_piki';
  static const featureLoyalty = 'loyalty';
  static const featureGiftCards = 'gift_cards';
  static const featurePromotions = 'promotions';
  static const featureCustomRoles = 'custom_roles';
  static const featureSerialTracking = 'serial_tracking';
  static const featureStocktake = 'stocktake';
  static const featureSmsCampaigns = 'sms_campaigns';
  static const featureMultiCurrency = 'multi_currency';
  static const featureWastage = 'wastage';
  static const featureRestaurantMode = 'restaurant_mode';
  static const featureAttendance = 'attendance';
  static const featureCustomerSegments = 'customer_segments';
  static const featureDelivery = 'delivery';

  static const posModeBoth = 'both';
  static const posModeProducts = 'products';
  static const posModeServices = 'services';
  static const serviceOrderScopeAllVisibleServices = 'all_visible_services';
  static const serviceOrderScopeAssignedOnly = 'assigned_only';

  static const allFeatures = [
    featurePos,
    featureProducts,
    featureCategories,
    featurePurchases,
    featureSales,
    featureDashboard,
    featureKopesha,
    featureProfitLoss,
    featureReports,
    featureSettings,
    featureShifts,
    featureServices,
    featureAgent,
    featureStockList,
    featureTransfers,
    featureBranches,
    featureAuditLogs,
    featureProactivePiki,
    featureLoyalty,
    featureGiftCards,
    featurePromotions,
    featureCustomRoles,
    featureSerialTracking,
    featureStocktake,
    featureSmsCampaigns,
    featureMultiCurrency,
    featureWastage,
    featureRestaurantMode,
    featureAttendance,
    featureCustomerSegments,
    featureDelivery,
  ];

  static const configurableFeatures = [
    featurePos,
    featureProducts,
    featureCategories,
    featurePurchases,
    featureSales,
    featureDashboard,
    featureKopesha,
    featureProfitLoss,
    featureReports,
    featureShifts,
    featureServices,
    featureAgent,
    featurePromotions,
    featureSerialTracking,
    featureStocktake,
    featureSmsCampaigns,
    featureMultiCurrency,
    featureWastage,
    featureRestaurantMode,
    featureAttendance,
    featureCustomerSegments,
    featureDelivery,
  ];

  static const _featureToNavigationIndex = <String, int>{
    featurePos: 0,
    featureProducts: 1,
    featureCategories: 2,
    featurePurchases: 3,
    featureSales: 4,
    featureDashboard: 5,
    featureKopesha: 6,
    featureProfitLoss: 7,
    featureReports: 8,
    featureSettings: 9,
    featureShifts: 10,
    featureServices: 11,
    featureAgent: 16,
    featureStockList: 12,
    featureBranches: 13,
    featureAuditLogs: 14,
    featureTransfers: 15,
    featureLoyalty: 21,
    featureGiftCards: 22,
    featurePromotions: 23,
    featureCustomRoles: 24,
    featureSerialTracking: 25,
    featureStocktake: 26,
    featureSmsCampaigns: 27,
    featureMultiCurrency: 9,
    featureWastage: 28,
    featureRestaurantMode: 29,
    featureAttendance: 30,
    featureCustomerSegments: 31,
    featureDelivery: 33,
  };

  static const _additionalNavigationFeatures = <int, String>{
    34: featureReports,
  };

  static List<String> defaultFeatureAccessForRole(String? role) {
    switch (RolePermissions.normalizeRole(role)) {
      case RolePermissions.admin:
      case RolePermissions.manager:
        return List<String>.from(allFeatures);
      default:
        return const [
          featurePos,
          featureSales,
          featureDashboard,
          featureKopesha,
          featureSettings,
          featureShifts,
          featureAgent,
        ];
    }
  }

  static List<String> resolveFeatureAccess({
    required String role,
    String? rawFeatureAccessJson,
  }) {
    final normalizedRole = RolePermissions.normalizeRole(role);
    if (normalizedRole == RolePermissions.admin) {
      return List<String>.from(allFeatures);
    }

    final parsed = _tryDecodeStringList(rawFeatureAccessJson);
    final source = parsed ?? defaultFeatureAccessForRole(role);
    final normalized = <String>[];
    for (final feature in source) {
      if (allFeatures.contains(feature) && !normalized.contains(feature)) {
        normalized.add(feature);
      }
    }
    if (!normalized.contains(featureSettings)) {
      normalized.add(featureSettings);
    }
    return normalized;
  }

  static List<String> resolveAllowedServiceIds({
    required String role,
    String? rawAllowedServiceIdsJson,
  }) {
    if (RolePermissions.normalizeRole(role) == RolePermissions.admin) {
      return const [];
    }
    return _decodeStringList(rawAllowedServiceIdsJson);
  }

  static List<String> resolveAllowedBranchIds({
    required String role,
    String? rawAllowedBranchIdsJson,
  }) {
    if (RolePermissions.normalizeRole(role) == RolePermissions.admin) {
      return const [];
    }
    return _decodeStringList(rawAllowedBranchIdsJson);
  }

  static String resolvePosMode({required String role, String? rawPosMode}) {
    if (RolePermissions.normalizeRole(role) == RolePermissions.admin) {
      return posModeBoth;
    }
    final normalized = rawPosMode?.trim().toLowerCase();
    switch (normalized) {
      case posModeProducts:
      case posModeServices:
      case posModeBoth:
        return normalized!;
      default:
        return posModeBoth;
    }
  }

  static String resolveServiceOrderScope({
    required String role,
    String? rawScope,
  }) {
    if (RolePermissions.normalizeRole(role) == RolePermissions.admin) {
      return serviceOrderScopeAllVisibleServices;
    }
    final normalized = rawScope?.trim().toLowerCase();
    switch (normalized) {
      case serviceOrderScopeAssignedOnly:
      case serviceOrderScopeAllVisibleServices:
        return normalized!;
      default:
        return serviceOrderScopeAllVisibleServices;
    }
  }

  static List<int> navigationIndicesForFeatures(List<String> featureKeys) {
    final indices = <int>[];
    for (final feature in allFeatures) {
      final index = _featureToNavigationIndex[feature];
      if (index != null && featureKeys.contains(feature)) {
        indices.add(index);
      }
    }
    return indices;
  }

  static String? featureForNavigationIndex(int index) {
    final additional = _additionalNavigationFeatures[index];
    if (additional != null) return additional;
    for (final entry in _featureToNavigationIndex.entries) {
      if (entry.value == index) {
        return entry.key;
      }
    }
    return null;
  }

  static String encodeStringList(Iterable<String> values) {
    final normalized = <String>[];
    for (final value in values) {
      final clean = value.trim();
      if (clean.isNotEmpty && !normalized.contains(clean)) {
        normalized.add(clean);
      }
    }
    return jsonEncode(normalized);
  }

  static String featureLabel(String featureKey) {
    switch (featureKey) {
      case featurePos:
        return 'POS';
      case featureProducts:
        return 'Products';
      case featureCategories:
        return 'Categories';
      case featurePurchases:
        return 'Purchases';
      case featureSales:
        return 'Sales';
      case featureDashboard:
        return 'Dashboard';
      case featureKopesha:
        return 'Kopesha';
      case featureProfitLoss:
        return 'Profit & Loss';
      case featureReports:
        return 'Reports';
      case featureSettings:
        return 'Settings';
      case featureShifts:
        return 'Shifts';
      case featureServices:
        return 'Services';
      case featureAgent:
        return 'Piki AI';
      case featureStockList:
        return 'Stock List';
      case featureTransfers:
        return 'Transfers';
      case featureBranches:
        return 'Branches';
      case featureAuditLogs:
        return 'Audit Logs';
      case featureProactivePiki:
        return 'Proactive Piki';
      case featureLoyalty:
        return 'Loyalty';
      case featureGiftCards:
        return 'Gift Cards';
      case featurePromotions:
        return 'Promotions';
      case featureCustomRoles:
        return 'Custom Roles';
      case featureSerialTracking:
        return 'Serial Tracking';
      case featureStocktake:
        return 'Stocktake';
      case featureSmsCampaigns:
        return 'SMS Campaigns';
      case featureMultiCurrency:
        return 'Multi-Currency';
      case featureWastage:
        return 'Wastage';
      case featureRestaurantMode:
        return 'Restaurant';
      case featureAttendance:
        return 'Attendance';
      case featureCustomerSegments:
        return 'Customer Segments';
      case featureDelivery:
        return 'Delivery';
      default:
        return featureKey;
    }
  }

  static String serviceOrderScopeLabel(String scope) {
    switch (scope) {
      case serviceOrderScopeAssignedOnly:
        return 'Assigned only';
      default:
        return 'All allowed services';
    }
  }

  static List<String> _decodeStringList(String? rawJson) {
    final raw = rawJson?.trim() ?? '';
    if (raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final values = <String>[];
      for (final value in decoded) {
        final clean = value?.toString().trim() ?? '';
        if (clean.isNotEmpty && !values.contains(clean)) {
          values.add(clean);
        }
      }
      return values;
    } catch (_) {
      return const [];
    }
  }

  static List<String>? _tryDecodeStringList(String? rawJson) {
    final raw = rawJson?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      final values = <String>[];
      for (final value in decoded) {
        final clean = value?.toString().trim() ?? '';
        if (clean.isNotEmpty && !values.contains(clean)) {
          values.add(clean);
        }
      }
      return values;
    } catch (_) {
      return null;
    }
  }
}
