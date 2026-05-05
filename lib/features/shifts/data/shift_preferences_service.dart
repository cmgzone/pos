import 'package:shared_preferences/shared_preferences.dart';

class ShiftPreferencesService {
  static const _lastOpeningCashPrefix = 'shift.last_opening_cash.';

  static Future<double?> getLastOpeningCash(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_lastOpeningCashPrefix${_normalizeUserId(userId)}';
    final value = prefs.get(key);
    if (value is num) {
      return _roundMoney(value.toDouble());
    }
    return null;
  }

  static Future<void> saveLastOpeningCash(String userId, double amount) async {
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Opening cash cannot be negative',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      '$_lastOpeningCashPrefix${_normalizeUserId(userId)}',
      _roundMoney(amount),
    );
  }

  static String _normalizeUserId(String userId) {
    final trimmed = userId.trim();
    return trimmed.isEmpty ? 'admin' : trimmed;
  }

  static double _roundMoney(double amount) {
    return double.parse(amount.toStringAsFixed(2));
  }
}
