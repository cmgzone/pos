import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_service.dart';
import 'shop_settings.dart';

class CashDrawerOpenResult {
  final bool success;
  final String message;

  const CashDrawerOpenResult({required this.success, required this.message});
}

class CashDrawerService {
  static final RegExp _portPattern = RegExp(
    r'^(LPT|COM)\d+:$',
    caseSensitive: false,
  );

  static bool get isSupportedPlatform => Platform.isWindows;

  static bool get isReady =>
      isSupportedPlatform &&
      ShopSettings.cashDrawerEnabled &&
      ShopSettings.cashDrawerPrinterPath.trim().isNotEmpty;

  static bool get canManualOpen => RolePermissions.canManageOperationalSettings(
    SessionService.currentUserRole,
  );

  static Future<CashDrawerOpenResult> openAfterCashSale() {
    return _open(requireManager: false, reason: 'cash_sale');
  }

  static Future<CashDrawerOpenResult> testOpen() {
    return _open(requireManager: true, reason: 'settings_test');
  }

  static Future<CashDrawerOpenResult> _open({
    required bool requireManager,
    required String reason,
  }) async {
    if (!isSupportedPlatform) {
      return const CashDrawerOpenResult(
        success: false,
        message: 'Cash drawer opening is only supported on Windows.',
      );
    }
    if (!ShopSettings.cashDrawerEnabled) {
      return const CashDrawerOpenResult(
        success: false,
        message: 'Cash drawer opening is disabled in Settings.',
      );
    }
    if (requireManager && !canManualOpen) {
      return const CashDrawerOpenResult(
        success: false,
        message: 'Only a manager or admin can test-open the cash drawer.',
      );
    }

    final printerPath = ShopSettings.cashDrawerPrinterPath.trim();
    final validationError = _validatePrinterPath(printerPath);
    if (validationError != null) {
      return CashDrawerOpenResult(success: false, message: validationError);
    }

    File? tempFile;
    try {
      tempFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}mimipos_drawer_${DateTime.now().microsecondsSinceEpoch}.bin',
      );
      await tempFile.writeAsBytes(
        Uint8List.fromList(const [0x1B, 0x70, 0x00, 0x19, 0xFA]),
        flush: true,
      );

      final result = await Process.run('cmd', [
        '/c',
        'copy /b "${tempFile.path}" "$printerPath"',
      ], runInShell: false);
      if (result.exitCode == 0) {
        debugPrint('Cash drawer opened for $reason.');
        return const CashDrawerOpenResult(
          success: true,
          message: 'Cash drawer opened.',
        );
      }

      final error = result.stderr.toString().trim();
      final output = result.stdout.toString().trim();
      return CashDrawerOpenResult(
        success: false,
        message: error.isNotEmpty
            ? error
            : output.isNotEmpty
            ? output
            : 'Windows could not send the drawer command.',
      );
    } catch (error) {
      return CashDrawerOpenResult(
        success: false,
        message: 'Cash drawer could not open: $error',
      );
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  static String? _validatePrinterPath(String value) {
    if (value.isEmpty) {
      return 'Add the printer share or port path in Settings first.';
    }
    if (value.contains(RegExp(r'["&|<>^]'))) {
      return 'Printer path contains unsafe characters.';
    }
    if (value.startsWith(r'\\') || _portPattern.hasMatch(value)) {
      return null;
    }
    return r'Use a Windows printer share like \\localhost\ReceiptPrinter or a port like LPT1:.';
  }
}
