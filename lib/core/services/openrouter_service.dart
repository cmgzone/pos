import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';
import '../../features/products/data/product_repository.dart';
import '../../features/purchases/data/purchase_repository.dart';
import '../../features/reports/data/expense_repository.dart';
import '../../features/reports/data/report_repository.dart';
import '../../features/sales/data/sale_repository.dart';
import '../../features/shifts/data/shift_repository.dart';

/// Connects the Piki AI agent to the backend AI proxy (OpenRouter).
/// The API key never touches the client — the backend handles it.
class OpenRouterService {
  static const _keyCachedAiEnabled = 'ai_enabled';
  static const _keyCachedAiModel = 'ai_model';
  static const _timeout = Duration(seconds: 30);

  static SharedPreferences? _prefs;
  static bool? _cachedEnabled;
  static String? _cachedModel;

  // ─── Initialization ───────────────────────────────────────────────────

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _cachedEnabled = _prefs?.getBool(_keyCachedAiEnabled);
    _cachedModel = _prefs?.getString(_keyCachedAiModel);
  }

  /// Whether AI is enabled (cached from last server fetch).
  static bool get isEnabled => _cachedEnabled ?? false;

  /// Current model name (cached from last server fetch).
  static String get modelName => _cachedModel ?? 'openai/gpt-4o-mini';

  // ─── Fetch AI config from backend ─────────────────────────────────────

  /// Fetches the current AI config from the server and caches it locally.
  /// Returns true if AI is enabled, false otherwise.
  static Future<bool> refreshConfig() async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      _cachedEnabled = false;
      return false;
    }

    try {
      final deviceId = await SyncSettingsService.getOrCreateDeviceId();
      final license = await _ensureAccess(backendUrl, deviceId);
      final client = http.Client();

      try {
        final response = await client
            .get(
              _buildUri(backendUrl, 'ai/config', {'deviceId': deviceId}),
              headers: _authHeaders(license),
            )
            .timeout(_timeout);

        if (response.statusCode != 200) {
          return _cachedEnabled ?? false;
        }

        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final enabled = body['aiEnabled'] == true;
        final model = body['aiModel'] as String? ?? 'openai/gpt-4o-mini';

        _cachedEnabled = enabled;
        _cachedModel = model;
        await _prefs?.setBool(_keyCachedAiEnabled, enabled);
        await _prefs?.setString(_keyCachedAiModel, model);

        return enabled;
      } finally {
        client.close();
      }
    } catch (_) {
      return _cachedEnabled ?? false;
    }
  }

  // ─── Send chat message ────────────────────────────────────────────────

  /// Sends a chat message through the backend AI proxy.
  /// Returns the AI response text, or throws on failure.
  static Future<String> chat({
    required List<Map<String, String>> messages,
    bool includeBusinessContext = true,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);

    // Build system prompt with business context
    String systemPrompt = _buildSystemPrompt();
    if (includeBusinessContext) {
      final contextData = await _gatherBusinessContext();
      systemPrompt += '\n\n$contextData';
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            _buildUri(backendUrl, 'ai/chat'),
            headers: {
              ..._authHeaders(license),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'messages': messages,
              'systemPrompt': systemPrompt,
            }),
          )
          .timeout(const Duration(seconds: 45));

      final body = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 429) {
        throw Exception(
          body['error'] as String? ?? 'AI rate limit reached. Try again later.',
        );
      }

      if (response.statusCode == 403) {
        _cachedEnabled = false;
        await _prefs?.setBool(_keyCachedAiEnabled, false);
        throw Exception('AI is not enabled by the platform administrator.');
      }

      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(
          body['error'] as String? ?? 'AI request failed (${response.statusCode})',
        );
      }

      return body['content'] as String? ?? '';
    } finally {
      client.close();
    }
  }

  /// Ask the model to choose which local tools should run next.
  static Future<Map<String, dynamic>> planToolUse({
    required String userMessage,
    required List<Map<String, String>> conversation,
    required String toolCatalog,
    required String memorySummary,
    bool includeBusinessContext = true,
  }) async {
    final response = await chat(
      messages: [
        {
          'role': 'user',
          'content': '''
Plan the next grounded POS response.

Return JSON only. Do not wrap it in markdown.

JSON schema:
{
  "mode": "tool" | "answer",
  "summary": "short internal plan",
  "answer": "only when no tools are needed",
  "tool_calls": [
    {
      "tool": "tool_name",
      "reason": "why it is needed",
      "arguments": {
        "daysRange": 1,
        "limit": 10,
        "query": "optional search text"
      }
    }
  ]
}

Rules:
- Prefer tool calls for requests involving inventory, sales, debtors, expenses, purchases, products, or follow-up actions on earlier results.
- Use at most 3 tool calls.
- Reuse follow-up memory when the user refers to "that", "those", "last result", "create a draft", or "show supplier history".
- Use "answer" mode only for simple guidance or when no business data lookup is needed.
- Never invent tool names outside the catalog.

AVAILABLE TOOLS
$toolCatalog

FOLLOW-UP MEMORY
$memorySummary

RECENT CONVERSATION
${conversation.map((entry) => '- ${entry['role']}: ${entry['content']}').join('\n')}

LATEST USER MESSAGE
$userMessage
''',
        },
      ],
      includeBusinessContext: includeBusinessContext,
    );
    return _extractJsonObject(response);
  }

  // ─── System prompt builder ────────────────────────────────────────────

  static String _buildSystemPrompt() {
    final shopName = ShopSettings.shopName;
    final currency = ShopSettings.currency;
    final userName = SessionService.currentUserName;

    return '''You are Piki, an AI assistant for "$shopName" — a business that uses the Devis POS system.
You help with sales analysis, inventory management, customer insights, and business decisions.
The current user is "$userName". The currency is "$currency".

Guidelines:
• Be concise and actionable — this is a POS app, not a chatbot.
• Use bullet points and numbers for data.
• Format currency values with the $currency symbol.
• If asked about something you don't have data for, say so clearly.
• Never fabricate sales numbers or product data.
• You can suggest business improvements based on the data provided.''';
  }

  static Future<String> _gatherBusinessContext() async {
    try {
      final parts = <String>[];

      // Today's summary
      final todaySummary = await SaleRepository.getTodaySummary();
      final totalSales = (todaySummary['total_sales'] as num? ?? 0).toDouble();
      final totalRevenue = (todaySummary['total_revenue'] as num? ?? 0).toDouble();
      final totalProfit = (todaySummary['total_profit'] as num? ?? 0).toDouble();
      parts.add('TODAY: ${totalSales.toInt()} sales, '
          'revenue ${ShopSettings.currency}${totalRevenue.toStringAsFixed(2)}, '
          'profit ${ShopSettings.currency}${totalProfit.toStringAsFixed(2)}');

      // Stock overview
      final lowStockItems = await ProductRepository.getLowStock();
      parts.add('LOW STOCK: ${lowStockItems.length} items below reorder threshold');

      final expiryAlerts = await ProductRepository.getExpiryAlerts();
      parts.add('EXPIRY: ${expiryAlerts.length} products are expired or expiring soon');

      // Product count
      final productCount = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as cnt FROM products WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ?",
        [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
      );
      final cnt = (productCount.firstOrNull?['cnt'] as num? ?? 0).toInt();
      parts.add('INVENTORY: $cnt total products');

      final topProducts = await ReportRepository.getTopProducts(
        daysRange: 30,
        limit: 3,
      );
      if (topProducts.isNotEmpty) {
        parts.add(
          'TOP PRODUCTS 30D: ${topProducts.map((row) => '${row['name']} (${(row['total_qty_sold'] as num? ?? 0).toString()})').join(', ')}',
        );
      }

      final topDebtors = await ReportRepository.getTopDebtors(limit: 3);
      if (topDebtors.isNotEmpty) {
        parts.add(
          'TOP DEBTORS: ${topDebtors.map((row) => '${row['name']} ${ShopSettings.currency}${((row['balance'] as num? ?? 0).toDouble()).toStringAsFixed(2)}').join(', ')}',
        );
      }

      final recentExpenses = await ExpenseRepository.getRecentExpenses(
        daysRange: 30,
        limit: 5,
      );
      final expenseTotal = recentExpenses.fold<double>(
        0,
        (sum, row) => sum + (row['amount'] as num? ?? 0).toDouble(),
      );
      parts.add(
        'EXPENSES 30D: ${recentExpenses.length} records totalling ${ShopSettings.currency}${expenseTotal.toStringAsFixed(2)}',
      );

      final purchases = await PurchaseRepository.getPurchases();
      parts.add('PURCHASES: ${purchases.take(5).length} recent purchase records available');

      try {
        final closedShifts = await ShiftRepository.getClosedShifts(limit: 3);
        if (closedShifts.isNotEmpty) {
          parts.add('SHIFTS: ${closedShifts.length} recent closed shifts available');
        }
      } catch (_) {
        // Shift data is optional in some installs.
      }

      return 'CURRENT BUSINESS DATA:\n${parts.join('\n')}';
    } catch (_) {
      return '';
    }
  }

  static Map<String, dynamic> _extractJsonObject(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
    } catch (_) {
      // Fall through to brace extraction.
    }

    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final candidate = raw.substring(start, end + 1);
      final parsed = jsonDecode(candidate);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
    }
    throw const FormatException('AI planner did not return valid JSON');
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  static Future<LicenseSnapshot> _ensureAccess(
    String backendUrl,
    String deviceId,
  ) async {
    final snapshot = await LicenseService.ensureOnlineLicense(
      backendUrl: backendUrl,
      deviceId: deviceId,
      businessName: ShopSettings.shopName,
      ownerName: SessionService.currentUserName,
      ownerEmail: SessionService.currentUserEmail,
    );
    if (!snapshot.hasBinding || snapshot.accessToken == null) {
      throw Exception('Cloud subscription not activated.');
    }
    return snapshot;
  }

  static Map<String, String> _authHeaders(LicenseSnapshot snapshot) {
    final accessToken = snapshot.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      return const <String, String>{};
    }
    return {'Authorization': 'Bearer $accessToken'};
  }

  static Uri _buildUri(
    String backendUrl,
    String path, [
    Map<String, String>? queryParameters,
  ]) {
    return Uri.parse('$backendUrl/$path')
        .replace(queryParameters: queryParameters);
  }
}
