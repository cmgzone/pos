import 'dart:convert';

import 'package:dio/dio.dart';

import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class BusinessEtimsSettings {
  final bool isActive;
  final bool autoSubmit;
  final bool platformActive;
  final String providerName;
  final String taxpayerPin;
  final String vatNumber;
  final String solutionType;
  final String branchCode;
  final String deviceSerial;

  const BusinessEtimsSettings({
    required this.isActive,
    required this.autoSubmit,
    required this.platformActive,
    required this.providerName,
    required this.taxpayerPin,
    required this.vatNumber,
    required this.solutionType,
    required this.branchCode,
    required this.deviceSerial,
  });

  factory BusinessEtimsSettings.fromJson(Map<String, dynamic> json) {
    return BusinessEtimsSettings(
      isActive: json['isActive'] == true,
      autoSubmit: json['autoSubmit'] != false,
      platformActive: json['platformActive'] == true,
      providerName: json['providerName']?.toString() ?? 'KRA eTIMS',
      taxpayerPin: json['taxpayerPin']?.toString() ?? '',
      vatNumber: json['vatNumber']?.toString() ?? '',
      solutionType: json['solutionType']?.toString() ?? 'OSCU',
      branchCode: json['branchCode']?.toString() ?? '',
      deviceSerial: json['deviceSerial']?.toString() ?? '',
    );
  }

  static BusinessEtimsSettings get local => BusinessEtimsSettings(
    isActive: ShopSettings.etimsEnabled,
    autoSubmit: ShopSettings.etimsAutoSubmit,
    platformActive: false,
    providerName: 'KRA eTIMS',
    taxpayerPin: ShopSettings.kraPin,
    vatNumber: ShopSettings.etimsVatNumber,
    solutionType: ShopSettings.etimsSolutionType,
    branchCode: ShopSettings.etimsBranchCode,
    deviceSerial: ShopSettings.etimsDeviceSerial,
  );
}

class EtimsSubmissionResult {
  final String id;
  final String saleId;
  final String status;
  final String? invoiceNumber;
  final String? controlUnitInvoiceNumber;
  final String? controlUnitSerial;
  final String? verificationUrl;
  final String? qrCode;
  final String? submittedAt;
  final String? errorMessage;

  const EtimsSubmissionResult({
    required this.id,
    required this.saleId,
    required this.status,
    this.invoiceNumber,
    this.controlUnitInvoiceNumber,
    this.controlUnitSerial,
    this.verificationUrl,
    this.qrCode,
    this.submittedAt,
    this.errorMessage,
  });

  factory EtimsSubmissionResult.fromJson(Map<String, dynamic> json) {
    return EtimsSubmissionResult(
      id: json['id']?.toString() ?? '',
      saleId: json['saleId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'failed',
      invoiceNumber: json['invoiceNumber']?.toString(),
      controlUnitInvoiceNumber: json['controlUnitInvoiceNumber']?.toString(),
      controlUnitSerial: json['controlUnitSerial']?.toString(),
      verificationUrl: json['verificationUrl']?.toString(),
      qrCode: json['qrCode']?.toString(),
      submittedAt: json['submittedAt']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}

class EtimsService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<BusinessEtimsSettings> fetchSettings() async {
    await ShopSettings.init();
    try {
      final headers = await _authHeaders();
      final deviceId = await SyncSettingsService.getOrCreateDeviceId();
      final response = await _dio.get<Map<String, dynamic>>(
        _url('business/etims-settings'),
        queryParameters: {'deviceId': deviceId},
        options: Options(headers: headers),
      );
      final data = _requireOk(response)['data'] as Map<String, dynamic>;
      final settings = BusinessEtimsSettings.fromJson(data);
      await _storeLocal(settings);
      return settings;
    } catch (_) {
      return BusinessEtimsSettings.local;
    }
  }

  static Future<BusinessEtimsSettings> saveSettings({
    required bool isActive,
    required bool autoSubmit,
    required String taxpayerPin,
    required String vatNumber,
    required String solutionType,
    required String branchCode,
    required String deviceSerial,
  }) async {
    await ShopSettings.init();
    await ShopSettings.setEtimsEnabled(isActive);
    await ShopSettings.setEtimsAutoSubmit(autoSubmit);
    await ShopSettings.setKraPin(taxpayerPin);
    await ShopSettings.setEtimsVatNumber(vatNumber);
    await ShopSettings.setEtimsSolutionType(solutionType);
    await ShopSettings.setEtimsBranchCode(branchCode);
    await ShopSettings.setEtimsDeviceSerial(deviceSerial);

    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.put<Map<String, dynamic>>(
      _url('business/etims-settings'),
      data: {
        'deviceId': deviceId,
        'isActive': isActive,
        'autoSubmit': autoSubmit,
        'taxpayerPin': taxpayerPin.trim().toUpperCase(),
        'vatNumber': vatNumber.trim(),
        'solutionType': solutionType.trim().toUpperCase(),
        'branchCode': branchCode.trim(),
        'deviceSerial': deviceSerial.trim(),
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    final settings = BusinessEtimsSettings.fromJson(data);
    await _storeLocal(settings);
    return settings;
  }

  static Future<EtimsSubmissionResult?> submitSaleIfEnabled(
    String saleId,
  ) async {
    await ShopSettings.init();
    if (!ShopSettings.etimsEnabled || !ShopSettings.etimsAutoSubmit) {
      return null;
    }
    return submitSale(saleId);
  }

  static Future<EtimsSubmissionResult> submitSale(String saleId) async {
    final sale = await DatabaseService.queryById('sales', saleId);
    if (sale == null) {
      throw Exception('Sale was not found for eTIMS submission.');
    }
    final items = await _loadSaleItems(saleId);

    try {
      final headers = await _authHeaders();
      final deviceId = await SyncSettingsService.getOrCreateDeviceId();
      final response = await _dio.post<Map<String, dynamic>>(
        _url('etims/submit-sale'),
        data: {
          'deviceId': deviceId,
          'userId': SessionService.currentUserId,
          'sale': _salePayload(sale),
          'items': items,
        },
        options: Options(headers: headers),
      );
      final data = _requireOk(response)['data'] as Map<String, dynamic>;
      final result = EtimsSubmissionResult.fromJson(data);
      await _applySubmissionResult(saleId, result, responseJson: data);
      return result;
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      final result = EtimsSubmissionResult(
        id: '',
        saleId: saleId,
        status: 'pending_sync',
        errorMessage: message,
      );
      await _applySubmissionResult(saleId, result);
      return result;
    }
  }

  static Future<void> _applySubmissionResult(
    String saleId,
    EtimsSubmissionResult result, {
    Map<String, dynamic>? responseJson,
  }) async {
    await DatabaseService.update('sales', {
      'etims_status': result.status,
      'etims_invoice_number': result.invoiceNumber,
      'etims_control_unit_invoice_number': result.controlUnitInvoiceNumber,
      'etims_control_unit_serial': result.controlUnitSerial,
      'etims_verification_url': result.verificationUrl,
      'etims_qr_code': result.qrCode,
      'etims_submitted_at': result.submittedAt,
      'etims_error': result.errorMessage,
      'etims_response_json': responseJson == null
          ? null
          : jsonEncode(responseJson),
    }, saleId);
  }

  static Map<String, dynamic> _salePayload(Map<String, dynamic> sale) {
    return {
      'id': sale['id'],
      'branchId': sale['branch_id'],
      'totalAmount': sale['total_amount'],
      'tax': sale['tax'],
      'discount': sale['discount'],
      'paymentType': sale['payment_type'],
      'customerId': sale['customer_id'],
      'customerName': sale['customer_name'],
      'paymentReference': sale['payment_reference'],
      'refundForSaleId': sale['refund_for_sale_id'],
      'createdAt': sale['created_at'],
      'currency': ShopSettings.currency,
    };
  }

  static Future<List<Map<String, dynamic>>> _loadSaleItems(
    String saleId,
  ) async {
    final productItems = await DatabaseService.rawQuery(
      '''
      SELECT
        si.product_id,
        CASE
          WHEN si.variant_id IS NOT NULL THEN p.name || ' - ' || COALESCE(pv.name, '')
          ELSE p.name
        END as product_name,
        si.quantity,
        si.unit_price,
        si.unit,
        si.quantity * si.unit_price as line_total
      FROM sale_items si
      LEFT JOIN products p ON p.id = si.product_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      WHERE si.sale_id = ? AND si.deleted_at IS NULL
      ORDER BY si.created_at ASC
      ''',
      [saleId],
    );
    final serviceItems = await DatabaseService.rawQuery(
      '''
      SELECT
        service_id as product_id,
        service_name as product_name,
        quantity,
        unit_price,
        'service' as unit,
        quantity * unit_price as line_total
      FROM service_sale_items
      WHERE sale_id = ? AND deleted_at IS NULL
      ORDER BY created_at ASC
      ''',
      [saleId],
    );
    return [...productItems, ...serviceItems];
  }

  static Future<void> _storeLocal(BusinessEtimsSettings settings) async {
    await ShopSettings.setEtimsEnabled(settings.isActive);
    await ShopSettings.setEtimsAutoSubmit(settings.autoSubmit);
    await ShopSettings.setKraPin(settings.taxpayerPin);
    await ShopSettings.setEtimsVatNumber(settings.vatNumber);
    await ShopSettings.setEtimsSolutionType(settings.solutionType);
    await ShopSettings.setEtimsBranchCode(settings.branchCode);
    await ShopSettings.setEtimsDeviceSerial(settings.deviceSerial);
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
      throw Exception('Cloud KRA/eTIMS is not activated.');
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
    throw Exception(body['error']?.toString() ?? 'KRA/eTIMS request failed');
  }
}
