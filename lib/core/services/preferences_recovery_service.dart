import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PreferencesRecoveryService {
  static const _preferencesFileName = 'shared_preferences.json';

  static Future<void> repairIfNeeded({String? appSupportPathOverride}) async {
    if (kIsWeb) {
      return;
    }

    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }

    final preferencesFile = await _resolvePreferencesFile(
      appSupportPathOverride: appSupportPathOverride,
    );
    if (!await preferencesFile.exists()) {
      return;
    }

    final bytes = await preferencesFile.readAsBytes();
    if (bytes.isEmpty || _isValidPreferencesPayload(bytes)) {
      return;
    }

    await _backupCorruptedFile(preferencesFile);
    await preferencesFile.writeAsString('{}', flush: true);
  }

  static Future<File> _resolvePreferencesFile({
    String? appSupportPathOverride,
  }) async {
    final directoryPath =
        appSupportPathOverride ?? (await getApplicationSupportDirectory()).path;
    return File('$directoryPath${Platform.pathSeparator}$_preferencesFileName');
  }

  static bool _isValidPreferencesPayload(List<int> bytes) {
    try {
      final content = utf8.decode(bytes);
      if (content.isEmpty) {
        return true;
      }

      return jsonDecode(content) is Map;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _backupCorruptedFile(File preferencesFile) async {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '_',
    );
    final backupPath = '${preferencesFile.path}.corrupted_$timestamp.bak';
    try {
      await preferencesFile.copy(backupPath);
    } catch (_) {
      // If the backup fails we still prefer resetting the broken file so the
      // app can recover and launch.
    }
  }
}
