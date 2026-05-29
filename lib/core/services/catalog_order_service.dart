import 'package:dio/dio.dart';

import 'license_service.dart';
import 'sync_settings_service.dart';

class CatalogOrderItem {
  final String id;
  final String productName;
  final String variantName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  const CatalogOrderItem({
    required this.id,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  String get label =>
      variantName.trim().isEmpty ? productName : '$productName - $variantName';

  factory CatalogOrderItem.fromJson(Map<String, dynamic> json) {
    return CatalogOrderItem(
      id: json['id']?.toString() ?? '',
      productName: json['productName']?.toString() ?? 'Product',
      variantName: json['variantName']?.toString() ?? '',
      quantity: _readDouble(json['quantity']),
      unitPrice: _readDouble(json['unitPrice']),
      lineTotal: _readDouble(json['lineTotal']),
    );
  }
}

class CatalogOrder {
  final String id;
  final String orderNumber;
  final String customerName;
  final String phone;
  final String deliveryAddress;
  final String note;
  final String status;
  final double subtotal;
  final double itemCount;
  final DateTime? createdAt;
  final List<CatalogOrderItem> items;

  const CatalogOrder({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.phone,
    required this.deliveryAddress,
    required this.note,
    required this.status,
    required this.subtotal,
    required this.itemCount,
    required this.createdAt,
    required this.items,
  });

  factory CatalogOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return CatalogOrder(
      id: json['id']?.toString() ?? '',
      orderNumber: json['orderNumber']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? 'Customer',
      phone: json['phone']?.toString() ?? '',
      deliveryAddress: json['deliveryAddress']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      subtotal: _readDouble(json['subtotal']),
      itemCount: _readDouble(json['itemCount']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => CatalogOrderItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class CatalogOrderService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<List<CatalogOrder>> fetchOrders({
    String status = 'pending',
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/orders'),
      queryParameters: {'deviceId': deviceId, 'status': status},
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'];
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map>()
        .map((item) => CatalogOrder.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<CatalogOrder> updateStatus({
    required String orderId,
    required String status,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.put<Map<String, dynamic>>(
      _url('catalog/orders/$orderId/status'),
      queryParameters: {'deviceId': deviceId},
      data: {'status': status},
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return CatalogOrder.fromJson(data);
  }

  static String _url(String path) {
    final base = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return '$base/$path';
  }

  static Future<Map<String, String>> _authHeaders() async {
    await LicenseService.init();
    final token = LicenseService.currentSnapshot.accessToken;
    if (token == null || token.trim().isEmpty) {
      throw Exception('Cloud sync is not activated.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  static Map<String, dynamic> _requireOk(
    Response<Map<String, dynamic>> response,
  ) {
    final body = response.data ?? const <String, dynamic>{};
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300 &&
        body['ok'] == true) {
      return body;
    }
    throw Exception(
      body['error']?.toString() ?? 'Catalog order request failed',
    );
  }
}

double _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
