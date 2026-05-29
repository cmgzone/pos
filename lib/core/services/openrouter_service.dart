import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
  static const _keyCachedImageModel = 'ai_image_model';
  static const _keyCachedWebSearchEnabled = 'web_search_enabled';
  static const _timeout = Duration(seconds: 30);

  static SharedPreferences? _prefs;
  static bool? _cachedEnabled;
  static String? _cachedModel;
  static String? _cachedImageModel;
  static bool? _cachedWebSearchEnabled;

  // ─── Initialization ───────────────────────────────────────────────────

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _cachedEnabled = _prefs?.getBool(_keyCachedAiEnabled);
    _cachedModel = _prefs?.getString(_keyCachedAiModel);
    _cachedImageModel = _prefs?.getString(_keyCachedImageModel);
    _cachedWebSearchEnabled = _prefs?.getBool(_keyCachedWebSearchEnabled);
  }

  /// Whether AI is enabled (cached from last server fetch).
  static bool get isEnabled => _cachedEnabled ?? false;

  /// Current model name (cached from last server fetch).
  static String get modelName => _cachedModel ?? 'openai/gpt-4o-mini';

  /// Current product image model name (cached from last server fetch).
  static String get imageModelName =>
      _cachedImageModel ?? 'google/gemini-2.5-flash-image';

  /// Whether backend web search is configured and available to Piki.
  static bool get webSearchEnabled => _cachedWebSearchEnabled ?? false;

  // ─── Fetch AI config from backend ─────────────────────────────────────

  /// Fetches the current AI config from the server and caches it locally.
  /// Returns true if AI is enabled, false otherwise.
  static Future<bool> refreshConfig() async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      _cachedEnabled = false;
      _cachedWebSearchEnabled = false;
      await _prefs?.setBool(_keyCachedWebSearchEnabled, false);
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
        final imageModel =
            body['imageModel'] as String? ?? 'google/gemini-2.5-flash-image';
        final webSearchEnabled = body['webSearchEnabled'] == true;

        _cachedEnabled = enabled;
        _cachedModel = model;
        _cachedImageModel = imageModel;
        _cachedWebSearchEnabled = webSearchEnabled;
        await _prefs?.setBool(_keyCachedAiEnabled, enabled);
        await _prefs?.setString(_keyCachedAiModel, model);
        await _prefs?.setString(_keyCachedImageModel, imageModel);
        await _prefs?.setBool(_keyCachedWebSearchEnabled, webSearchEnabled);

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
    bool consumeQuota = false,
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
              'consumeQuota': consumeQuota,
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
          body['error'] as String? ??
              'AI request failed (${response.statusCode})',
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
    bool consumeQuota = false,
  }) async {
    final webSearchRule = webSearchEnabled
        ? '- Use web_search for current external information that is not in the POS database, such as market prices, supplier websites, regulations, tax/news context, weather, or competitor/public information.'
        : '- Web search is currently not configured. Do not call web_search; answer from local POS data or ask the user to enable web search if current external information is required.';
    final response = await chat(
      consumeQuota: consumeQuota,
      messages: [
        {
          'role': 'user',
          'content':
              '''
Plan the next grounded POS response.

Return JSON only. Do not wrap it in markdown.
The first character of your response must be { and the final character must be }.
Use valid JSON with double-quoted keys and strings. Do not add commentary before or after the JSON.

JSON schema:
{
  "mode": "tool" | "answer",
  "summary": "short internal plan",
  "answer": "only when no tools are needed",
  "suggestions": ["Follow-up question 1", "Follow-up question 2"],
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
- You are operating in a multi-step reasoning loop. You can call tools to gather data, and you will be called again with their results.
- Prefer tool calls for requests involving inventory, sales, debtors, expenses, purchases, products, or follow-up actions on earlier results.
- BEFORE creating a product or service, ensure you have the critical details. If the user only says "Add product Bread", do NOT use create_product immediately. Instead, use "answer" mode to ask for the price and initial stock.
- Use create_product ONLY when you have at least the name and price. If stock or unit is missing, you can proceed with defaults (0 stock, 'pcs' unit) but it's better to ask if the user wants to set them now.
- Use create_service ONLY when you have the name and price.
- Use create_category and create_expense_category when you have the name.
- Use create_customer and create_supplier when the user wants to add a new contact.
- Use reconcile_stock when the user provides a physical count that differs from the system (e.g., "I counted 50 milks").
- Use customer_search and supplier_search to look up contact details.
- Use enhance_product_image when the user asks to improve, enhance, clean up, upscale, or make a better product photo for an existing product. If the product has no image, explain that they need to add or capture one first.
- Use predictive_restock when the user asks what will run out, forecast demand, or predict what to reorder.
- Use anomaly_alerts when the user asks for alerts, risks, unusual activity, sales drops, or what is wrong in the business.
- Use customer_followups when the user asks for Kopesha reminders, overdue follow-ups, or customer debt messages.
- Use daily_whatsapp_report when the user asks for a WhatsApp-ready owner or daily report. This drafts the report only; do not claim it was sent.
- Use image_order_draft when the user provides an image path or URL and asks Piki to read an order/product image or draft item lines from the image.
- Use voice_cashier_help when the user asks how hands-free or voice cashier mode works.
$webSearchRule
- Do not use web_search for local POS facts like stock, sales, customers, suppliers, or expenses when a local tool can answer.
- Use add_to_cart to add an item to the POS cart when the user asks to "sell", "add", or "buy" items in Sell Mode.
- Use remove_from_cart when the cashier asks to remove, void, undo, or take an item off the cart.
- Use set_cart_quantity when the cashier asks to make a cart line an exact quantity.
- Use repeat_last_item for phrases like "same again", "one more", or "add another".
- Use clear_cart when the user asks to empty the cart.
- Use checkout when the user wants to pay, charge, or proceed to the POS screen for the items in their cart.
- Use hold_sale when the cashier wants to park, suspend, or hold the current sale.
- Use teach_alias when the cashier teaches a nickname, local term, or shortcut phrase for a product.
- For create_product, edit_product, add_variant, create_service, create_category, and create_expense_category, extract all available details (name, price, cost, stock, unit, color, etc.) from the user's message and pass them as arguments.
- Use at most 3 tool calls per step.
- Once you have enough data from the tool results, return mode="answer" and provide a rich, detailed, paragraph-style final synthesis and business recommendation. Do NOT just output raw numbers.
- Use "answer" mode to ask clarifying questions if information is missing for a write tool.
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
    return _extractPlannerResponse(response);
  }

  /// Runs a web search through the backend SerpAPI proxy.
  static Future<Map<String, dynamic>> webSearch({
    required String query,
    String? location,
    String? countryCode,
    String? language,
    int limit = 5,
    bool consumeQuota = false,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final client = http.Client();

    try {
      final response = await client
          .post(
            _buildUri(backendUrl, 'ai/web-search'),
            headers: {
              ..._authHeaders(license),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'query': query,
              if (location != null && location.trim().isNotEmpty)
                'location': location.trim(),
              if (countryCode != null && countryCode.trim().isNotEmpty)
                'countryCode': countryCode.trim(),
              if (language != null && language.trim().isNotEmpty)
                'language': language.trim(),
              'limit': limit,
              'consumeQuota': consumeQuota,
            }),
          )
          .timeout(_timeout);

      final body = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 429) {
        throw Exception(
          body['error'] as String? ?? 'AI rate limit reached. Try again later.',
        );
      }

      if (response.statusCode == 403) {
        _cachedWebSearchEnabled = false;
        await _prefs?.setBool(_keyCachedWebSearchEnabled, false);
      }

      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(
          body['error'] as String? ??
              'Web search failed (${response.statusCode})',
        );
      }

      return Map<String, dynamic>.from(body['data'] as Map? ?? {});
    } finally {
      client.close();
    }
  }

  /// Enhances a local or remote product image through the backend OpenRouter
  /// proxy and saves the generated image into the app's product image folder.
  static Future<String> enhanceProductImage({
    required String imageSource,
    String? productName,
    String? prompt,
    bool consumeQuota = true,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }

    final imageDataUrl = await _imageSourceToDataUrl(imageSource);
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final client = http.Client();

    try {
      final response = await client
          .post(
            _buildUri(backendUrl, 'ai/product-image/enhance'),
            headers: {
              ..._authHeaders(license),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'imageDataUrl': imageDataUrl,
              if (productName != null && productName.trim().isNotEmpty)
                'productName': productName.trim(),
              if (prompt != null && prompt.trim().isNotEmpty)
                'prompt': prompt.trim(),
              'consumeQuota': consumeQuota,
            }),
          )
          .timeout(const Duration(seconds: 90));

      final body = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 429) {
        throw Exception(
          body['error'] as String? ?? 'AI rate limit reached. Try again later.',
        );
      }

      if (response.statusCode == 403) {
        throw Exception(
          'AI image enhancement is not enabled by the platform administrator.',
        );
      }

      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(
          body['error'] as String? ??
              'AI image enhancement failed (${response.statusCode})',
        );
      }

      final generatedUrl =
          body['imageDataUrl'] as String? ?? body['imageUrl'] as String?;
      if (generatedUrl == null || generatedUrl.trim().isEmpty) {
        throw Exception('AI image enhancement did not return an image');
      }

      final model = body['model'] as String?;
      if (model != null && model.trim().isNotEmpty) {
        _cachedImageModel = model.trim();
        await _prefs?.setString(_keyCachedImageModel, model.trim());
      }

      return _saveGeneratedProductImage(generatedUrl.trim());
    } finally {
      client.close();
    }
  }

  // ─── System prompt builder ────────────────────────────────────────────

  /// Reads a local or remote order/product image and returns drafted item
  /// lines. The backend performs the model call so API keys stay server-side.
  static Future<Map<String, dynamic>> analyzeOrderImage({
    required String imageSource,
    String? note,
    bool consumeQuota = true,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }

    final imageDataUrl = await _imageSourceToDataUrl(imageSource);
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final client = http.Client();

    try {
      final response = await client
          .post(
            _buildUri(backendUrl, 'ai/order-image/analyze'),
            headers: {
              ..._authHeaders(license),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'imageDataUrl': imageDataUrl,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
              'consumeQuota': consumeQuota,
            }),
          )
          .timeout(const Duration(seconds: 60));

      final body = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 429) {
        throw Exception(
          body['error'] as String? ?? 'AI rate limit reached. Try again later.',
        );
      }

      if (response.statusCode == 403) {
        throw Exception(
          'AI image analysis is not enabled by the platform administrator.',
        );
      }

      if (response.statusCode != 200 || body['ok'] != true) {
        throw Exception(
          body['error'] as String? ??
              'AI image analysis failed (${response.statusCode})',
        );
      }

      return Map<String, dynamic>.from(body['data'] as Map? ?? {});
    } finally {
      client.close();
    }
  }

  static String _buildSystemPrompt() {
    final shopName = ShopSettings.shopName;
    final currency = ShopSettings.currency;
    final userName = SessionService.currentUserName;
    final now = DateTime.now();
    final todayDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final currentTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return '''You are Piki, an AI assistant for "$shopName" — a business that uses the Piki POS system.
You help with sales analysis, inventory management, customer insights, business decisions, and helping users understand how to use the Piki POS app.
The current user is "$userName". The currency is "$currency".
The current system date is $todayDate, and the current local time is $currentTime. This is your live concept of time.


APP USAGE CONTEXT (How to use Piki POS):
• Navigation: The app has a main side navigation bar (or bottom bar on mobile) with: Dashboard, POS, Products, Services, Reports, and Settings.
• Selling (POS Screen): Go to the "POS" screen to ring up customers. Click products/services to add to the cart. Click "Charge" or "Checkout" to process payments. You can switch payment methods (Cash, Card, Mobile Money).
• Adding Products: Go to the "Products" screen, click the "+" or "Add" button. You can manage stock, prices, categories, and barcodes here.
• Managing Services: Go to the "Services" screen to manage Service Desk/Queues (e.g., car washes, repairs). You can add a service to a queue and track its status. Services can also be sold quickly from the POS screen via the "Services" tab.
• Reports: Go to the "Reports" screen to see Profit & Loss, Sales Summaries, and Shift Reports.
• Multi-Branch: If the business has multiple branches, managers can switch branches or view consolidated data from the Settings or Dashboard.
• Piki AI: You are integrated directly into the app! If the user is in "Sell Mode", you can execute commands like adding items to their cart or clearing it. You can also create products and services directly via tools.

WRITE ACTIONS YOU CAN PERFORM:
• add_to_cart: Add an item to the POS cart. Extract query (item name) and qty (number).
• remove_from_cart: Remove a cart line or a quantity from it. Extract query and optional qty.
• set_cart_quantity: Set an existing cart line to an exact qty.
• repeat_last_item: Add the most recent sell-mode item again.
• clear_cart: Empty the POS cart.
• checkout: Navigate to the POS screen to complete payment for the cart.
• hold_sale: Save the current POS cart as a held sale and clear the cart.
• teach_alias: Learn that an alias phrase means a target product query.
• create_product: Create a new product. Extract name, price (number, required), cost (number, optional), stock (number, optional), unit (string, optional), category_id (string, optional), sku (string, optional), barcode (string, optional), brand (string, optional).
• draft_product: Safely draft a new product with an image from the web. ALWAYS use this instead of create_product when you are retrieving an image from the web. Extract name, price, image_url (MUST be a direct, raw http/https URL from the web search results' "imageUrl" field, never descriptive text), cost, stock.
• enhance_product_image: Improve an existing product image using the configured OpenRouter image model. Use this when the user asks to enhance, clean up, improve, or make a better catalog photo for a product that already has an image.
• edit_product: Edit an existing product or variant. Extract query/product name and changed fields such as price, cost, new_name, low_stock, or barcode.
• add_variant: Add a sellable variant to an existing product. Extract query/product_name, variant_name, price, cost, stock, low_stock, sku, and barcode when provided.
• create_service: Create a new service type (e.g., "Car Wash", "Haircut"). Extract name, price, category (optional), description (optional).
• record_product_sale: Record a product sale. Extract product_name, quantity (default 1), unit_price (use product price if not stated), payment_type (cash/card/mobile, default cash).
• record_service_sale: Record a service sale. Extract service_name, unit_price, payment_type. Optionally link a service_order_id if mentioned.
• add_service_field: Add a custom field to a service. Extract service_name, field_label, field_type (text/select/number), and options list (for select type).
• create_category: Create a new product category. Extract name and optional color.
• create_expense_category: Create a new expense category. Extract name and optional color.
• create_customer: Add a new customer. Extract name, phone (optional), and email (optional).
• create_supplier: Add a new supplier. Extract name, phone (optional), email (optional), address (optional), and note (optional).
• reconcile_stock: Adjust product stock level after a physical count. Extract product_name and new_count.
• When performing a write action, always confirm what was done clearly in your response.

CLARIFICATION GUIDELINES:
• If a user asks to "Add Bread", Bread is the name but the price is missing. Do NOT guess the price. Ask: "What is the selling price for Bread? You can also tell me the initial stock and unit (e.g., 50 loaves)."
• If the price is provided but stock is not, you can create it with 0 stock, but it's proactive to ask: "I can add Bread at \$5.00. Do you want to set an initial stock level or unit now?"
• Only proceed with write actions when you have the minimum required data (usually Name and Price).

Guidelines:
• Be concise and actionable — this is a POS app, not a chatbot.
• Use bullet points and numbers for data.
• Format currency values with the $currency symbol.
• If asked how to do something in the app, use the APP USAGE CONTEXT to provide step-by-step instructions.
• If asked to create, update stock, or record a sale, use an available local tool from the tool catalog — do NOT claim the action is complete unless a tool result confirms it.
• If asked about something you don't have data for, say so clearly.
• Proactively suggest 2-3 logical next steps or follow-up questions in the "suggestions" field of your JSON response. For example, if you list low stock items, suggest "Prepare a restock list" or "Show me supplier history".
• Never fabricate sales numbers or product data.
• You can suggest business improvements based on the data provided.''';
  }

  static Future<String> _gatherBusinessContext() async {
    try {
      final parts = <String>[];

      // Today's summary
      final todaySummary = await SaleRepository.getTodaySummary();
      final totalSales = (todaySummary['total_sales'] as num? ?? 0).toDouble();
      final totalRevenue = (todaySummary['total_revenue'] as num? ?? 0)
          .toDouble();
      final totalProfit = (todaySummary['total_profit'] as num? ?? 0)
          .toDouble();
      parts.add(
        'TODAY: ${totalSales.toInt()} sales, '
        'revenue ${ShopSettings.currency}${totalRevenue.toStringAsFixed(2)}, '
        'profit ${ShopSettings.currency}${totalProfit.toStringAsFixed(2)}',
      );

      // Stock overview
      final lowStockItems = await ProductRepository.getLowStock();
      parts.add(
        'LOW STOCK: ${lowStockItems.length} items below reorder threshold',
      );

      final expiryAlerts = await ProductRepository.getExpiryAlerts();
      parts.add(
        'EXPIRY: ${expiryAlerts.length} products are expired or expiring soon',
      );

      // Product count
      final productCount = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as cnt FROM products WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ?",
        [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
      );
      final cnt = (productCount.firstOrNull?['cnt'] as num? ?? 0).toInt();

      final variantCount = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as cnt FROM product_variants WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ?",
        [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
      );
      final vCnt = (variantCount.firstOrNull?['cnt'] as num? ?? 0).toInt();

      final categoryCount = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as cnt FROM product_categories WHERE deleted_at IS NULL",
      );
      final cCnt = (categoryCount.firstOrNull?['cnt'] as num? ?? 0).toInt();

      parts.add(
        'INVENTORY: $cnt total products, $vCnt product variations/variants, across $cCnt categories',
      );

      final productImageCount = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as cnt FROM products WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? AND image_url IS NOT NULL AND TRIM(image_url) <> ''",
        [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
      );
      final withImages = (productImageCount.firstOrNull?['cnt'] as num? ?? 0)
          .toInt();
      parts.add(
        'PRODUCT IMAGES: $withImages products have catalog images, ${cnt - withImages} are missing images. Product image enhancement uses $imageModelName.',
      );

      // Service count
      final serviceCount = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as cnt FROM services WHERE is_active = 1 AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?",
        [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
      );
      final sCnt = (serviceCount.firstOrNull?['cnt'] as num? ?? 0).toInt();
      parts.add('SERVICES: $sCnt active services');

      // Contact count
      final customerCount = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as cnt FROM customers WHERE deleted_at IS NULL",
      );
      final custCnt = (customerCount.firstOrNull?['cnt'] as num? ?? 0).toInt();

      final supplierCount = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as cnt FROM suppliers WHERE deleted_at IS NULL",
      );
      final supCnt = (supplierCount.firstOrNull?['cnt'] as num? ?? 0).toInt();
      parts.add(
        'CONTACTS: $custCnt registered customers, $supCnt registered suppliers',
      );

      final topProducts = await ReportRepository.getTopProducts(
        daysRange: 30,
        limit: 3,
      );
      if (topProducts.isNotEmpty) {
        parts.add(
          'TOP PRODUCTS 30D: ${topProducts.length} ranked products available',
        );
      }

      final topDebtors = await ReportRepository.getTopDebtors(limit: 3);
      if (topDebtors.isNotEmpty) {
        final totalOwed = topDebtors.fold<double>(
          0,
          (sum, row) => sum + (row['balance'] as num? ?? 0).toDouble(),
        );
        parts.add(
          'TOP DEBTORS: ${topDebtors.length} customer balances totalling ${ShopSettings.currency}${totalOwed.toStringAsFixed(2)}',
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
      parts.add(
        'PURCHASES: ${purchases.take(5).length} recent purchase records available',
      );

      try {
        final closedShifts = await ShiftRepository.getClosedShifts(limit: 3);
        if (closedShifts.isNotEmpty) {
          parts.add(
            'SHIFTS: ${closedShifts.length} recent closed shifts available',
          );
        }
      } catch (_) {
        // Shift data is optional in some installs.
      }

      return 'CURRENT BUSINESS DATA:\n${parts.join('\n')}';
    } catch (_) {
      return '';
    }
  }

  static Map<String, dynamic> extractPlannerResponseForTesting(String raw) {
    return _extractPlannerResponse(raw);
  }

  static Map<String, dynamic> _extractPlannerResponse(String raw) {
    for (final candidate in _jsonCandidates(raw)) {
      final parsed =
          _decodeJsonMap(candidate) ??
          _decodeJsonMap(_repairCommonJsonIssues(candidate));
      if (parsed != null) {
        return parsed;
      }
    }

    // Fallback 1: Extract XML <tool_call> tags used by some models (like Gemini)
    final xmlToolCalls = _extractXmlToolCalls(raw);
    if (xmlToolCalls != null) {
      return xmlToolCalls;
    }

    // Fallback 2: Do not crash the chat if a model returns prose instead of
    // planner JSON. This lets Piki show the useful answer and continue.
    final textAnswer =
        _extractMalformedJsonText(raw, 'answer') ??
        (_looksLikeMalformedPlannerJson(raw)
            ? 'I had trouble reading the AI plan. Please try again with one specific POS request.'
            : _cleanPlainTextFallback(raw));
    if (textAnswer.trim().isNotEmpty) {
      return {
        'mode': 'answer',
        'summary': 'Model returned text instead of planner JSON',
        'answer': textAnswer.trim(),
        'suggestions': const <String>[],
        'tool_calls': const <Map<String, dynamic>>[],
      };
    }

    throw const FormatException('AI planner did not return valid JSON');
  }

  static Iterable<String> _jsonCandidates(String raw) sync* {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    yield trimmed;

    final unfenced = _stripMarkdownFence(trimmed);
    if (unfenced != trimmed) {
      yield unfenced;
    }

    for (final candidate in _balancedJsonObjects(trimmed)) {
      yield candidate;
    }
  }

  static Map<String, dynamic>? _decodeJsonMap(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        return Map<String, dynamic>.from(parsed);
      }
      if (parsed is List) {
        final toolCalls = parsed
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        if (toolCalls.isNotEmpty) {
          return {
            'mode': 'tool',
            'summary': 'Converted planner array into tool calls',
            'tool_calls': toolCalls,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  static String _stripMarkdownFence(String raw) {
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    return match?.group(1)?.trim() ?? raw;
  }

  static Iterable<String> _balancedJsonObjects(String raw) sync* {
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;

    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        if (depth == 0) {
          start = i;
        }
        depth++;
      } else if (char == '}' && depth > 0) {
        depth--;
        if (depth == 0 && start >= 0) {
          yield raw.substring(start, i + 1);
          start = -1;
        }
      }
    }
  }

  static String _repairCommonJsonIssues(String raw) {
    final normalized = _stripMarkdownFence(raw)
        .replaceAll('\uFEFF', '')
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .trim();
    return normalized
        .replaceAllMapped(RegExp(r',\s*([}\]])'), (match) => match.group(1)!)
        .replaceAllMapped(
          RegExp(r'([{\[,]\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*:'),
          (match) => '${match.group(1)}"${match.group(2)}":',
        );
  }

  static Map<String, dynamic>? _extractXmlToolCalls(String raw) {
    final toolCallExp = RegExp(
      r'<tool_call>\s*([a-zA-Z0-9_]+)\s*(.*?)<\/tool_call>',
      dotAll: true,
    );
    final matches = toolCallExp.allMatches(raw);
    if (matches.isEmpty) return null;

    final toolCalls = <Map<String, dynamic>>[];
    for (final m in matches) {
      final tool = m.group(1);
      if (tool == null) continue;
      final argsText = m.group(2) ?? '';
      final args = <String, dynamic>{};
      final argExp = RegExp(
        r'<arg_key>(.*?)<\/arg_key>\s*<arg_value>(.*?)<\/arg_value>',
        dotAll: true,
      );
      for (final am in argExp.allMatches(argsText)) {
        final key = am.group(1)?.trim();
        final val = am.group(2)?.trim();
        if (key != null && val != null) {
          args[key] = num.tryParse(val) ?? val;
        }
      }
      toolCalls.add({'tool': tool, 'arguments': args});
    }
    return {
      'mode': 'tool',
      'summary': 'Extracted tool calls',
      'tool_calls': toolCalls,
    };
  }

  static String? _extractMalformedJsonText(String raw, String key) {
    final match = RegExp(
      '(?:"$key"|$key)\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"',
      dotAll: true,
    ).firstMatch(raw);
    final encoded = match?.group(1);
    if (encoded == null) return null;
    try {
      return jsonDecode('"$encoded"') as String;
    } catch (_) {
      return encoded;
    }
  }

  static bool _looksLikeMalformedPlannerJson(String raw) {
    final trimmed = _stripMarkdownFence(raw).trimLeft();
    return trimmed.startsWith('{') ||
        trimmed.contains('"mode"') ||
        trimmed.contains('mode:') ||
        trimmed.contains('"tool_calls"') ||
        trimmed.contains('tool_calls:');
  }

  static String _cleanPlainTextFallback(String raw) {
    final cleaned = _stripMarkdownFence(
      raw,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 2000) {
      return cleaned;
    }
    return '${cleaned.substring(0, 1997)}...';
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  static Future<String> _imageSourceToDataUrl(String source) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw Exception('Choose a product image first');
    }
    if (trimmed.startsWith('data:image/')) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Could not download the product image');
      }
      final mimeType =
          response.headers['content-type']
              ?.split(';')
              .first
              .trim()
              .toLowerCase() ??
          _mimeTypeForPath(uri.path);
      return 'data:$mimeType;base64,${base64Encode(response.bodyBytes)}';
    }

    final filePath = trimmed.startsWith('file://')
        ? Uri.parse(trimmed).toFilePath()
        : trimmed;
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Choose a product image first');
    }
    final bytes = await file.readAsBytes();
    return 'data:${_mimeTypeForPath(file.path)};base64,${base64Encode(bytes)}';
  }

  static Future<String> _saveGeneratedProductImage(String imageUrl) async {
    List<int> bytes;
    String mimeType;

    if (imageUrl.startsWith('data:image/')) {
      final comma = imageUrl.indexOf(',');
      if (comma < 0) {
        throw Exception('AI returned an invalid image');
      }
      final header = imageUrl.substring(0, comma);
      mimeType = header
          .replaceFirst('data:', '')
          .replaceFirst(RegExp(r';base64.*$'), '');
      bytes = base64Decode(imageUrl.substring(comma + 1));
    } else {
      final uri = Uri.tryParse(imageUrl);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw Exception('AI returned an unsupported image format');
      }
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Could not download the enhanced image');
      }
      mimeType =
          response.headers['content-type']
              ?.split(';')
              .first
              .trim()
              .toLowerCase() ??
          _mimeTypeForPath(uri.path);
      bytes = response.bodyBytes;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/product_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final ext = _extensionForMimeType(mimeType);
    final fileName = 'product_ai_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File('${imagesDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static String _extensionForMimeType(String mimeType) {
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('png')) return 'png';
    if (normalized.contains('webp')) return 'webp';
    return 'jpg';
  }

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
    if (!snapshot.allowsFeature('agent')) {
      throw Exception(
        'Your current subscription plan does not include Piki AI.',
      );
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
    return Uri.parse(
      '$backendUrl/$path',
    ).replace(queryParameters: queryParameters);
  }
}
