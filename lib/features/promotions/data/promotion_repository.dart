import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../sales/data/cart_provider.dart';

const _uuid = Uuid();

class PromotionRuleDraft {
  final String ruleType;
  final String? productId;
  final String? categoryId;
  final double minQuantity;
  final double freeQuantity;
  final double bundleQuantity;
  final double minSubtotal;
  final Map<String, dynamic>? ruleJson;

  const PromotionRuleDraft({
    this.ruleType = 'cart',
    this.productId,
    this.categoryId,
    this.minQuantity = 0,
    this.freeQuantity = 0,
    this.bundleQuantity = 0,
    this.minSubtotal = 0,
    this.ruleJson,
  });

  Map<String, dynamic> toRow({required String promotionId, String? id}) {
    final now = DateTime.now().toIso8601String();
    return {
      'id': id ?? _uuid.v4(),
      'branch_id': DatabaseService.currentBranchId,
      'promotion_id': promotionId,
      'rule_type': ruleType,
      'product_id': _clean(productId),
      'category_id': _clean(categoryId),
      'min_quantity': minQuantity,
      'free_quantity': freeQuantity,
      'bundle_quantity': bundleQuantity,
      'min_subtotal': minSubtotal,
      'rule_json': ruleJson == null ? null : jsonEncode(ruleJson),
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    };
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

class PromotionCartDiscount {
  final double amount;
  final List<Map<String, dynamic>> appliedPromotions;

  const PromotionCartDiscount({
    required this.amount,
    required this.appliedPromotions,
  });

  bool get hasDiscount => amount > 0.001;
}

class PromotionRepository {
  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> getAll({
    bool activeOnly = false,
  }) async {
    final where = <String>['deleted_at IS NULL', 'COALESCE(branch_id, ?) = ?'];
    final args = <dynamic>[..._currentBranchArgs];
    if (activeOnly) {
      where.add('is_active = 1');
    }
    return DatabaseService.queryAll(
      'promotions',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'priority DESC, updated_at DESC',
    );
  }

  static Future<List<Map<String, dynamic>>> getRules(String promotionId) async {
    return DatabaseService.queryAll(
      'promotion_rules',
      where:
          'promotion_id = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [promotionId, ..._currentBranchArgs],
      orderBy: 'created_at ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getActiveWithRules() async {
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM promotions
      WHERE deleted_at IS NULL
        AND is_active = 1
        AND COALESCE(branch_id, ?) = ?
        AND (starts_at IS NULL OR starts_at = '' OR starts_at <= ?)
        AND (ends_at IS NULL OR ends_at = '' OR ends_at >= ?)
      ORDER BY priority DESC, updated_at DESC
      ''',
      [..._currentBranchArgs, nowIso, nowIso],
    );
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (!_matchesDayAndTime(row, now)) continue;
      result.add({...row, 'rules': await getRules(row['id'] as String)});
    }
    return result;
  }

  static Future<String> create({
    required String name,
    required String promotionType,
    required String discountType,
    required double discountValue,
    int priority = 0,
    bool isActive = true,
    String? description,
    String? startsAt,
    String? endsAt,
    String? daysOfWeek,
    String? startTime,
    String? endTime,
    List<PromotionRuleDraft> rules = const [],
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create promotions');
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Promotion name is required.');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.insert('promotions', {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'name': cleanName,
      'description': _cleanText(description),
      'promotion_type': promotionType,
      'discount_type': discountType,
      'discount_value': discountValue < 0 ? 0 : discountValue,
      'priority': priority,
      'starts_at': _cleanText(startsAt),
      'ends_at': _cleanText(endsAt),
      'days_of_week': _cleanText(daysOfWeek),
      'start_time': _cleanText(startTime),
      'end_time': _cleanText(endTime),
      'is_active': isActive ? 1 : 0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    for (final rule in rules) {
      await DatabaseService.insert(
        'promotion_rules',
        rule.toRow(promotionId: id),
      );
    }
    await AuditLogService.log(
      action: 'create',
      entityTable: 'promotions',
      entityId: id,
    );
    return id;
  }

  static Future<void> update({
    required String id,
    required String name,
    required String promotionType,
    required String discountType,
    required double discountValue,
    int priority = 0,
    bool isActive = true,
    String? description,
    String? startsAt,
    String? endsAt,
    String? daysOfWeek,
    String? startTime,
    String? endTime,
    List<PromotionRuleDraft> rules = const [],
  }) async {
    await LicenseService.ensureWriteAccess(action: 'update promotions');
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Promotion name is required.');
    }
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('promotions', {
      'name': cleanName,
      'description': _cleanText(description),
      'promotion_type': promotionType,
      'discount_type': discountType,
      'discount_value': discountValue < 0 ? 0 : discountValue,
      'priority': priority,
      'starts_at': _cleanText(startsAt),
      'ends_at': _cleanText(endsAt),
      'days_of_week': _cleanText(daysOfWeek),
      'start_time': _cleanText(startTime),
      'end_time': _cleanText(endTime),
      'is_active': isActive ? 1 : 0,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
    final existingRules = await getRules(id);
    for (final rule in existingRules) {
      await DatabaseService.update('promotion_rules', {
        'deleted_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      }, rule['id'] as String);
    }
    for (final rule in rules) {
      await DatabaseService.insert(
        'promotion_rules',
        rule.toRow(promotionId: id),
      );
    }
    await AuditLogService.log(
      action: 'update',
      entityTable: 'promotions',
      entityId: id,
    );
  }

  static Future<void> delete(String id) async {
    await LicenseService.ensureWriteAccess(action: 'delete promotions');
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('promotions', {
      'deleted_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
    final rules = await getRules(id);
    for (final rule in rules) {
      await DatabaseService.update('promotion_rules', {
        'deleted_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      }, rule['id'] as String);
    }
    await AuditLogService.log(
      action: 'delete',
      entityTable: 'promotions',
      entityId: id,
    );
  }

  static Future<PromotionCartDiscount> evaluateCart(List<CartItem> cart) async {
    if (cart.isEmpty) {
      return const PromotionCartDiscount(amount: 0, appliedPromotions: []);
    }
    final promotions = await getActiveWithRules();
    final subtotal = cart.fold<double>(0, (sum, item) => sum + item.total);
    var totalDiscount = 0.0;
    final applied = <Map<String, dynamic>>[];
    for (final promotion in promotions) {
      final discount = _evaluatePromotion(promotion, cart, subtotal);
      if (discount <= 0) continue;
      final capped = math.min(discount, subtotal - totalDiscount);
      if (capped <= 0) break;
      totalDiscount += capped;
      applied.add({
        'id': promotion['id'],
        'name': promotion['name'],
        'amount': double.parse(capped.toStringAsFixed(2)),
      });
    }
    return PromotionCartDiscount(
      amount: double.parse(totalDiscount.toStringAsFixed(2)),
      appliedPromotions: applied,
    );
  }

  static double _evaluatePromotion(
    Map<String, dynamic> promotion,
    List<CartItem> cart,
    double subtotal,
  ) {
    final type = promotion['promotion_type']?.toString() ?? 'amount_off';
    final discountType = promotion['discount_type']?.toString() ?? 'amount';
    final discountValue = _asDouble(promotion['discount_value']);
    final rules =
        (promotion['rules'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    if (discountValue <= 0 && type != 'buy_x_get_y') return 0;

    final minSubtotal = rules.fold<double>(
      0,
      (max, rule) => math.max(max, _asDouble(rule['min_subtotal'])),
    );
    if (minSubtotal > 0 && subtotal < minSubtotal) return 0;

    switch (type) {
      case 'percent_off':
      case 'amount_off':
      case 'happy_hour':
        final eligibleSubtotal = _eligibleSubtotal(cart, rules);
        return _discountFromValue(
          eligibleSubtotal <= 0 ? subtotal : eligibleSubtotal,
          discountType,
          discountValue,
        );
      case 'bundle':
        final eligibleSubtotal = _eligibleSubtotal(cart, rules);
        if (eligibleSubtotal <= 0) return 0;
        return _discountFromValue(
          eligibleSubtotal,
          discountType,
          discountValue,
        );
      case 'buy_x_get_y':
        return _buyXGetYDiscount(cart, rules);
      default:
        return _discountFromValue(subtotal, discountType, discountValue);
    }
  }

  static double _eligibleSubtotal(
    List<CartItem> cart,
    List<Map<String, dynamic>> rules,
  ) {
    final productRules = rules
        .where((rule) => _cleanText(rule['product_id']?.toString()) != null)
        .toList();
    if (productRules.isEmpty) {
      return cart.fold<double>(0, (sum, item) => sum + item.total);
    }
    var subtotal = 0.0;
    for (final rule in productRules) {
      final productId = rule['product_id']?.toString();
      final minQuantity = _asDouble(rule['min_quantity']);
      for (final item in cart.where((item) => item.productId == productId)) {
        if (minQuantity > 0 && item.quantity < minQuantity) continue;
        subtotal += item.total;
      }
    }
    return subtotal;
  }

  static double _buyXGetYDiscount(
    List<CartItem> cart,
    List<Map<String, dynamic>> rules,
  ) {
    var discount = 0.0;
    for (final rule in rules) {
      final productId = rule['product_id']?.toString();
      if (productId == null || productId.isEmpty) continue;
      final buyQty = _asDouble(rule['min_quantity']);
      final freeQty = _asDouble(rule['free_quantity']);
      if (buyQty <= 0 || freeQty <= 0) continue;
      final groupSize = buyQty + freeQty;
      for (final item in cart.where((item) => item.productId == productId)) {
        final groups = (item.quantity / groupSize).floor();
        if (groups <= 0) continue;
        discount += groups * freeQty * item.unitPrice;
      }
    }
    return discount;
  }

  static double _discountFromValue(
    double base,
    String discountType,
    double discountValue,
  ) {
    if (base <= 0 || discountValue <= 0) return 0;
    if (discountType == 'percent') {
      return base * (discountValue.clamp(0, 100) / 100);
    }
    return math.min(discountValue, base);
  }

  static bool _matchesDayAndTime(Map<String, dynamic> row, DateTime now) {
    final days = _cleanText(row['days_of_week']?.toString());
    if (days != null) {
      final allowedDays = days
          .split(',')
          .map((value) => int.tryParse(value.trim()))
          .whereType<int>()
          .toSet();
      if (allowedDays.isNotEmpty && !allowedDays.contains(now.weekday)) {
        return false;
      }
    }
    final start = _minutes(row['start_time']?.toString());
    final end = _minutes(row['end_time']?.toString());
    if (start == null && end == null) return true;
    final current = now.hour * 60 + now.minute;
    if (start != null && end != null && end < start) {
      return current >= start || current <= end;
    }
    if (start != null && current < start) return false;
    if (end != null && current > end) return false;
    return true;
  }

  static int? _minutes(String? value) {
    final clean = _cleanText(value);
    if (clean == null) return null;
    final parts = clean.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _cleanText(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
