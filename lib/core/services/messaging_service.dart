import 'package:dio/dio.dart';

import 'external_app_launcher.dart';
import 'license_service.dart';
import 'sync_settings_service.dart';

enum CustomerMessageChannel { whatsapp, sms, email }

class MessagingService {
  /// Cached flag — updated by fetchSettings / saveSettings.
  static bool allowApiSend = false;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<void> openManual({
    required CustomerMessageChannel channel,
    required String phoneNumber,
    required String message,
  }) async {
    if (channel == CustomerMessageChannel.email) {
      final email = phoneNumber.trim();
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('Customer email address is required.');
      }
      final uri = Uri(
        scheme: 'mailto',
        path: email,
        queryParameters: {'subject': 'Receipt from Piki POS', 'body': message},
      );
      if (await ExternalAppLauncher.launch(uri)) {
        return;
      }
      throw Exception('No email app is available to open this receipt.');
    }

    final phone = _normalizePhone(phoneNumber);
    if (phone.isEmpty) {
      throw Exception('Customer phone number is required.');
    }
    final encoded = Uri.encodeComponent(message);
    final uris = channel == CustomerMessageChannel.whatsapp
        ? [
            Uri.parse('whatsapp://send?phone=$phone&text=$encoded'),
            Uri.parse('https://wa.me/$phone?text=$encoded'),
          ]
        : [
            Uri.parse('sms:$phone?body=$encoded'),
            Uri.parse('smsto:$phone?body=$encoded'),
          ];

    if (await ExternalAppLauncher.launchFirst(uris)) {
      return;
    }
    throw Exception('No app is available to open this message.');
  }

  static Future<void> sendApi({
    required CustomerMessageChannel channel,
    required String phoneNumber,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    if (channel == CustomerMessageChannel.email) {
      throw Exception(
        'Email API sending is not configured yet. Open the email app instead.',
      );
    }
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('messages/send'),
      data: {
        'deviceId': deviceId,
        'channel': channel.name,
        'recipient': phoneNumber,
        'body': message,
        ...?(metadata == null ? null : {'metadata': metadata}),
      },
      options: Options(headers: headers),
    );
    _requireOk(response);
  }

  static Future<Map<String, dynamic>> fetchSettings() async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('business/communication-settings'),
      queryParameters: {'deviceId': deviceId},
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    allowApiSend = data['allowApiSend'] == true;
    return data;
  }

  static Future<Map<String, dynamic>> saveSettings({
    required String whatsappNumber,
    required String smsSenderId,
    required bool allowApiSend,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.put<Map<String, dynamic>>(
      _url('business/communication-settings'),
      data: {
        'deviceId': deviceId,
        'whatsappNumber': whatsappNumber.trim(),
        'smsSenderId': smsSenderId.trim(),
        'allowApiSend': allowApiSend,
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    allowApiSend = allowApiSend; // preserve the value just saved
    return data;
  }

  static Future<Map<String, dynamic>> fetchWhatsAppConnectStatus() async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('business/whatsapp-connect'),
      queryParameters: {'deviceId': deviceId},
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> completeWhatsAppConnect({
    String? code,
    String? redirectUri,
    String? wabaId,
    required String phoneNumberId,
    String? displayPhoneNumber,
    String? businessName,
    String? accessToken,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('business/whatsapp-connect/complete'),
      data: {
        'deviceId': deviceId,
        if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
        if (redirectUri != null && redirectUri.trim().isNotEmpty)
          'redirectUri': redirectUri.trim(),
        if (wabaId != null && wabaId.trim().isNotEmpty) 'wabaId': wabaId.trim(),
        'phoneNumberId': phoneNumberId.trim(),
        if (displayPhoneNumber != null && displayPhoneNumber.trim().isNotEmpty)
          'displayPhoneNumber': displayPhoneNumber.trim(),
        if (businessName != null && businessName.trim().isNotEmpty)
          'businessName': businessName.trim(),
        if (accessToken != null && accessToken.trim().isNotEmpty)
          'accessToken': accessToken.trim(),
      },
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createWhatsAppConnectSession() async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('business/whatsapp-connect/session'),
      data: {'deviceId': deviceId},
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
  }

  static Future<void> openWhatsAppBusinessSetup() async {
    final session = await createWhatsAppConnectSession();
    final connectUrl = session['connectUrl']?.toString().trim() ?? '';
    final uri = Uri.tryParse(connectUrl);
    if (uri == null || !uri.hasScheme || connectUrl.isEmpty) {
      throw Exception('WhatsApp setup link could not be created.');
    }
    if (await ExternalAppLauncher.launch(uri)) {
      return;
    }
    throw Exception('Could not open WhatsApp setup in the browser.');
  }

  static Future<Map<String, dynamic>> disconnectWhatsAppBusiness() async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.delete<Map<String, dynamic>>(
      _url('business/whatsapp-connect'),
      queryParameters: {'deviceId': deviceId},
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
  }

  static String receiptMessage({
    required String customerName,
    required String saleId,
    required String amount,
    String? kopeshaBalance,
    String? loyaltyPointsEarned,
    String? loyaltyPointsBalance,
    String? giftCardBalance,
    String? earnedGiftCardCode,
    String? earnedGiftCardAmount,
    String? earnedGiftCardExpiresAt,
  }) {
    final lines = <String>[
      'Hello $customerName, your receipt $saleId for $amount is ready. Thank you.',
    ];
    if (kopeshaBalance != null && kopeshaBalance.trim().isNotEmpty) {
      lines.add('Kopesha balance: $kopeshaBalance.');
    }
    if (loyaltyPointsEarned != null && loyaltyPointsEarned.trim().isNotEmpty) {
      lines.add('Loyalty earned: $loyaltyPointsEarned.');
    }
    if (loyaltyPointsBalance != null &&
        loyaltyPointsBalance.trim().isNotEmpty) {
      lines.add('Loyalty balance: $loyaltyPointsBalance.');
    }
    if (giftCardBalance != null && giftCardBalance.trim().isNotEmpty) {
      lines.add('Gift card balance: $giftCardBalance.');
    }
    if (earnedGiftCardCode != null &&
        earnedGiftCardCode.trim().isNotEmpty &&
        earnedGiftCardAmount != null &&
        earnedGiftCardAmount.trim().isNotEmpty) {
      lines.add(
        'You earned a gift card: $earnedGiftCardAmount. Code: $earnedGiftCardCode.',
      );
      if (earnedGiftCardExpiresAt != null &&
          earnedGiftCardExpiresAt.trim().isNotEmpty) {
        lines.add('Gift card expires: $earnedGiftCardExpiresAt.');
      }
      lines.add('Show this code at checkout.');
    }
    return lines.join('\n');
  }

  static String giftCardRewardMessage({
    required String customerName,
    required String code,
    required String amount,
    String? expiresAt,
    int? pointsSpent,
  }) {
    final lines = <String>[
      'Hi $customerName, congratulations. You earned a $amount Piki gift card.',
      'Code: $code',
      if (pointsSpent != null && pointsSpent > 0)
        'Reward used: $pointsSpent loyalty points.',
      if (expiresAt != null && expiresAt.trim().isNotEmpty)
        'Expires: $expiresAt',
      'Show this code at checkout. Keep it safe.',
    ];
    return lines.join('\n');
  }

  static String balanceReminder({
    required String customerName,
    required String balance,
    String? dueDate,
  }) {
    final due = dueDate == null || dueDate.trim().isEmpty
        ? ''
        : ' Due date: $dueDate.';
    return 'Hello $customerName, this is a reminder that your Kopesha balance is $balance.$due';
  }

  static String _normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('0') && digits.length == 10) {
      return '254${digits.substring(1)}';
    }
    return digits;
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
      throw Exception('Cloud messaging is not activated.');
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
    throw Exception(body['error']?.toString() ?? 'Message request failed');
  }
}
