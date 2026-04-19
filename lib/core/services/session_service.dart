import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static SharedPreferences? _prefs;

  static const _keyCurrentUserId = 'current_user_id';
  static const _keyCurrentUserName = 'current_user_name';
  static const _keyCurrentUserEmail = 'current_user_email';
  static const _keyCurrentUserRole = 'current_user_role';

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
  }

  static Future<void> updateRole(String role) async {
    await init();
    await _prefs!.setString(
      _keyCurrentUserRole,
      RolePermissions.normalizeRole(role),
    );
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
    switch (normalizeRole(role)) {
      case admin:
        return const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
      case manager:
        return const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
      default:
        return const [0, 4, 5, 6, 9];
    }
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
