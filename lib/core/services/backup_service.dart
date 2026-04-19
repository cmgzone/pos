import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'database_service.dart';

class BackupService {
  static const _backupFolderName = 'backups';

  static Future<Directory> _getBackupDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/$_backupFolderName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<String> createBackup({
    String filePrefix = 'velora_pos_backup',
  }) async {
    final backupDirectory = await _getBackupDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final backupPath = '${backupDirectory.path}/${filePrefix}_$timestamp.db';
    final escapedBackupPath = backupPath.replaceAll("'", "''");

    await DatabaseService.db.execute('PRAGMA wal_checkpoint(FULL)');
    await DatabaseService.db.execute("VACUUM INTO '$escapedBackupPath'");

    return backupPath;
  }

  static String buildBackupFileName({String filePrefix = 'velora_pos_backup'}) {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${filePrefix}_$timestamp.db';
  }

  static Future<String> exportBackup(String targetPath) async {
    var normalizedTargetPath = targetPath.trim();
    if (normalizedTargetPath.isEmpty) {
      throw Exception('Choose where to save the backup file');
    }
    if (!normalizedTargetPath.toLowerCase().endsWith('.db')) {
      normalizedTargetPath = '$normalizedTargetPath.db';
    }

    final localBackupPath = await createBackup();
    await File(localBackupPath).copy(normalizedTargetPath);
    return normalizedTargetPath;
  }

  static Future<List<Map<String, dynamic>>> listBackups() async {
    final backupDirectory = await _getBackupDirectory();
    final files = await backupDirectory
        .list()
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.db'),
        )
        .cast<File>()
        .toList();

    final backups = <Map<String, dynamic>>[];
    for (final file in files) {
      final stat = await file.stat();
      backups.add({
        'name': file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : file.path,
        'path': file.path,
        'size_bytes': stat.size,
        'modified_at': stat.modified.toIso8601String(),
      });
    }

    backups.sort((a, b) {
      final aTime =
          DateTime.tryParse(a['modified_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          DateTime.tryParse(b['modified_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return backups;
  }

  static Future<String> restoreBackup(String backupPath) async {
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw Exception('Backup file not found');
    }

    final safetyBackupPath = await createBackup(
      filePrefix: 'pre_restore_backup',
    );
    final databasePath = DatabaseService.databasePath;
    final databaseFile = File(databasePath);
    final walFile = File('$databasePath-wal');
    final shmFile = File('$databasePath-shm');

    await DatabaseService.close();

    if (await walFile.exists()) {
      await walFile.delete();
    }
    if (await shmFile.exists()) {
      await shmFile.delete();
    }
    if (await databaseFile.exists()) {
      await databaseFile.delete();
    }

    await backupFile.copy(databasePath);
    await DatabaseService.initialize();

    return safetyBackupPath;
  }
}
