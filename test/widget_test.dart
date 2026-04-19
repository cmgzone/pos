import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_app/core/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionService.init();
    await SessionService.signOut();
  });

  test('SessionService stores and clears the active user', () async {
    await SessionService.signIn({
      'id': 'user-1',
      'name': 'Cashier Jane',
      'email': 'jane@example.com',
      'role': 'MANAGER',
    });

    expect(SessionService.isLoggedIn, isTrue);
    expect(SessionService.currentUserId, 'user-1');
    expect(SessionService.currentUserName, 'Cashier Jane');
    expect(SessionService.currentUserEmail, 'jane@example.com');
    expect(SessionService.currentUserRole, RolePermissions.manager);

    await SessionService.signOut();

    expect(SessionService.isLoggedIn, isFalse);
    expect(SessionService.currentUserId, isEmpty);
    expect(SessionService.currentUserRole, RolePermissions.cashier);
  });

  test('Role permissions limit cashier access and preserve admin access', () {
    expect(
      RolePermissions.navigationIndicesForRole(RolePermissions.cashier),
      const [0, 4, 5, 6, 9],
    );
    expect(RolePermissions.canRefundSales(RolePermissions.cashier), isFalse);
    expect(
      RolePermissions.canManageOperationalSettings(RolePermissions.manager),
      isTrue,
    );
    expect(RolePermissions.canManageUsers(RolePermissions.admin), isTrue);
  });
}
