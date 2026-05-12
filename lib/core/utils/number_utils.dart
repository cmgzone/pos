import '../services/shop_settings.dart';

class NumberUtils {
  static String formatCompact(num? val, {bool isCurrency = false}) {
    if (val == null) return isCurrency ? '${ShopSettings.currency}0' : '0';
    double v = val.toDouble();
    if (v.abs() < 1000) {
      return isCurrency
          ? '${ShopSettings.currency}${v.toStringAsFixed(2)}'
          : v.toInt().toString();
    }

    String suffix = '';
    if (v.abs() >= 1000000) {
      v = v / 1000000;
      suffix = 'M';
    } else if (v.abs() >= 1000) {
      v = v / 1000;
      suffix = 'K';
    }

    String formatted =
        v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '') + suffix;
    return isCurrency ? '${ShopSettings.currency}$formatted' : formatted;
  }
}
