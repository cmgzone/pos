import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/preferences_recovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late File preferencesFile;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'pos-prefs-recovery-',
    );
    preferencesFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}shared_preferences.json',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('repairs zero-filled desktop shared preferences files', () async {
    await preferencesFile.writeAsBytes(List<int>.filled(64, 0), flush: true);

    await PreferencesRecoveryService.repairIfNeeded(
      appSupportPathOverride: tempDirectory.path,
    );

    expect(await preferencesFile.readAsString(), '{}');

    final backups = tempDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('.corrupted_'))
        .toList();
    expect(backups, hasLength(1));
    expect(await backups.single.readAsBytes(), List<int>.filled(64, 0));
  });

  test('keeps valid shared preferences files untouched', () async {
    const originalContent = '{"flutter.current_user_id":"user-1"}';
    await preferencesFile.writeAsString(originalContent, flush: true);

    await PreferencesRecoveryService.repairIfNeeded(
      appSupportPathOverride: tempDirectory.path,
    );

    expect(await preferencesFile.readAsString(), originalContent);

    final backups = tempDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('.corrupted_'))
        .toList();
    expect(backups, isEmpty);
  });
}
