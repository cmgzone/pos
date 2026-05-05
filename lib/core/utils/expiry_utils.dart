import 'package:intl/intl.dart';

enum ExpiryStatus { unknown, ok, expiringSoon, expired }

class ExpiryUtils {
  static const int defaultAlertDays = 30;

  static final DateFormat _storageFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _displayFormat = DateFormat('dd MMM yyyy');

  static DateTime? parse(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String? toStorageString(DateTime? value) {
    if (value == null) {
      return null;
    }
    return _storageFormat.format(_startOfDay(value));
  }

  static String format(Object? value) {
    final parsed = value is DateTime ? _startOfDay(value) : parse(value);
    if (parsed == null) {
      return 'No expiry date';
    }
    return _displayFormat.format(parsed);
  }

  static int? daysUntil(Object? value, {DateTime? referenceDate}) {
    final parsed = value is DateTime ? _startOfDay(value) : parse(value);
    if (parsed == null) {
      return null;
    }
    final today = _startOfDay(referenceDate ?? DateTime.now());
    return parsed.difference(today).inDays;
  }

  static ExpiryStatus statusFor(
    Object? value, {
    int alertBeforeDays = defaultAlertDays,
    DateTime? referenceDate,
  }) {
    final days = daysUntil(value, referenceDate: referenceDate);
    if (days == null) {
      return ExpiryStatus.unknown;
    }
    if (days < 0) {
      return ExpiryStatus.expired;
    }
    if (days <= alertBeforeDays) {
      return ExpiryStatus.expiringSoon;
    }
    return ExpiryStatus.ok;
  }

  static String statusLabel(
    Object? value, {
    int alertBeforeDays = defaultAlertDays,
    DateTime? referenceDate,
  }) {
    final status = statusFor(
      value,
      alertBeforeDays: alertBeforeDays,
      referenceDate: referenceDate,
    );
    final days = daysUntil(value, referenceDate: referenceDate);

    switch (status) {
      case ExpiryStatus.expired:
        final overdueDays = days == null ? 0 : days.abs();
        return overdueDays <= 1 ? 'Expired' : 'Expired $overdueDays days ago';
      case ExpiryStatus.expiringSoon:
        if (days == null) {
          return 'Expiring soon';
        }
        if (days == 0) {
          return 'Expires today';
        }
        if (days == 1) {
          return 'Expires tomorrow';
        }
        return 'Expires in $days days';
      case ExpiryStatus.ok:
        if (days == null) {
          return 'Fresh';
        }
        return 'Expires in $days days';
      case ExpiryStatus.unknown:
        return 'No expiry date';
    }
  }

  static DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
