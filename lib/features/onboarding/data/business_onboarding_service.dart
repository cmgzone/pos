import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/session_service.dart';

class BusinessOnboardingAnswers {
  final String businessId;
  final String businessName;
  final String? planCode;
  final String heardFrom;
  final String businessType;
  final String sellingFocus;
  final String stockTracking;
  final String creditSales;
  final String onlineSelling;
  final List<String> recommendedFeatures;
  final DateTime completedAt;

  const BusinessOnboardingAnswers({
    required this.businessId,
    required this.businessName,
    required this.planCode,
    required this.heardFrom,
    required this.businessType,
    required this.sellingFocus,
    required this.stockTracking,
    required this.creditSales,
    required this.onlineSelling,
    required this.recommendedFeatures,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'planCode': planCode,
      'heardFrom': heardFrom,
      'businessType': businessType,
      'sellingFocus': sellingFocus,
      'stockTracking': stockTracking,
      'creditSales': creditSales,
      'onlineSelling': onlineSelling,
      'recommendedFeatures': recommendedFeatures,
      'completedAt': completedAt.toUtc().toIso8601String(),
    };
  }

  factory BusinessOnboardingAnswers.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['recommendedFeatures'];
    return BusinessOnboardingAnswers(
      businessId: json['businessId']?.toString() ?? '',
      businessName: json['businessName']?.toString() ?? '',
      planCode: json['planCode']?.toString(),
      heardFrom: json['heardFrom']?.toString() ?? '',
      businessType: json['businessType']?.toString() ?? '',
      sellingFocus: json['sellingFocus']?.toString() ?? '',
      stockTracking: json['stockTracking']?.toString() ?? '',
      creditSales: json['creditSales']?.toString() ?? '',
      onlineSelling: json['onlineSelling']?.toString() ?? '',
      recommendedFeatures: rawFeatures is List
          ? rawFeatures.map((item) => item.toString()).toList()
          : const [],
      completedAt:
          DateTime.tryParse(json['completedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class BusinessOnboardingService {
  static const _latestBusinessKey = 'business_onboarding_latest_business_id';

  static Future<void> save(BusinessOnboardingAnswers answers) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForBusiness(answers.businessId);
    await prefs.setString(key, jsonEncode(answers.toJson()));
    await prefs.setString(_latestBusinessKey, answers.businessId.trim());
  }

  static Future<BusinessOnboardingAnswers?> loadForBusiness(
    String businessId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyForBusiness(businessId));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return BusinessOnboardingAnswers.fromJson(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<BusinessOnboardingAnswers?> loadLatest() async {
    final prefs = await SharedPreferences.getInstance();
    final businessId = prefs.getString(_latestBusinessKey) ?? '';
    return loadForBusiness(businessId);
  }

  static List<String> recommendedFeatures({
    required String businessType,
    required String sellingFocus,
    required String stockTracking,
    required String creditSales,
    required String onlineSelling,
  }) {
    final features = <String>[
      UserAccessProfile.featureDashboard,
      UserAccessProfile.featurePos,
      UserAccessProfile.featureSales,
      UserAccessProfile.featureSettings,
    ];

    void add(String feature) {
      if (!features.contains(feature)) {
        features.add(feature);
      }
    }

    final sellsProducts =
        sellingFocus == 'products' ||
        sellingFocus == 'both' ||
        {
          'retail',
          'grocery',
          'beauty',
          'pharmacy',
          'electronics',
          'fashion',
          'wholesale',
          'online',
          'restaurant',
        }.contains(businessType);
    final sellsServices =
        sellingFocus == 'services' ||
        sellingFocus == 'both' ||
        businessType == 'services';

    if (sellsProducts) {
      add(UserAccessProfile.featureProducts);
      add(UserAccessProfile.featureCategories);
    }
    if (sellsServices) {
      add(UserAccessProfile.featureServices);
    }
    if (stockTracking == 'yes' || stockTracking == 'later') {
      add(UserAccessProfile.featureStockList);
      add(UserAccessProfile.featurePurchases);
    }
    if (stockTracking == 'yes') {
      add(UserAccessProfile.featureTransfers);
    }
    if (creditSales == 'yes' || creditSales == 'later') {
      add(UserAccessProfile.featureKopesha);
    }
    if (onlineSelling == 'yes' || onlineSelling == 'later') {
      add(UserAccessProfile.featureProducts);
      add(UserAccessProfile.featureSales);
    }
    if (businessType == 'wholesale') {
      add(UserAccessProfile.featurePurchases);
      add(UserAccessProfile.featureReports);
    }
    if (businessType == 'restaurant') {
      add(UserAccessProfile.featureRestaurantMode);
      add(UserAccessProfile.featureShifts);
    }

    add(UserAccessProfile.featureReports);
    add(UserAccessProfile.featureAgent);
    return features;
  }

  static List<String> planSupportedFeatures({
    required Iterable<String> recommendedFeatures,
    required Iterable<String> planFeatures,
  }) {
    final planSet = planFeatures.map((feature) => feature.trim()).toSet();
    if (planSet.isEmpty) {
      return const [];
    }
    return recommendedFeatures
        .where((feature) => planSet.contains(feature))
        .toList();
  }

  static String _keyForBusiness(String businessId) {
    final normalized = businessId.trim().isEmpty ? 'local' : businessId.trim();
    return 'business_onboarding_answers_$normalized';
  }
}
