import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/features/training/application/training_controller.dart';
import 'package:pos_app/features/training/data/training_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LicenseService.init();
    await SessionService.init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await SessionService.signOut();
  });

  test('training modules follow the signed-in feature access', () async {
    final controller = TrainingController(
      progressService: TrainingProgressService(),
    );
    addTearDown(controller.dispose);

    await SessionService.signIn({
      'id': 'manager-1',
      'name': 'Manager Jane',
      'email': 'jane@example.com',
      'role': RolePermissions.manager,
      'feature_access_json': UserAccessProfile.encodeStringList([
        UserAccessProfile.featurePos,
        UserAccessProfile.featureSales,
        UserAccessProfile.featureSettings,
      ]),
    });
    await controller.ensureLoadedForCurrentUser();

    final moduleIds = controller.availableModules
        .map((module) => module.id)
        .toList(growable: false);

    expect(moduleIds, containsAll(['quick-start', 'pos', 'sales', 'settings']));
    expect(moduleIds, isNot(contains('products')));
    expect(moduleIds, isNot(contains('categories')));
    expect(moduleIds, isNot(contains('purchases')));
    expect(moduleIds, isNot(contains('reports')));

    final quickStart = controller.availableModules.firstWhere(
      (module) => module.id == 'quick-start',
    );
    expect(
      quickStart.steps.map((step) => step.id),
      isNot(contains('quick-start.dashboard')),
    );
  });
}
