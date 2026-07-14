import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/services/catalog_order_service.dart';
import '../../../core/services/catalog_share_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/storefront_brand_service.dart';
import '../../../core/services/pos_payment_service.dart';
import '../../../core/services/storefront_theme_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/services/openrouter_service.dart';
import '../../customers/data/customer_repository.dart';
import '../../products/data/category_repository.dart';
import '../../products/data/product_repository.dart';
import '../../products/data/product_variant_repository.dart';
import '../../purchases/data/purchase_repository.dart';
import '../../reports/data/expense_repository.dart';
import '../../reports/data/bi_repository.dart';
import '../../reports/data/report_repository.dart';
import '../../sales/data/sale_repository.dart';
import '../../services/data/service_repository.dart';
import '../../shifts/data/shift_repository.dart';
import 'piki_models.dart';

// ─── Skill definitions ──────────────────────────────────────────────────────

enum PikiSkill {
  analyzeLowStock,
  todaysSummary,
  restockList,
  salesReport,
  productSearch,
  profitSummary,
  shiftSummary,
  expiryCheck,
  topDebtors,
  topProducts,
  expenseSummary,
  purchaseHistory,
  dailyBrief,
  predictiveRestock,
  anomalyAlerts,
  customerFollowups,
  dailyWhatsappReport,
  catalogOrders,
  voiceCashier,
  loyaltyOverview,
  giftCardOverview,
  promotionOverview,
  rolesOverview,
  serialOverview,
  stocktakeOverview,
  campaignOverview,
  currencyOverview,
  wastageOverview,
  restaurantOverview,
  attendanceOverview,
  customerGroupsOverview,
  purchaseApprovalsOverview,
  deliveryOverview,
  businessIntelligence,
  customerPortalOverview,
}

class PikiRequestAnalysis {
  final String originalInput;
  final String normalizedInput;
  final List<PikiSkill> skills;
  final int daysRange;
  final int resultLimit;
  final String? productQuery;
  final String? filter;

  const PikiRequestAnalysis({
    required this.originalInput,
    required this.normalizedInput,
    required this.skills,
    this.daysRange = 1,
    this.resultLimit = 10,
    this.productQuery,
    this.filter,
  });

  String get periodLabel => PikiAgentService.periodLabelForDays(daysRange);
}

class PikiSellableProduct {
  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;

  const PikiSellableProduct({required this.product, this.variant});

  String get cartKey {
    final productId = product['id'] as String? ?? '';
    final variantId = variant?['id'] as String?;
    return variantId == null || variantId.isEmpty
        ? productId
        : '${productId}_$variantId';
  }

  String get label {
    final productName = product['name'] as String? ?? 'Item';
    final variantName = variant?['name'] as String?;
    if (variantName == null || variantName.trim().isEmpty) {
      return productName;
    }
    return '$productName - $variantName';
  }
}

// ─── Agent engine ───────────────────────────────────────────────────────────

class PikiAgentService {
  static const toolLowStock = 'low_stock';
  static const toolTodaySummary = 'sales_summary';
  static const toolRestockList = 'restock_list';
  static const toolSalesReport = 'sales_report';
  static const toolProductSearch = 'product_search';
  static const toolProfitSummary = 'profit_summary';
  static const toolShiftSummary = 'shift_summary';
  static const toolExpiryCheck = 'expiry_check';
  static const toolTopDebtors = 'top_debtors';
  static const toolTopProducts = 'top_products';
  static const toolExpenseSummary = 'expense_summary';
  static const toolPurchaseHistory = 'purchase_history';
  static const toolPurchaseDraft = 'purchase_draft';
  static const toolDailyBrief = 'daily_brief';
  static const toolPredictiveRestock = 'predictive_restock';
  static const toolAnomalyAlerts = 'anomaly_alerts';
  static const toolCustomerFollowups = 'customer_followups';
  static const toolDailyWhatsappReport = 'daily_whatsapp_report';
  static const toolCatalogOrders = 'catalog_orders';
  static const toolImageOrderDraft = 'image_order_draft';
  static const toolVoiceCashierHelp = 'voice_cashier_help';
  static const toolCreateProduct = 'create_product';
  static const toolDraftProduct = 'draft_product';
  static const toolEnhanceProductImage = 'enhance_product_image';
  static const toolCreateService = 'create_service';
  static const toolEditProduct = 'edit_product';
  static const toolDeleteProduct = 'delete_product';
  static const toolAddVariant = 'add_variant';
  static const toolRecordProductSale = 'record_product_sale';
  static const toolRecordServiceSale = 'record_service_sale';
  static const toolCreateCategory = 'create_category';
  static const toolCreateExpenseCategory = 'create_expense_category';
  static const toolCreateCustomer = 'create_customer';
  static const toolCreateSupplier = 'create_supplier';
  static const toolReconcileStock = 'reconcile_stock';
  static const toolAddServiceField = 'add_service_field';
  static const toolCustomerSearch = 'customer_search';
  static const toolSupplierSearch = 'supplier_search';
  static const toolWebSearch = 'web_search';
  static const toolAddToCart = 'add_to_cart';
  static const toolRemoveFromCart = 'remove_from_cart';
  static const toolSetCartQuantity = 'set_cart_quantity';
  static const toolRepeatLast = 'repeat_last_item';
  static const toolClearCart = 'clear_cart';
  static const toolCheckout = 'checkout';
  static const toolHoldSale = 'hold_sale';
  static const toolTeachAlias = 'teach_alias';
  static const toolLoyaltyOverview = 'loyalty_overview';
  static const toolGiftCardOverview = 'gift_card_overview';
  static const toolPromotionOverview = 'promotion_overview';
  static const toolRolesOverview = 'roles_overview';
  static const toolSerialOverview = 'serial_overview';
  static const toolStocktakeOverview = 'stocktake_overview';
  static const toolCampaignOverview = 'campaign_overview';
  static const toolCurrencyOverview = 'currency_overview';
  static const toolWastageOverview = 'wastage_overview';
  static const toolRestaurantOverview = 'restaurant_overview';
  static const toolAttendanceOverview = 'attendance_overview';
  static const toolCustomerGroupsOverview = 'customer_groups_overview';
  static const toolPurchaseApprovalsOverview = 'purchase_approvals_overview';
  static const toolDeliveryOverview = 'delivery_overview';
  static const toolBusinessIntelligence = 'business_intelligence';
  static const toolCustomerPortalOverview = 'customer_portal_overview';
  static const toolBuildStorefront = 'build_storefront';
  static const toolCustomizeCheckout = 'customize_checkout';
  static const toolSetupPaymentGateway = 'setup_payment_gateway';

  // Each skill has a list of keyword-group patterns (ALL keywords in a group
  // must appear for a match).
  static final _skillPatterns = <PikiSkill, List<List<String>>>{
    PikiSkill.analyzeLowStock: [
      ['low', 'stock'],
      ['stock', 'alert'],
      ['out', 'stock'],
      ['running', 'low'],
      ['inventory', 'check'],
      ['analyze', 'inventory'],
    ],
    PikiSkill.todaysSummary: [
      ['today', 'summary'],
      ['daily', 'summary'],
      ['today', 'sales'],
      ['sales', 'summary'],
      ['how', 'today'],
      ['today', 'report'],
    ],
    PikiSkill.restockList: [
      ['restock'],
      ['reorder'],
      ['need', 'order'],
      ['purchase', 'list'],
    ],
    PikiSkill.salesReport: [
      ['sales', 'report'],
      ['recent', 'sales'],
      ['show', 'sales'],
      ['list', 'sales'],
    ],
    PikiSkill.productSearch: [
      ['find', 'product'],
      ['search', 'product'],
      ['show', 'product'],
      ['list', 'product'],
    ],
    PikiSkill.profitSummary: [
      ['profit'],
      ['margin'],
      ['earnings'],
    ],
    PikiSkill.shiftSummary: [
      ['shift'],
    ],
    PikiSkill.expiryCheck: [
      ['expir'],
      ['expiry'],
      ['shelf', 'life'],
    ],
    PikiSkill.topDebtors: [
      ['top', 'debtor'],
      ['who', 'owes'],
      ['kopesha', 'balance'],
      ['outstanding', 'balance'],
      ['overdue', 'customer'],
      ['credit', 'customer'],
    ],
    PikiSkill.topProducts: [
      ['top', 'product'],
      ['best', 'seller'],
      ['best', 'selling'],
      ['top', 'selling'],
      ['popular', 'product'],
      ['most', 'sold'],
    ],
    PikiSkill.expenseSummary: [
      ['expense'],
      ['spending'],
      ['expenditure'],
      ['operating', 'cost'],
      ['expense', 'summary'],
    ],
    PikiSkill.purchaseHistory: [
      ['purchase'],
      ['supplier', 'order'],
      ['stock', 'received'],
      ['stock', 'in'],
      ['restock', 'history'],
    ],
    PikiSkill.dailyBrief: [
      ['daily', 'brief'],
      ['business', 'news'],
      ['market', 'comparison'],
      ['how', 'doing', 'compared'],
    ],
    PikiSkill.predictiveRestock: [
      ['predict', 'restock'],
      ['forecast', 'stock'],
      ['demand', 'forecast'],
      ['future', 'stock'],
      ['what', 'will', 'run', 'out'],
    ],
    PikiSkill.anomalyAlerts: [
      ['anomaly'],
      ['unusual'],
      ['risk', 'alert'],
      ['sales', 'drop'],
      ['business', 'alert'],
      ['what', 'is', 'wrong'],
    ],
    PikiSkill.customerFollowups: [
      ['customer', 'follow'],
      ['send', 'reminder'],
      ['kopesha', 'reminder'],
      ['overdue', 'message'],
      ['follow', 'debtors'],
    ],
    PikiSkill.dailyWhatsappReport: [
      ['whatsapp', 'report'],
      ['daily', 'whatsapp'],
      ['send', 'daily', 'report'],
      ['owner', 'report'],
    ],
    PikiSkill.catalogOrders: [
      ['catalog', 'order'],
      ['online', 'order'],
      ['customer', 'order'],
      ['pending', 'order'],
      ['order', 'link'],
      ['orders'],
      ['oders'],
    ],
    PikiSkill.voiceCashier: [
      ['voice', 'cashier'],
      ['auto', 'listen'],
      ['hands', 'free'],
      ['voice', 'sell'],
    ],
    PikiSkill.loyaltyOverview: [
      ['loyalty'],
      ['reward', 'point'],
      ['customer', 'point'],
    ],
    PikiSkill.giftCardOverview: [
      ['gift', 'card'],
      ['voucher'],
    ],
    PikiSkill.promotionOverview: [
      ['promotion'],
      ['promo'],
      ['discount', 'campaign'],
    ],
    PikiSkill.rolesOverview: [
      ['role', 'permission'],
      ['staff', 'permission'],
      ['custom', 'role'],
    ],
    PikiSkill.serialOverview: [
      ['serial'],
      ['warranty'],
    ],
    PikiSkill.stocktakeOverview: [
      ['stocktake'],
      ['cycle', 'count'],
      ['physical', 'count'],
    ],
    PikiSkill.campaignOverview: [
      ['sms', 'campaign'],
      ['marketing', 'campaign'],
    ],
    PikiSkill.currencyOverview: [
      ['exchange', 'rate'],
      ['multi', 'currency'],
      ['secondary', 'currency'],
    ],
    PikiSkill.wastageOverview: [
      ['wastage'],
      ['spoilage'],
      ['waste', 'stock'],
    ],
    PikiSkill.restaurantOverview: [
      ['restaurant'],
      ['table', 'status'],
      ['kitchen', 'display'],
    ],
    PikiSkill.attendanceOverview: [
      ['attendance'],
      ['clocked', 'in'],
      ['clock', 'out'],
    ],
    PikiSkill.customerGroupsOverview: [
      ['customer', 'group'],
      ['customer', 'segment'],
    ],
    PikiSkill.purchaseApprovalsOverview: [
      ['purchase', 'approval'],
      ['pending', 'approval'],
    ],
    PikiSkill.deliveryOverview: [
      ['delivery'],
      ['rider'],
      ['tracking', 'order'],
    ],
    PikiSkill.businessIntelligence: [
      ['business', 'intelligence'],
      ['bi', 'dashboard'],
      ['customer', 'lifetime', 'value'],
      ['cohort'],
      ['turnover'],
      ['sales', 'forecast'],
    ],
    PikiSkill.customerPortalOverview: [
      ['customer', 'portal'],
      ['self', 'service'],
      ['portal', 'payment'],
    ],
  };

  static final _toolToSkill = <String, PikiSkill>{
    toolLowStock: PikiSkill.analyzeLowStock,
    toolTodaySummary: PikiSkill.todaysSummary,
    toolRestockList: PikiSkill.restockList,
    toolSalesReport: PikiSkill.salesReport,
    toolProductSearch: PikiSkill.productSearch,
    toolProfitSummary: PikiSkill.profitSummary,
    toolShiftSummary: PikiSkill.shiftSummary,
    toolExpiryCheck: PikiSkill.expiryCheck,
    toolTopDebtors: PikiSkill.topDebtors,
    toolTopProducts: PikiSkill.topProducts,
    toolExpenseSummary: PikiSkill.expenseSummary,
    toolPurchaseHistory: PikiSkill.purchaseHistory,
    toolDailyBrief: PikiSkill.dailyBrief,
    toolPredictiveRestock: PikiSkill.predictiveRestock,
    toolAnomalyAlerts: PikiSkill.anomalyAlerts,
    toolCustomerFollowups: PikiSkill.customerFollowups,
    toolDailyWhatsappReport: PikiSkill.dailyWhatsappReport,
    toolCatalogOrders: PikiSkill.catalogOrders,
    toolVoiceCashierHelp: PikiSkill.voiceCashier,
    toolLoyaltyOverview: PikiSkill.loyaltyOverview,
    toolGiftCardOverview: PikiSkill.giftCardOverview,
    toolPromotionOverview: PikiSkill.promotionOverview,
    toolRolesOverview: PikiSkill.rolesOverview,
    toolSerialOverview: PikiSkill.serialOverview,
    toolStocktakeOverview: PikiSkill.stocktakeOverview,
    toolCampaignOverview: PikiSkill.campaignOverview,
    toolCurrencyOverview: PikiSkill.currencyOverview,
    toolWastageOverview: PikiSkill.wastageOverview,
    toolRestaurantOverview: PikiSkill.restaurantOverview,
    toolAttendanceOverview: PikiSkill.attendanceOverview,
    toolCustomerGroupsOverview: PikiSkill.customerGroupsOverview,
    toolPurchaseApprovalsOverview: PikiSkill.purchaseApprovalsOverview,
    toolDeliveryOverview: PikiSkill.deliveryOverview,
    toolBusinessIntelligence: PikiSkill.businessIntelligence,
    toolCustomerPortalOverview: PikiSkill.customerPortalOverview,
  };

  static final _toolLabels = <String, String>{
    toolLowStock: 'Check low stock',
    toolTodaySummary: 'Review sales summary',
    toolRestockList: 'Prepare restock list',
    toolSalesReport: 'Review sales history',
    toolProductSearch: 'Search products',
    toolProfitSummary: 'Check profit',
    toolShiftSummary: 'Review shifts',
    toolExpiryCheck: 'Check expiry',
    toolTopDebtors: 'Review top debtors',
    toolTopProducts: 'Review top products',
    toolExpenseSummary: 'Review expenses',
    toolPurchaseHistory: 'Review purchase history',
    toolPurchaseDraft: 'Create purchase draft',
    toolDailyBrief: 'Daily market brief',
    toolPredictiveRestock: 'Predict restock needs',
    toolAnomalyAlerts: 'Detect business anomalies',
    toolCustomerFollowups: 'Prepare customer follow-ups',
    toolDailyWhatsappReport: 'Draft WhatsApp report',
    toolCatalogOrders: 'Review catalog orders',
    toolImageOrderDraft: 'Read order image',
    toolVoiceCashierHelp: 'Explain voice cashier',
    toolCreateProduct: 'Create product',
    toolDraftProduct: 'Draft a product from the web',
    toolEnhanceProductImage: 'Enhance product image',
    toolCreateService: 'Create service',
    toolEditProduct: 'Edit product',
    toolDeleteProduct: 'Delete product',
    toolAddVariant: 'Add variant',
    toolRecordProductSale: 'Record product sale',
    toolRecordServiceSale: 'Record service sale',
    toolCreateCategory: 'Create product category',
    toolCreateExpenseCategory: 'Create expense category',
    toolCreateCustomer: 'Create customer',
    toolCreateSupplier: 'Create supplier',
    toolReconcileStock: 'Reconcile stock',
    toolAddServiceField: 'Add service field',
    toolCustomerSearch: 'Search customers',
    toolSupplierSearch: 'Search suppliers',
    toolWebSearch: 'Search the web',
    toolAddToCart: 'Add to cart',
    toolRemoveFromCart: 'Remove from cart',
    toolSetCartQuantity: 'Set cart quantity',
    toolRepeatLast: 'Repeat last cart item',
    toolClearCart: 'Clear cart',
    toolCheckout: 'Checkout',
    toolHoldSale: 'Hold sale',
    toolTeachAlias: 'Teach cashier alias',
    toolCustomizeCheckout: 'Customize storefront checkout',
    toolSetupPaymentGateway: 'Configure storefront payment gateway',
    toolBuildStorefront: 'Build storefront website',
  };

  static final _toolDescriptions = <String, String>{
    toolLowStock:
        'Read current inventory levels and minimum stock thresholds. Returns items[] with name, current_stock, low_stock_threshold, unit.',
    toolTodaySummary:
        'Read sales, revenue, and profit for a time period. Returns total_sales, total_revenue, total_profit.',
    toolRestockList:
        'Build a reorder list from live low-stock products. Returns items[] with name, current_stock, low_stock_threshold, suggested_qty.',
    toolSalesReport:
        'List recent sales in a selected period. Returns items[] with date, product_name, quantity, total, payment_type.',
    toolProductSearch:
        'Look up products by name, barcode, or SKU. Returns items[] with name, price, cost, stock, unit, barcode, category, image_url.',
    toolProfitSummary:
        'Calculate profit for a selected period. Returns total_revenue, total_cost, total_profit, margin_percent.',
    toolShiftSummary:
        'Review recently closed cashier shifts. Returns shifts[] with user_name, start, end, total_sales, total_revenue.',
    toolExpiryCheck:
        'Check batches for expired or soon-to-expire products. Returns items[] with product_name, batch_id, expiry_date, days_remaining, quantity.',
    toolTopDebtors:
        'Find customers with the highest outstanding balances. Returns items[] with customer_name, total_owed, last_payment_date.',
    toolTopProducts:
        'Rank best-selling products over a period. Returns items[] with name, total_qty_sold, total_revenue, image_url.',
    toolExpenseSummary:
        'Summarize recent operating expenses. Returns items[] with category, total_amount, count.',
    toolPurchaseHistory:
        'Show recent stock-in and supplier history. Returns items[] with date, supplier, product_name, quantity, cost.',
    toolPurchaseDraft:
        'Build a purchase draft from low stock and recent supplier history. Returns items[] with product_name, suggested_qty, last_supplier, last_cost.',
    toolDailyBrief:
        'Fetch a short business performance brief for today. Returns summary text, sales count, revenue, and profit.',
    toolPredictiveRestock:
        'Forecast products likely to run out from sales velocity, current stock, and low-stock thresholds. Returns items[] with name, days_until_stockout, daily_velocity, current_stock.',
    toolAnomalyAlerts:
        'Find unusual sales, stock, Kopesha, expiry, and shift risks that need attention. Returns alerts[] with type, severity, message, details.',
    toolCustomerFollowups:
        'Prepare WhatsApp/SMS-ready Kopesha reminder messages for due, overdue, or risky customers. Returns items[] with customer_name, amount_owed, days_overdue, message.',
    toolDailyWhatsappReport:
        'Draft an owner-ready daily WhatsApp report from sales, products, stock, and alerts. Returns formatted report text.',
    toolCatalogOrders:
        'Read customer orders submitted through the public catalog link. Returns orders[] with id, customer_name, items, total, status, created_at.',
    toolLoyaltyOverview:
        'Read loyalty rules and leading customer point balances. No rewards are issued or redeemed.',
    toolGiftCardOverview:
        'Read active gift cards, remaining balances, and expiry risk. Does not issue, top up, redeem, or deactivate cards.',
    toolPromotionOverview:
        'Read active promotions and discount configuration. Does not create, edit, enable, or disable promotions.',
    toolRolesOverview:
        'Read custom role names, base roles, and active status. Does not change permissions or users.',
    toolSerialOverview:
        'Read serial availability, sold counts, and warranties nearing expiry. Does not assign or sell serials.',
    toolStocktakeOverview:
        'Read current stocktake sessions and unresolved item variances. Does not count, complete, or cancel sessions.',
    toolCampaignOverview:
        'Read SMS campaign drafts and sending outcomes. Does not create or send messages.',
    toolCurrencyOverview:
        'Read the active base/quote exchange rate. Does not change currency or exchange settings.',
    toolWastageOverview:
        'Read recent wastage logs and estimated cost. Does not record wastage or change stock.',
    toolRestaurantOverview:
        'Read restaurant table occupancy and open kitchen orders. Does not open, alter, or settle orders.',
    toolAttendanceOverview:
        'Read clocked-in employees and recent attendance. Does not clock staff in or out.',
    toolCustomerGroupsOverview:
        'Read customer groups and member counts. Does not create groups or edit membership.',
    toolPurchaseApprovalsOverview:
        'Read purchase orders awaiting approval. Does not submit, approve, reject, or receive orders.',
    toolDeliveryOverview:
        'Read delivery zones and delivery statuses. Does not assign riders or update delivery status.',
    toolBusinessIntelligence:
        'Read the advanced BI dashboard: customer value, sales forecast, cohort retention, and employee turnover. No data is changed.',
    toolCustomerPortalOverview:
        'Read how many customers are eligible for the email-verified portal and their outstanding balances. Does not access customer credentials or initiate payments.',
    toolImageOrderDraft:
        'Analyze a product or order photo and draft item lines from the image.',
    toolVoiceCashierHelp:
        'Explain how cashiers can use hands-free voice commands in Sell Mode.',
    toolCreateProduct:
        'Create a product when name and price are known. Returns created product details.',
    toolDraftProduct:
        'Prepare a product with a web image for user approval before saving.',
    toolEnhanceProductImage:
        'Enhance an existing product photo and save the improved image on the product.',
    toolCreateService:
        'Create a service template when name and price are known. Returns created service details.',
    toolEditProduct:
        'Edit an existing product\'s details like price, cost, name, or low stock threshold. Returns updated product.',
    toolDeleteProduct:
        'Delete an existing product or matched variant from the catalog. Uses soft-delete and returns deleted item details.',
    toolAddVariant:
        'Add a variant (size, color, etc.) to an existing product. Returns created variant details.',
    toolRecordProductSale:
        'Record a product sale immediately against inventory. Returns sale confirmation with total.',
    toolRecordServiceSale:
        'Record a service sale immediately. Returns sale confirmation with total.',
    toolCreateCategory:
        'Create a product category. Returns category id and name.',
    toolCreateExpenseCategory:
        'Create an expense category. Returns category id and name.',
    toolCreateCustomer:
        'Create a customer record. Returns customer id and name.',
    toolCreateSupplier:
        'Create a supplier record. Returns supplier id and name.',
    toolReconcileStock:
        'Set a product stock count after a physical count. Returns updated stock level.',
    toolAddServiceField: 'Add a custom field to an existing service template.',
    toolCustomerSearch:
        'Look up customers by name, phone, or email. Returns items[] with name, phone, email, total_owed.',
    toolSupplierSearch:
        'Look up suppliers by name, phone, or email. Returns items[] with name, phone, email, address.',
    toolWebSearch:
        'Search live web results for current prices, market context, regulations, supplier information, or other external facts not stored in the POS. Returns results[] with title, snippet, url, imageUrl.',
    toolAddToCart: 'Add products, variants, or services to the live POS cart.',
    toolRemoveFromCart: 'Remove a line or quantity from the live POS cart.',
    toolSetCartQuantity: 'Set an existing POS cart line to an exact quantity.',
    toolRepeatLast: 'Add the last sold item again.',
    toolClearCart: 'Empty the cart.',
    toolCheckout: 'Go to checkout screen.',
    toolHoldSale: 'Save the current cart as a held sale and clear the cart.',
    toolTeachAlias:
        'Remember a cashier phrase, nickname, or local term for a product query.',
    toolBuildStorefront:
        'Create or refresh a retail, service, or restaurant storefront using approved brand copy, theme, colour, and checkout settings. The website change is staged for confirmation before publishing.',
    toolCustomizeCheckout:
        'Create a storefront checkout draft using safe fields, labels, fulfillment, and active payment methods. The draft is published only after explicit confirmation.',
    toolSetupPaymentGateway:
        'Configure public M-Pesa gateway settings and enable it only when owner-supplied credentials already exist securely on the server. Never requests, reads, displays, or changes consumer secrets or passkeys.',
  };

  static final _toolArguments = <String, String>{
    toolLowStock: 'daysRange(int), limit(int)',
    toolTodaySummary: 'daysRange(int)',
    toolRestockList: 'limit(int)',
    toolSalesReport: 'daysRange(int), limit(int)',
    toolProductSearch: 'query(string), limit(int)',
    toolProfitSummary: 'daysRange(int)',
    toolShiftSummary: 'limit(int)',
    toolExpiryCheck: 'limit(int)',
    toolTopDebtors: 'limit(int)',
    toolTopProducts: 'daysRange(int), limit(int)',
    toolExpenseSummary: 'daysRange(int), limit(int)',
    toolPurchaseHistory: 'daysRange(int), limit(int)',
    toolPurchaseDraft: 'limit(int)',
    toolDailyBrief: 'daysRange(int)',
    toolPredictiveRestock: 'daysRange(int), limit(int)',
    toolAnomalyAlerts: 'daysRange(int), limit(int)',
    toolCustomerFollowups:
        'filter(string: overdue|due_today|risky|all), limit(int)',
    toolDailyWhatsappReport: 'daysRange(int)',
    toolCatalogOrders:
        'filter/status(string: pending|accepted|completed|cancelled|all), limit(int)',
    toolLoyaltyOverview: 'limit(int)',
    toolGiftCardOverview: 'limit(int)',
    toolPromotionOverview: 'limit(int)',
    toolRolesOverview: 'limit(int)',
    toolSerialOverview: 'limit(int)',
    toolStocktakeOverview: 'limit(int)',
    toolCampaignOverview: 'limit(int)',
    toolCurrencyOverview: 'none',
    toolWastageOverview: 'daysRange(int), limit(int)',
    toolRestaurantOverview: 'limit(int)',
    toolAttendanceOverview: 'limit(int)',
    toolCustomerGroupsOverview: 'limit(int)',
    toolPurchaseApprovalsOverview: 'limit(int)',
    toolDeliveryOverview: 'limit(int)',
    toolBusinessIntelligence: 'none',
    toolCustomerPortalOverview: 'limit(int)',
    toolImageOrderDraft:
        'image_source/image_url/url/path(string, required), note(string)',
    toolVoiceCashierHelp: 'none',
    toolCreateProduct:
        'name(string, required), price(number, required), cost(number), stock(number), unit(string), category_id(string), category(string), sku(string), barcode(string), brand(string)',
    toolDraftProduct:
        'name(string, required), price(number, required), image_url(string), cost(number), stock(number), unit(string), category_id(string), category(string), sku(string), barcode(string), brand(string)',
    toolEnhanceProductImage:
        'query/product_name/name(string, required), prompt(string, optional)',
    toolCreateService:
        'name(string, required), price/base_price(number, required), category(string), description(string), duration_minutes(int)',
    toolEditProduct:
        'query/name(string, required), price(number), cost(number), new_name(string), low_stock(number), barcode(string)',
    toolDeleteProduct:
        'query/name/product_name(string, required), sku(string), barcode(string)',
    toolAddVariant:
        'query/product_name(string, required), variant_name/name(string, required), price(number, required), cost(number), sku(string), barcode(string), stock(number), low_stock(number)',
    toolRecordProductSale:
        'product_name/query(string, required), quantity(number), unit_price/price(number), payment_type(string)',
    toolRecordServiceSale:
        'service_name/query(string, required), quantity(number), unit_price/price(number), payment_type(string), customer_name(string)',
    toolCreateCategory: 'name(string, required), color(string)',
    toolCreateExpenseCategory: 'name(string, required), color(string)',
    toolCreateCustomer: 'name(string, required), phone(string), email(string)',
    toolCreateSupplier:
        'name(string, required), phone(string), email(string), address(string), note(string)',
    toolReconcileStock:
        'product_name/query(string, required), new_count/count/stock(number, required)',
    toolAddServiceField:
        'service_name/query(string, required), field_label/label(string, required), field_type(string), options(list/string), is_required(bool)',
    toolCustomerSearch: 'query(string), limit(int)',
    toolSupplierSearch: 'query(string), limit(int)',
    toolWebSearch:
        'query(string, required), location(string), countryCode(string), language(string), limit(int)',
    toolAddToCart: 'query(string, required), qty(number)',
    toolRemoveFromCart: 'query(string), qty(number)',
    toolSetCartQuantity: 'query(string), qty/quantity(number, required)',
    toolRepeatLast: 'qty(number)',
    toolCheckout: 'payment_type(string)',
    toolTeachAlias: 'alias(string, required), target(string, required)',
    toolBuildStorefront:
        'storefront_type(string: retail|services|restaurant, required), business_name(string), tagline(string), description(string), theme_name(string), preset/theme(string: studio|minimal|warm|fresh|bold), primary_color(string #RRGGBB), hero_style(string: cover|split|minimal), card_style(string: bordered|elevated|minimal), image_ratio(string: square|portrait|landscape), corner_style(string: sharp|soft|rounded|pill), make_main(bool), publish(bool)',
    toolCustomizeCheckout:
        'storefront_type(string: retail|services|restaurant, required), theme_id(string), payment_methods(list: manual|mpesa), fulfillment_methods(list: pickup|delivery), show_delivery_address(bool), show_order_note(bool), show_order_tracking(bool), checkout_title(string), checkout_button_label(string), success_message(string), publish(bool)',
    toolSetupPaymentGateway:
        'provider(string: mpesa, required), display_name(string), shortcode(string), transaction_type(string: CustomerPayBillOnline|CustomerBuyGoodsOnline), account_reference(string), send_sms(bool), enable(bool). Secret credentials are forbidden.',
  };

  static String toolCatalogPrompt() {
    final buffer = StringBuffer();
    for (final entry in _toolLabels.entries) {
      if (entry.key == toolWebSearch && !OpenRouterService.webSearchEnabled) {
        continue;
      }
      buffer.writeln(
        '- ${entry.key}: ${entry.value}. ${_toolDescriptions[entry.key]} '
        'Arguments: ${_toolArguments[entry.key] ?? 'none'}.',
      );
    }
    return buffer.toString().trimRight();
  }

  static bool isKnownTool(String tool) => _toolLabels.containsKey(tool);

  static final Set<String> _writeTools = <String>{
    toolPurchaseDraft,
    toolCreateProduct,
    toolDraftProduct,
    toolEnhanceProductImage,
    toolCreateService,
    toolEditProduct,
    toolDeleteProduct,
    toolAddVariant,
    toolRecordProductSale,
    toolRecordServiceSale,
    toolCreateCategory,
    toolCreateExpenseCategory,
    toolCreateCustomer,
    toolCreateSupplier,
    toolReconcileStock,
    toolAddServiceField,
    toolAddToCart,
    toolRemoveFromCart,
    toolSetCartQuantity,
    toolRepeatLast,
    toolClearCart,
    toolCheckout,
    toolHoldSale,
    toolTeachAlias,
    toolBuildStorefront,
    toolCustomizeCheckout,
    toolSetupPaymentGateway,
  };

  static bool requiresConfirmation(String tool) => _writeTools.contains(tool);

  static Map<String, dynamic> buildWriteConfirmationPreview(
    String tool, {
    required Map<String, dynamic> args,
  }) {
    final detail = args.entries
        .where(
          (entry) => entry.value != null && '${entry.value}'.trim().isNotEmpty,
        )
        .take(6)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
    return {
      'tool': tool,
      'success': true,
      'requires_confirmation': true,
      'preview_args': args,
      'summary':
          '${_toolLabels[tool] ?? tool} is ready to apply'
          '${detail.isEmpty ? '' : ' ($detail)'}.'
          ' Reply “confirm” to continue or “cancel” to leave your data unchanged.',
    };
  }

  static PikiRequestAnalysis analyzeRequest(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final daysRange = _extractDaysRange(normalized);
    final resultLimit = _extractResultLimit(normalized);
    final productQuery = _extractProductQuery(input);
    final scores = <PikiSkill, int>{};

    void addScore(PikiSkill skill, int value) {
      scores[skill] = (scores[skill] ?? 0) + value;
    }

    bool hasAny(List<String> terms) =>
        terms.any((term) => normalized.contains(term));
    bool hasAll(List<String> terms) =>
        terms.every((term) => normalized.contains(term));

    if (hasAll(['low', 'stock']) ||
        hasAll(['stock', 'alert']) ||
        hasAll(['running', 'low']) ||
        hasAll(['out', 'stock'])) {
      addScore(PikiSkill.analyzeLowStock, 4);
    }
    if (hasAny(['restock', 'reorder']) ||
        hasAll(['need', 'order']) ||
        hasAll(['purchase', 'list'])) {
      addScore(PikiSkill.restockList, 4);
    }
    if (hasAll(['predict', 'restock']) ||
        hasAll(['forecast', 'stock']) ||
        hasAll(['demand', 'forecast']) ||
        hasAll(['what', 'will', 'run', 'out']) ||
        hasAny(['stock forecast', 'future stock'])) {
      addScore(PikiSkill.predictiveRestock, 6);
    }
    if (hasAny(['anomaly', 'unusual', 'alerts']) ||
        hasAll(['sales', 'drop']) ||
        hasAll(['risk', 'alert']) ||
        hasAll(['what', 'is', 'wrong'])) {
      addScore(PikiSkill.anomalyAlerts, 6);
    }
    if (hasAll(['customer', 'follow']) ||
        hasAll(['kopesha', 'reminder']) ||
        hasAll(['overdue', 'message']) ||
        hasAll(['send', 'reminder']) ||
        hasAll(['follow', 'debtors'])) {
      addScore(PikiSkill.customerFollowups, 6);
    }
    if (hasAll(['whatsapp', 'report']) ||
        hasAll(['daily', 'whatsapp']) ||
        hasAll(['owner', 'report']) ||
        hasAll(['send', 'daily', 'report'])) {
      addScore(PikiSkill.dailyWhatsappReport, 6);
    }
    final asksCatalogOrders =
        hasAll(['catalog', 'order']) ||
        hasAll(['online', 'order']) ||
        hasAll(['customer', 'order']) ||
        hasAll(['pending', 'order']) ||
        hasAll(['order', 'link']) ||
        hasAny(['catalog orders', 'online orders', 'customer orders']) ||
        (hasAny(['orders', 'oders']) &&
            !hasAny(['purchase', 'supplier', 'restock', 'stock in']));
    if (asksCatalogOrders) {
      addScore(PikiSkill.catalogOrders, 6);
    }
    if (hasAll(['voice', 'cashier']) ||
        hasAll(['auto', 'listen']) ||
        hasAll(['hands', 'free']) ||
        hasAll(['voice', 'sell'])) {
      addScore(PikiSkill.voiceCashier, 6);
    }
    if (hasAny(['today', 'daily']) ||
        hasAll(['sales', 'summary']) ||
        normalized.contains('how are sales')) {
      addScore(PikiSkill.todaysSummary, 4);
    }
    if (hasAll(['sales', 'report']) ||
        hasAll(['recent', 'sales']) ||
        hasAll(['sales', 'history']) ||
        hasAll(['show', 'sales']) ||
        hasAll(['list', 'sales'])) {
      addScore(PikiSkill.salesReport, 4);
    }
    if (hasAny(['profit', 'margin', 'earnings']) ||
        hasAll(['how', 'much', 'made'])) {
      addScore(PikiSkill.profitSummary, 4);
    }
    if (hasAny(['shift', 'cashier summary', 'cash up'])) {
      addScore(PikiSkill.shiftSummary, 3);
    }
    if (hasAny(['expiry', 'expiring', 'expired', 'shelf life'])) {
      addScore(PikiSkill.expiryCheck, 4);
    }
    if (hasAll(['top', 'debtor']) ||
        hasAll(['who', 'owes']) ||
        hasAll(['outstanding', 'balance']) ||
        hasAll(['overdue', 'customer']) ||
        hasAll(['credit', 'customer']) ||
        hasAll(['kopesha', 'balance'])) {
      addScore(PikiSkill.topDebtors, 5);
    }
    if (hasAll(['top', 'product']) ||
        hasAll(['best', 'seller']) ||
        hasAll(['best', 'selling']) ||
        hasAll(['top', 'selling']) ||
        hasAll(['most', 'sold']) ||
        hasAll(['popular', 'product'])) {
      addScore(PikiSkill.topProducts, 5);
    }
    if (hasAny(['expense', 'expenses', 'spending', 'expenditure']) ||
        hasAll(['operating', 'cost'])) {
      addScore(PikiSkill.expenseSummary, 4);
    }
    if (hasAny(['purchase', 'purchases']) ||
        hasAll(['stock', 'received']) ||
        hasAll(['stock', 'in']) ||
        hasAll(['supplier', 'order']) ||
        hasAll(['restock', 'history'])) {
      addScore(PikiSkill.purchaseHistory, 4);
    }
    if (productQuery != null ||
        hasAll(['find', 'product']) ||
        hasAll(['search', 'product']) ||
        hasAll(['show', 'product']) ||
        hasAll(['lookup', 'product']) ||
        hasAll(['tell', 'me']) && normalized.contains('product')) {
      addScore(PikiSkill.productSearch, productQuery != null ? 5 : 3);
    }

    final sortedSkills = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return PikiRequestAnalysis(
      originalInput: input.trim(),
      normalizedInput: normalized,
      skills: sortedSkills.map((entry) => entry.key).toList(),
      daysRange: daysRange,
      resultLimit: resultLimit,
      productQuery: productQuery,
      filter:
          _extractCustomerFilter(normalized) ??
          _extractCatalogOrderStatus(normalized),
    );
  }

  /// Match user input to one or more skills.
  static List<PikiSkill> matchSkills(String input) {
    final analyzed = analyzeRequest(input);
    if (analyzed.skills.isNotEmpty) {
      return analyzed.skills;
    }

    final lower = input.toLowerCase();
    final matched = <PikiSkill>[];
    for (final entry in _skillPatterns.entries) {
      for (final pattern in entry.value) {
        if (pattern.every((kw) => lower.contains(kw))) {
          if (!matched.contains(entry.key)) matched.add(entry.key);
          break;
        }
      }
    }
    return matched;
  }

  // ── Skill metadata ──────────────────────────────────────────────────────

  static String skillLabel(PikiSkill skill) => switch (skill) {
    PikiSkill.analyzeLowStock => 'Analyze Inventory',
    PikiSkill.todaysSummary => "Review Sales",
    PikiSkill.restockList => 'Prepare Restock',
    PikiSkill.salesReport => 'Compile Sales',
    PikiSkill.productSearch => 'Search Products',
    PikiSkill.profitSummary => 'Profit Summary',
    PikiSkill.shiftSummary => 'Shift Summary',
    PikiSkill.expiryCheck => 'Expiry Check',
    PikiSkill.topDebtors => 'Top Debtors',
    PikiSkill.topProducts => 'Top Products',
    PikiSkill.expenseSummary => 'Expense Summary',
    PikiSkill.purchaseHistory => 'Purchase History',
    PikiSkill.dailyBrief => 'Daily Market Brief',
    PikiSkill.predictiveRestock => 'Predict Restock',
    PikiSkill.anomalyAlerts => 'Anomaly Alerts',
    PikiSkill.customerFollowups => 'Customer Follow-ups',
    PikiSkill.dailyWhatsappReport => 'WhatsApp Report',
    PikiSkill.catalogOrders => 'Catalog Orders',
    PikiSkill.voiceCashier => 'Voice Cashier',
    PikiSkill.loyaltyOverview => 'Loyalty Overview',
    PikiSkill.giftCardOverview => 'Gift Card Overview',
    PikiSkill.promotionOverview => 'Promotion Overview',
    PikiSkill.rolesOverview => 'Roles Overview',
    PikiSkill.serialOverview => 'Serial & Warranty Overview',
    PikiSkill.stocktakeOverview => 'Stocktake Overview',
    PikiSkill.campaignOverview => 'Campaign Overview',
    PikiSkill.currencyOverview => 'Currency Overview',
    PikiSkill.wastageOverview => 'Wastage Overview',
    PikiSkill.restaurantOverview => 'Restaurant Overview',
    PikiSkill.attendanceOverview => 'Attendance Overview',
    PikiSkill.customerGroupsOverview => 'Customer Groups Overview',
    PikiSkill.purchaseApprovalsOverview => 'Purchase Approvals',
    PikiSkill.deliveryOverview => 'Delivery Overview',
    PikiSkill.businessIntelligence => 'Business Intelligence',
    PikiSkill.customerPortalOverview => 'Customer Portal Overview',
  };

  static String skillDescription(PikiSkill skill) => switch (skill) {
    PikiSkill.analyzeLowStock => 'Scanning stock levels across all items',
    PikiSkill.todaysSummary => 'Calculating sales and profit metrics',
    PikiSkill.restockList => 'Identifying low stock & reorder qty',
    PikiSkill.salesReport => 'Compiling recent sales data',
    PikiSkill.productSearch => 'Searching product catalog',
    PikiSkill.profitSummary => 'Calculating profit margins',
    PikiSkill.shiftSummary => 'Reviewing closed shifts',
    PikiSkill.expiryCheck => 'Checking product expiry dates',
    PikiSkill.topDebtors => 'Finding customers with highest balances',
    PikiSkill.topProducts => 'Ranking products by sales volume',
    PikiSkill.expenseSummary => 'Totalling recent operating expenses',
    PikiSkill.purchaseHistory => 'Reviewing recent stock-in records',
    PikiSkill.dailyBrief =>
      'Fetching daily market news and comparing performance',
    PikiSkill.predictiveRestock =>
      'Forecasting stock cover from sales velocity',
    PikiSkill.anomalyAlerts => 'Scanning sales, stock, debt, and shift risks',
    PikiSkill.customerFollowups => 'Preparing Kopesha reminder message drafts',
    PikiSkill.dailyWhatsappReport => 'Drafting an owner-ready daily update',
    PikiSkill.catalogOrders => 'Reviewing customer orders from catalog links',
    PikiSkill.voiceCashier => 'Showing supported hands-free sell commands',
    PikiSkill.loyaltyOverview => 'Reviewing loyalty rewards and point balances',
    PikiSkill.giftCardOverview =>
      'Reviewing active gift card value and expiries',
    PikiSkill.promotionOverview => 'Reviewing promotion activity and value',
    PikiSkill.rolesOverview => 'Reviewing roles and access coverage',
    PikiSkill.serialOverview => 'Reviewing serial statuses and warranty dates',
    PikiSkill.stocktakeOverview => 'Reviewing stocktake progress and variances',
    PikiSkill.campaignOverview => 'Reviewing SMS campaign outcomes',
    PikiSkill.currencyOverview => 'Reviewing the active exchange rate',
    PikiSkill.wastageOverview => 'Reviewing wastage quantities and cost',
    PikiSkill.restaurantOverview => 'Reviewing table and kitchen workload',
    PikiSkill.attendanceOverview => 'Reviewing active staff attendance',
    PikiSkill.customerGroupsOverview => 'Reviewing customer segments',
    PikiSkill.purchaseApprovalsOverview => 'Reviewing orders awaiting approval',
    PikiSkill.deliveryOverview => 'Reviewing active deliveries',
    PikiSkill.businessIntelligence =>
      'Reviewing forecast and retention metrics',
    PikiSkill.customerPortalOverview =>
      'Reviewing self-service portal coverage',
  };

  static IconData skillIcon(PikiSkill skill) => switch (skill) {
    PikiSkill.analyzeLowStock => Icons.search_rounded,
    PikiSkill.todaysSummary => Icons.bar_chart_rounded,
    PikiSkill.restockList => Icons.inventory_2_rounded,
    PikiSkill.salesReport => Icons.receipt_long_rounded,
    PikiSkill.productSearch => Icons.shopping_bag_rounded,
    PikiSkill.profitSummary => Icons.trending_up_rounded,
    PikiSkill.shiftSummary => Icons.timer_rounded,
    PikiSkill.expiryCheck => Icons.event_busy_rounded,
    PikiSkill.topDebtors => Icons.people_alt_rounded,
    PikiSkill.topProducts => Icons.leaderboard_rounded,
    PikiSkill.expenseSummary => Icons.money_off_rounded,
    PikiSkill.purchaseHistory => Icons.local_shipping_rounded,
    PikiSkill.dailyBrief => Icons.auto_awesome,
    PikiSkill.predictiveRestock => Icons.insights_rounded,
    PikiSkill.anomalyAlerts => Icons.notification_important_rounded,
    PikiSkill.customerFollowups => Icons.mark_chat_unread_rounded,
    PikiSkill.dailyWhatsappReport => Icons.chat_rounded,
    PikiSkill.catalogOrders => Icons.assignment_rounded,
    PikiSkill.voiceCashier => Icons.record_voice_over_rounded,
    PikiSkill.loyaltyOverview => Icons.loyalty_rounded,
    PikiSkill.giftCardOverview => Icons.card_giftcard_rounded,
    PikiSkill.promotionOverview => Icons.local_offer_rounded,
    PikiSkill.rolesOverview => Icons.admin_panel_settings_rounded,
    PikiSkill.serialOverview => Icons.qr_code_2_rounded,
    PikiSkill.stocktakeOverview => Icons.playlist_add_check_rounded,
    PikiSkill.campaignOverview => Icons.sms_rounded,
    PikiSkill.currencyOverview => Icons.currency_exchange_rounded,
    PikiSkill.wastageOverview => Icons.delete_sweep_rounded,
    PikiSkill.restaurantOverview => Icons.restaurant_rounded,
    PikiSkill.attendanceOverview => Icons.timer_rounded,
    PikiSkill.customerGroupsOverview => Icons.groups_rounded,
    PikiSkill.purchaseApprovalsOverview => Icons.approval_rounded,
    PikiSkill.deliveryOverview => Icons.local_shipping_rounded,
    PikiSkill.businessIntelligence => Icons.query_stats_rounded,
    PikiSkill.customerPortalOverview => Icons.account_circle_rounded,
  };

  /// Build PikiStep list for Plan mode.
  static List<PikiStep> buildSteps(List<PikiSkill> skills) => skills
      .map(
        (s) => PikiStep(
          label: skillLabel(s),
          description: skillDescription(s),
          icon: skillIcon(s),
        ),
      )
      .toList();

  // ── Execution ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> executeSkill(
    PikiSkill skill, {
    PikiRequestAnalysis? request,
  }) async {
    final currency = ShopSettings.currency;
    switch (skill) {
      case PikiSkill.analyzeLowStock:
        final items = await ProductRepository.getLowStock();
        final prioritized = List<Map<String, dynamic>>.from(items)
          ..sort((a, b) {
            final aGap =
                ((a['low_stock'] as num? ?? 0).toDouble() -
                        (a['stock'] as num? ?? 0).toDouble())
                    .toDouble();
            final bGap =
                ((b['low_stock'] as num? ?? 0).toDouble() -
                        (b['stock'] as num? ?? 0).toDouble())
                    .toDouble();
            return bGap.compareTo(aGap);
          });
        return {
          'type': 'low_stock',
          'items': prioritized,
          'count': prioritized.length,
          'summary': prioritized.isEmpty
              ? 'All products are well-stocked!'
              : 'Low stock found: ${prioritized.take(3).map((p) => p['name']).join(', ')}',
          'details': prioritized
              .take(5)
              .map((p) => '${p['name']}: ${p['stock']} ${p['unit'] ?? 'pcs'}')
              .toList(),
        };

      case PikiSkill.todaysSummary:
        final s = await _buildSalesSummary(daysRange: request?.daysRange ?? 1);
        final rev = (s['total_revenue'] as num? ?? 0).toDouble();
        final profit = (s['total_profit'] as num? ?? 0).toDouble();
        final sales = (s['total_sales'] as num? ?? 0).toInt();
        final averageSale = sales > 0 ? rev / sales : 0.0;
        return {
          'type': 'today_summary',
          'data': s,
          'summary':
              '${request?.periodLabel ?? 'Today'}: '
              '$sales sales, revenue $currency${rev.toStringAsFixed(0)}, '
              'profit $currency${profit.toStringAsFixed(0)}',
          'total_sales': s['total_sales'] ?? 0,
          'total_revenue': rev,
          'total_profit': profit,
          'average_sale': averageSale,
          'days_range': request?.daysRange ?? 1,
        };

      case PikiSkill.dailyBrief:
        return _buildDailyBrief(request: request);

      case PikiSkill.predictiveRestock:
        return _buildPredictiveRestock(
          daysRange: request?.daysRange ?? 30,
          limit: request?.resultLimit ?? 10,
        );

      case PikiSkill.anomalyAlerts:
        return _buildAnomalyAlerts(
          daysRange: request?.daysRange ?? 7,
          limit: request?.resultLimit ?? 10,
        );

      case PikiSkill.customerFollowups:
        return _buildCustomerFollowups(
          filter: request?.filter,
          limit: request?.resultLimit ?? 10,
        );

      case PikiSkill.dailyWhatsappReport:
        return _buildDailyWhatsappReport(daysRange: request?.daysRange ?? 1);

      case PikiSkill.catalogOrders:
        return _buildCatalogOrders(
          status: request?.filter,
          limit: request?.resultLimit ?? 10,
        );

      case PikiSkill.voiceCashier:
        return _buildVoiceCashierHelp();

      case PikiSkill.restockList:
        final items = await ProductRepository.getLowStock();
        final restock =
            items.map((p) {
              final cur = (p['stock'] as num? ?? 0).toDouble();
              final low = (p['low_stock'] as num? ?? 5).toDouble();
              final reorderQty = (low * 2 - cur).clamp(low, low * 3);
              return {
                ...p,
                'reorder_qty': reorderQty,
                'urgency_score': low <= 0 ? 0 : ((low - cur) / low),
              };
            }).toList()..sort(
              (a, b) => (b['urgency_score'] as num).compareTo(
                a['urgency_score'] as num,
              ),
            );
        return {
          'type': 'restock_list',
          'items': restock,
          'count': restock.length,
          'summary': restock.isEmpty
              ? 'No items need restocking'
              : 'Restock list created',
        };

      case PikiSkill.salesReport:
        final range = _dateRangeForDays(request?.daysRange ?? 7);
        final sales = await SaleRepository.getAll(
          startDate: range.start.toIso8601String(),
          endDate: range.end.toIso8601String(),
        );
        final limited = sales.take(request?.resultLimit ?? 10).toList();
        return {
          'type': 'sales_report',
          'items': limited,
          'total_count': sales.length,
          'days_range': request?.daysRange ?? 7,
          'summary':
              '${sales.length} sales found for ${periodLabelForDays(request?.daysRange ?? 7).toLowerCase()}',
        };

      case PikiSkill.productSearch:
        final query = request?.productQuery?.trim();
        List<Map<String, dynamic>> products = [];
        bool usedSemanticSearch = false;

        if (query != null && query.isNotEmpty) {
          products = await ProductRepository.search(query);

          if (products.isEmpty && OpenRouterService.isEnabled) {
            try {
              final categories = await CategoryRepository.getAll();
              final catNames = categories.map((c) => c['name']).join(', ');

              final prompt =
                  '''
The user is searching for a product in a point-of-sale system.
Their natural language search query is: "$query".
Available product categories: $catNames.
Analyze their intent and provide a list of up to 5 single-word or short-phrase synonyms, categories, or keywords that would likely match the product name or brand in the database.
Return ONLY a valid JSON array of strings. Do not return any other text.
Example: ["detergent", "soap", "laundry"]
''';
              final aiResponse = await OpenRouterService.chat(
                messages: [
                  {'role': 'user', 'content': prompt},
                ],
                includeBusinessContext: false,
              );

              final List<dynamic> keywords = jsonDecode(aiResponse);
              final Set<String> matchedIds = {};

              for (final kw in keywords) {
                final kwStr = kw.toString().trim();
                if (kwStr.isNotEmpty) {
                  final matches = await ProductRepository.search(kwStr);
                  for (final m in matches) {
                    if (!matchedIds.contains(m['id'])) {
                      matchedIds.add(m['id']);
                      products.add(m);
                    }
                  }
                }
              }
              usedSemanticSearch = products.isNotEmpty;
            } catch (_) {
              // Fallback to empty if AI fails
            }
          }
        } else {
          products = await ProductRepository.getAll();
        }

        final limited = products.take(request?.resultLimit ?? 10).toList();
        return {
          'type': 'product_list',
          'items': limited,
          'count': products.length,
          'searched_query': query,
          'used_semantic_search': usedSemanticSearch,
          'details': limited
              .take(6)
              .map(
                (p) =>
                    '${p['name']}: ${((p['image_url'] as String?)?.trim().isNotEmpty ?? false) ? 'has image' : 'missing image'}',
              )
              .toList(),
          'summary': query != null && query.isNotEmpty
              ? products.isEmpty
                    ? 'No products found for "$query"'
                    : '${products.length} product matches for "$query"${usedSemanticSearch ? ' (via AI)' : ''}'
              : '${products.length} products in catalog',
        };

      case PikiSkill.profitSummary:
        final s = await _buildSalesSummary(daysRange: request?.daysRange ?? 1);
        final profit = (s['total_profit'] as num? ?? 0).toDouble();
        final revenue = (s['total_revenue'] as num? ?? 0).toDouble();
        return {
          'type': 'profit_summary',
          'data': s,
          'summary':
              '${request?.periodLabel ?? 'Today'} profit: $currency${profit.toStringAsFixed(2)}',
          'total_profit': profit,
          'total_revenue': revenue,
          'days_range': request?.daysRange ?? 1,
        };

      case PikiSkill.shiftSummary:
        try {
          final shifts = await ShiftRepository.getClosedShifts(limit: 5);
          return {
            'type': 'shift_summary',
            'items': shifts,
            'count': shifts.length,
            'summary': shifts.isEmpty
                ? 'No closed shifts found'
                : '${shifts.length} recent closed shifts',
          };
        } catch (_) {
          return {
            'type': 'shift_summary',
            'items': <Map<String, dynamic>>[],
            'count': 0,
            'summary': 'No shift data available',
          };
        }

      case PikiSkill.expiryCheck:
        final alerts = await ProductRepository.getExpiryAlerts();
        return {
          'type': 'expiry_check',
          'items': alerts,
          'count': alerts.length,
          'summary': alerts.isEmpty
              ? 'No expiring products found'
              : '${alerts.length} products expiring soon',
          'details': alerts
              .take(5)
              .map((b) => '${b['product_name']}: ${b['days_to_expiry']} days')
              .toList(),
        };

      case PikiSkill.topDebtors:
        final debtors = await ReportRepository.getTopDebtors(
          limit: request?.resultLimit ?? 10,
        );
        final totalOwed = debtors.fold<double>(
          0,
          (sum, d) => sum + (d['balance'] as num? ?? 0).toDouble(),
        );
        final currency = ShopSettings.currency;
        return {
          'type': 'top_debtors',
          'items': debtors,
          'count': debtors.length,
          'total_owed': totalOwed,
          'summary': debtors.isEmpty
              ? 'No outstanding Kopesha balances'
              : '${debtors.length} customers owe $currency${totalOwed.toStringAsFixed(2)}',
        };

      case PikiSkill.topProducts:
        final products = await ReportRepository.getTopProducts(
          daysRange: request?.daysRange ?? 30,
          limit: request?.resultLimit ?? 8,
        );
        return {
          'type': 'top_products',
          'items': products,
          'count': products.length,
          'days_range': request?.daysRange ?? 30,
          'summary': products.isEmpty
              ? 'No sales data in ${periodLabelForDays(request?.daysRange ?? 30).toLowerCase()}'
              : 'Top ${products.length} products by sales volume '
                    '(${periodLabelForDays(request?.daysRange ?? 30).toLowerCase()})',
        };

      case PikiSkill.expenseSummary:
        final expenses = await ExpenseRepository.getRecentExpenses(
          daysRange: request?.daysRange ?? 30,
          limit: request?.resultLimit ?? 20,
        );
        final totalAmount = expenses.fold<double>(
          0,
          (sum, e) => sum + (e['amount'] as num? ?? 0).toDouble(),
        );
        final cur = ShopSettings.currency;
        return {
          'type': 'expense_summary',
          'items': expenses,
          'count': expenses.length,
          'total_amount': totalAmount,
          'days_range': request?.daysRange ?? 30,
          'summary': expenses.isEmpty
              ? 'No expenses recorded in ${periodLabelForDays(request?.daysRange ?? 30).toLowerCase()}'
              : '${expenses.length} expenses totalling $cur${totalAmount.toStringAsFixed(2)}',
        };

      case PikiSkill.purchaseHistory:
        final rows = await DatabaseService.rawQuery(
          '''
          SELECT
            pb.id,
            p.name as product_name,
            pb.quantity_received,
            p.stock_unit,
            p.unit,
            pb.unit_cost as cost_per_unit,
            pb.received_at,
            pi.supplier_name
          FROM stock_batches pb
          JOIN products p ON p.id = pb.product_id
          LEFT JOIN purchase_invoices pi ON pi.id = pb.purchase_id
          WHERE pb.deleted_at IS NULL
            AND COALESCE(pb.branch_id, ?) = ?
          ORDER BY pb.received_at DESC
          LIMIT ${request?.resultLimit ?? 10}
        ''',
          [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
        );
        return {
          'type': 'purchase_history',
          'items': rows,
          'count': rows.length,
          'summary': rows.isEmpty
              ? 'No recent purchases recorded'
              : '${rows.length} recent stock-in records',
        };

      case PikiSkill.loyaltyOverview:
      case PikiSkill.giftCardOverview:
      case PikiSkill.promotionOverview:
      case PikiSkill.rolesOverview:
      case PikiSkill.serialOverview:
      case PikiSkill.stocktakeOverview:
      case PikiSkill.campaignOverview:
      case PikiSkill.currencyOverview:
      case PikiSkill.wastageOverview:
      case PikiSkill.restaurantOverview:
      case PikiSkill.attendanceOverview:
      case PikiSkill.customerGroupsOverview:
      case PikiSkill.purchaseApprovalsOverview:
      case PikiSkill.deliveryOverview:
      case PikiSkill.businessIntelligence:
      case PikiSkill.customerPortalOverview:
        return _buildModuleOverview(
          skill,
          daysRange: request?.daysRange ?? 30,
          limit: request?.resultLimit ?? 10,
        );
    }
  }

  static Future<Map<String, dynamic>> _buildModuleOverview(
    PikiSkill skill, {
    required int daysRange,
    required int limit,
  }) async {
    final safeLimit = limit.clamp(1, 50).toInt();
    final branchArgs = <dynamic>[
      DatabaseService.defaultBranchId,
      DatabaseService.currentBranchId,
    ];
    final currency = ShopSettings.currency;

    switch (skill) {
      case PikiSkill.loyaltyOverview:
        final rules = await DatabaseService.rawQuery(
          'SELECT * FROM loyalty_rules WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY updated_at DESC LIMIT 1',
          branchArgs,
        );
        final customers = await DatabaseService.rawQuery(
          'SELECT name, loyalty_points FROM customers WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? AND COALESCE(loyalty_points, 0) > 0 ORDER BY loyalty_points DESC LIMIT $safeLimit',
          branchArgs,
        );
        return {
          'type': 'loyalty_overview',
          'rules': rules.isEmpty ? null : rules.first,
          'items': customers,
          'count': customers.length,
          'summary': rules.isEmpty
              ? 'Loyalty rewards are not configured for this branch.'
              : '${customers.length} customer${customers.length == 1 ? '' : 's'} currently have loyalty points.',
        };

      case PikiSkill.giftCardOverview:
        final cards = await DatabaseService.rawQuery(
          'SELECT code, balance, currency, expires_at FROM gift_cards WHERE deleted_at IS NULL AND is_active = 1 AND COALESCE(branch_id, ?) = ? ORDER BY balance DESC LIMIT $safeLimit',
          branchArgs,
        );
        final total = cards.fold<double>(
          0,
          (sum, row) => sum + ((row['balance'] as num?)?.toDouble() ?? 0),
        );
        return {
          'type': 'gift_card_overview',
          'items': cards,
          'count': cards.length,
          'total_balance': total,
          'summary': cards.isEmpty
              ? 'There are no active gift cards.'
              : '${cards.length} active gift cards hold $currency${total.toStringAsFixed(2)}.',
        };

      case PikiSkill.promotionOverview:
        final promotions = await DatabaseService.rawQuery(
          'SELECT name, promotion_type, discount_type, discount_value, ends_at FROM promotions WHERE deleted_at IS NULL AND is_active = 1 AND COALESCE(branch_id, ?) = ? ORDER BY priority DESC, updated_at DESC LIMIT $safeLimit',
          branchArgs,
        );
        return {
          'type': 'promotion_overview',
          'items': promotions,
          'count': promotions.length,
          'summary': promotions.isEmpty
              ? 'No active promotions are running.'
              : '${promotions.length} active promotion${promotions.length == 1 ? '' : 's'} found.',
        };

      case PikiSkill.rolesOverview:
        final roles = await DatabaseService.rawQuery(
          'SELECT name, base_role, is_active, description FROM custom_roles WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY name LIMIT $safeLimit',
          branchArgs,
        );
        return {
          'type': 'roles_overview',
          'items': roles,
          'count': roles.length,
          'summary': roles.isEmpty
              ? 'No custom roles are configured.'
              : '${roles.length} custom role${roles.length == 1 ? '' : 's'} configured.',
        };

      case PikiSkill.serialOverview:
        final statuses = await DatabaseService.rawQuery(
          'SELECT status, COUNT(*) AS count FROM product_serials WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? GROUP BY status ORDER BY count DESC',
          branchArgs,
        );
        final warranty = await DatabaseService.rawQuery(
          "SELECT serial_number, warranty_expires_at FROM product_serials WHERE deleted_at IS NULL AND warranty_expires_at IS NOT NULL AND date(warranty_expires_at) <= date('now', '+60 days') AND COALESCE(branch_id, ?) = ? ORDER BY warranty_expires_at ASC LIMIT $safeLimit",
          branchArgs,
        );
        return {
          'type': 'serial_overview',
          'items': statuses,
          'warranty_watch': warranty,
          'count': statuses.fold<int>(
            0,
            (sum, row) => sum + ((row['count'] as num?)?.toInt() ?? 0),
          ),
          'summary': warranty.isEmpty
              ? 'Serial stock is healthy with no warranties expiring in 60 days.'
              : '${warranty.length} serial warranty${warranty.length == 1 ? '' : 'ies'} need attention within 60 days.',
        };

      case PikiSkill.stocktakeOverview:
        final sessions = await DatabaseService.rawQuery(
          'SELECT name, status, started_at, completed_at FROM stocktake_sessions WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY updated_at DESC LIMIT $safeLimit',
          branchArgs,
        );
        final variances = await DatabaseService.rawQuery(
          'SELECT product_name, variance_qty, unit FROM stocktake_items WHERE deleted_at IS NULL AND status != \'matched\' AND COALESCE(variance_qty, 0) != 0 AND COALESCE(branch_id, ?) = ? ORDER BY ABS(variance_qty) DESC LIMIT $safeLimit',
          branchArgs,
        );
        return {
          'type': 'stocktake_overview',
          'items': sessions,
          'variances': variances,
          'count': sessions.length,
          'summary': sessions.isEmpty
              ? 'No stocktake sessions have been created.'
              : '${sessions.length} stocktake session${sessions.length == 1 ? '' : 's'} and ${variances.length} unresolved variances found.',
        };

      case PikiSkill.campaignOverview:
        final campaigns = await DatabaseService.rawQuery(
          'SELECT name, segment, status, recipient_count, sent_count, failed_count, sent_at FROM sms_campaigns WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY updated_at DESC LIMIT $safeLimit',
          branchArgs,
        );
        return {
          'type': 'campaign_overview',
          'items': campaigns,
          'count': campaigns.length,
          'summary': campaigns.isEmpty
              ? 'No SMS campaigns have been created.'
              : '${campaigns.length} SMS campaign${campaigns.length == 1 ? '' : 's'} available for review.',
        };

      case PikiSkill.currencyOverview:
        final rates = await DatabaseService.rawQuery(
          'SELECT base_currency, quote_currency, rate, updated_at FROM exchange_rates WHERE deleted_at IS NULL AND is_active = 1 AND COALESCE(branch_id, ?) = ? ORDER BY updated_at DESC LIMIT 1',
          branchArgs,
        );
        final rate = rates.isEmpty ? null : rates.first;
        return {
          'type': 'currency_overview',
          'items': rates,
          'count': rates.length,
          'summary': rate == null
              ? 'No secondary currency exchange rate is active.'
              : '${rate['base_currency']} → ${rate['quote_currency']} is active at ${rate['rate']}.',
        };

      case PikiSkill.wastageOverview:
        final logs = await DatabaseService.rawQuery(
          "SELECT product_name, quantity, unit, unit_cost, reason, recorded_at FROM wastage_logs WHERE deleted_at IS NULL AND recorded_at >= datetime('now', ?) AND COALESCE(branch_id, ?) = ? ORDER BY recorded_at DESC LIMIT $safeLimit",
          ['-${daysRange.clamp(1, 365)} days', ...branchArgs],
        );
        final cost = logs.fold<double>(
          0,
          (sum, row) =>
              sum +
              ((row['quantity'] as num?)?.toDouble() ?? 0) *
                  ((row['unit_cost'] as num?)?.toDouble() ?? 0),
        );
        return {
          'type': 'wastage_overview',
          'items': logs,
          'count': logs.length,
          'estimated_cost': cost,
          'summary': logs.isEmpty
              ? 'No wastage has been recorded in the selected period.'
              : '${logs.length} wastage record${logs.length == 1 ? '' : 's'} total about $currency${cost.toStringAsFixed(2)}.',
        };

      case PikiSkill.restaurantOverview:
        final tables = await DatabaseService.rawQuery(
          'SELECT name, area, seats, status FROM restaurant_tables WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY area, name LIMIT $safeLimit',
          branchArgs,
        );
        final orders = await DatabaseService.rawQuery(
          'SELECT order_no, status, guest_count, total, opened_at FROM table_orders WHERE deleted_at IS NULL AND status != \'closed\' AND COALESCE(branch_id, ?) = ? ORDER BY opened_at ASC LIMIT $safeLimit',
          branchArgs,
        );
        return {
          'type': 'restaurant_overview',
          'items': tables,
          'open_orders': orders,
          'count': tables.length,
          'summary':
              '${tables.length} table${tables.length == 1 ? '' : 's'} configured with ${orders.length} open order${orders.length == 1 ? '' : 's'}.',
        };

      case PikiSkill.attendanceOverview:
        final attendance = await DatabaseService.rawQuery(
          'SELECT user_name, status, clock_in_at, clock_out_at FROM employee_attendance WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY clock_in_at DESC LIMIT $safeLimit',
          branchArgs,
        );
        final active = attendance
            .where((row) => row['status'] == 'open')
            .length;
        return {
          'type': 'attendance_overview',
          'items': attendance,
          'count': attendance.length,
          'active_count': active,
          'summary':
              '$active employee${active == 1 ? '' : 's'} currently clocked in.',
        };

      case PikiSkill.customerGroupsOverview:
        final groups = await DatabaseService.rawQuery(
          'SELECT g.name, g.description, COUNT(m.id) AS member_count FROM customer_groups g LEFT JOIN customer_group_members m ON m.group_id = g.id AND m.deleted_at IS NULL WHERE g.deleted_at IS NULL AND COALESCE(g.branch_id, ?) = ? GROUP BY g.id ORDER BY member_count DESC, g.name LIMIT $safeLimit',
          branchArgs,
        );
        return {
          'type': 'customer_groups_overview',
          'items': groups,
          'count': groups.length,
          'summary': groups.isEmpty
              ? 'No customer groups are configured.'
              : '${groups.length} customer segment${groups.length == 1 ? '' : 's'} available.',
        };

      case PikiSkill.purchaseApprovalsOverview:
        final orders = await DatabaseService.rawQuery(
          'SELECT order_number, supplier_name, total_amount, submitted_at FROM purchase_orders WHERE deleted_at IS NULL AND status = \'pending_approval\' AND COALESCE(branch_id, ?) = ? ORDER BY submitted_at ASC LIMIT $safeLimit',
          branchArgs,
        );
        final total = orders.fold<double>(
          0,
          (sum, row) => sum + ((row['total_amount'] as num?)?.toDouble() ?? 0),
        );
        return {
          'type': 'purchase_approvals_overview',
          'items': orders,
          'count': orders.length,
          'total_amount': total,
          'summary': orders.isEmpty
              ? 'There are no purchase orders awaiting approval.'
              : '${orders.length} purchase order${orders.length == 1 ? '' : 's'} await approval, worth $currency${total.toStringAsFixed(2)}.',
        };

      case PikiSkill.deliveryOverview:
        final deliveries = await DatabaseService.rawQuery(
          'SELECT tracking_code, status, rider_name, scheduled_at, delivered_at FROM deliveries WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY updated_at DESC LIMIT $safeLimit',
          branchArgs,
        );
        return {
          'type': 'delivery_overview',
          'items': deliveries,
          'count': deliveries.length,
          'summary': deliveries.isEmpty
              ? 'There are no deliveries to track.'
              : '${deliveries.length} delivery record${deliveries.length == 1 ? '' : 's'} available for review.',
        };

      case PikiSkill.businessIntelligence:
        final dashboard = await BiRepository.loadDashboard();
        if (dashboard == null) {
          return {
            'type': 'business_intelligence',
            'items': const <Map<String, dynamic>>[],
            'count': 0,
            'summary':
                'Business intelligence needs an online manager session to load cloud analytics.',
          };
        }
        return {
          'type': 'business_intelligence',
          'items': const <Map<String, dynamic>>[],
          'clv': dashboard.clv['summary'],
          'forecast': dashboard.forecast['summary'],
          'cohorts': dashboard.cohorts['cohorts'],
          'turnover': dashboard.turnover['summary'],
          'count': 1,
          'summary':
              'Loaded customer value, sales forecast, cohort retention, and employee turnover insights.',
        };

      case PikiSkill.customerPortalOverview:
        final coverage = await DatabaseService.rawQuery(
          'SELECT COUNT(*) AS customer_count, COUNT(CASE WHEN COALESCE(email, \'\') != \'\' THEN 1 END) AS email_ready_count, COALESCE(SUM(CASE WHEN COALESCE(email, \'\') != \'\' THEN balance ELSE 0 END), 0) AS email_ready_balance FROM customers WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
          branchArgs,
        );
        final values = coverage.isEmpty ? <String, dynamic>{} : coverage.first;
        final ready = (values['email_ready_count'] as num?)?.toInt() ?? 0;
        final total = (values['customer_count'] as num?)?.toInt() ?? 0;
        return {
          'type': 'customer_portal_overview',
          'items': coverage,
          'count': ready,
          'summary':
              '$ready of $total customers have an email and can use the self-service portal.',
        };

      default:
        throw StateError('Unsupported module overview: $skill');
    }
  }

  static PikiStep buildStepForTool(String tool) {
    final mappedSkill = _toolToSkill[tool];
    if (mappedSkill != null) {
      return PikiStep(
        label: skillLabel(mappedSkill),
        description: skillDescription(mappedSkill),
        icon: skillIcon(mappedSkill),
      );
    }
    return PikiStep(
      label: _toolLabels[tool] ?? tool,
      description: _toolDescriptions[tool] ?? 'Preparing a grounded response',
      icon: switch (tool) {
        toolPurchaseDraft => Icons.note_alt_rounded,
        toolEnhanceProductImage => Icons.auto_fix_high_rounded,
        toolImageOrderDraft => Icons.document_scanner_rounded,
        toolBuildStorefront => Icons.web_rounded,
        toolCustomizeCheckout => Icons.shopping_cart_checkout_rounded,
        toolSetupPaymentGateway => Icons.account_balance_wallet_rounded,
        toolWebSearch => Icons.public_rounded,
        _ => Icons.auto_awesome_rounded,
      },
    );
  }

  static Future<Map<String, dynamic>> executeAgentTool(
    String tool, {
    Map<String, dynamic>? args,
    Map<String, dynamic>? memory,
    // Conversation callers stage write tools before invoking the executor.
    // Keep direct service calls executable so diagnostics, tests, and other
    // trusted callers receive the actual tool result instead of a UI preview.
    bool confirmed = true,
  }) async {
    final safeArgs = args ?? const <String, dynamic>{};
    if (requiresConfirmation(tool) && !confirmed) {
      return buildWriteConfirmationPreview(tool, args: safeArgs);
    }
    final mappedSkill = _toolToSkill[tool];
    if (mappedSkill != null) {
      final request = PikiRequestAnalysis(
        originalInput: (args?['query'] as String?) ?? '',
        normalizedInput: ((args?['query'] as String?) ?? '').toLowerCase(),
        skills: [mappedSkill],
        daysRange: _coercePositiveInt(
          args?['daysRange'],
          _defaultDaysForTool(tool),
        ),
        resultLimit: _coercePositiveInt(
          args?['limit'],
          _defaultLimitForTool(tool),
        ),
        productQuery: (args?['query'] as String?)?.trim().isEmpty == true
            ? null
            : (args?['query'] as String?)?.trim(),
        filter: _stringArg(args ?? const <String, dynamic>{}, [
          'filter',
          'status',
        ]),
      );
      final result = await executeSkill(mappedSkill, request: request);
      return _enrichToolResult(
        tool,
        result,
        args: args ?? const <String, dynamic>{},
      );
    }

    switch (tool) {
      case toolPurchaseDraft:
        return _createPurchaseDraft(
          args: safeArgs,
          memory: memory ?? const <String, dynamic>{},
        );
      case toolCreateProduct:
        return _createProduct(safeArgs);
      case toolDraftProduct:
        return _draftProduct(safeArgs);
      case toolEnhanceProductImage:
        return _enhanceProductImage(safeArgs);
      case toolImageOrderDraft:
        return _imageOrderDraft(args ?? const <String, dynamic>{});
      case toolCreateService:
        return _createService(safeArgs);
      case toolEditProduct:
        return _editProduct(safeArgs);
      case toolDeleteProduct:
        return _deleteProduct(safeArgs);
      case toolAddVariant:
        return _addVariant(safeArgs);
      case toolRecordProductSale:
        return _recordProductSale(safeArgs);
      case toolRecordServiceSale:
        return _recordServiceSale(safeArgs);
      case toolCreateCategory:
        return _createCategory(safeArgs);
      case toolCreateExpenseCategory:
        return _createExpenseCategory(safeArgs);
      case toolCreateCustomer:
        return _createCustomer(safeArgs);
      case toolCreateSupplier:
        return _createSupplier(safeArgs);
      case toolReconcileStock:
        return _reconcileStock(safeArgs);
      case toolAddServiceField:
        return _addServiceField(safeArgs);
      case toolBuildStorefront:
        return _buildStorefront(safeArgs);
      case toolCustomerSearch:
        return _searchCustomers(safeArgs);
      case toolSupplierSearch:
        return _searchSuppliers(safeArgs);
      case toolWebSearch:
        return _webSearch(safeArgs);
      case toolCustomizeCheckout:
        return _customizeStorefrontCheckout(safeArgs);
      case toolSetupPaymentGateway:
        return _setupStorefrontPaymentGateway(safeArgs);
      default:
        throw Exception('Unknown agent tool: $tool');
    }
  }

  static String periodLabelForDays(int daysRange) {
    if (daysRange <= 1) return 'Today';
    if (daysRange == 7) return 'Last 7 days';
    if (daysRange == 30) return 'Last 30 days';
    return 'Last $daysRange days';
  }

  static bool isAdviceFollowUp(String input) {
    final lower = input.toLowerCase();
    return [
      'what should i do',
      'what do you recommend',
      'what next',
      'next step',
      'next steps',
      'what action should i take',
      'what action should we take',
      'give me advice',
      'give me recommendations',
      'what is your advice',
    ].any(lower.contains);
  }

  static String? buildFollowUpResponse(
    String input,
    Map<String, dynamic> result,
  ) {
    if (!isAdviceFollowUp(input)) {
      return null;
    }

    final type = result['type'] as String? ?? '';
    final recommendations =
        (result['recommendations'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    if (recommendations.isNotEmpty) {
      return 'Recommended next steps:\n'
          '${recommendations.take(4).map((step) => '• $step').join('\n')}';
    }

    switch (type) {
      case 'today_summary':
      case 'profit_summary':
        return 'Focus on three actions:\n'
            '• Check your top-selling items and keep them in stock.\n'
            '• Review low-margin or slow items before ordering more.\n'
            '• Compare today with the last 7 days for a stronger decision.';
      case 'product_list':
        return 'Next steps:\n'
            '• Open Products to review pricing and stock.\n'
            '• Search by barcode or SKU if the exact item is still unclear.\n'
            '• Use Sell Mode if you want to ring up one of these items.';
      default:
        return 'Next steps:\n'
            '• Open the related screen to review the full details.\n'
            '• Ask Piki for a focused follow-up like "show top products" or "create a restock list".';
    }
  }

  /// Generate a single-line insight from the first result.
  static Future<PikiInsightData> generateInsight(
    Map<String, dynamic> result,
  ) async {
    PikiInsightData fallbackInsight() {
      final type = result['type'] as String?;
      switch (type) {
        case 'low_stock':
          final items = result['items'] as List? ?? [];
          if (items.isEmpty) {
            return const PikiInsightData(
              text: 'Inventory is healthy — all items above minimum.',
            );
          }
          return PikiInsightData(
            text:
                '${items.first['name']} is the fastest-moving low-stock item today.',
          );
        case 'today_summary':
          final profit = (result['total_profit'] as num? ?? 0).toDouble();
          return PikiInsightData(
            text: profit > 0
                ? 'Good day so far — you\'re profitable.'
                : 'Sales are slow today. Consider a promotion.',
          );
        case 'restock_list':
          final count = result['count'] as int? ?? 0;
          return PikiInsightData(
            text: count == 0
                ? 'No restocking needed right now.'
                : '$count items queued for restocking.',
          );
        default:
          return const PikiInsightData(
            text: 'Analysis complete. Review the results above.',
          );
      }
    }

    if (!OpenRouterService.isEnabled) {
      return fallbackInsight();
    }

    try {
      final safeResult = Map<String, dynamic>.from(result);
      if (safeResult['items'] is List) {
        final list = safeResult['items'] as List;
        if (list.length > 10) {
          safeResult['items'] = list.take(10).toList();
        }
      }

      final shopName = ShopSettings.shopName;
      final currency = ShopSettings.currency;
      final prompt =
          '''
You are Piki, AI assistant for "$shopName" (currency: $currency).
Analyze the following POS tool result and provide a single, punchy, actionable business insight (max 1 short sentence).
Do not use markdown. Do not wrap in quotes.
Tool Result:
${jsonEncode(safeResult)}
''';
      final aiResponse = await OpenRouterService.chat(
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        includeBusinessContext: false,
      );

      final cleanText = aiResponse.trim().replaceAll('"', '');
      if (cleanText.isNotEmpty) {
        return PikiInsightData(text: cleanText);
      }
    } catch (_) {
      // Fallback below
    }

    return fallbackInsight();
  }

  static Future<Map<String, dynamic>> _buildDailyBrief({
    PikiRequestAnalysis? request,
  }) async {
    final s = await _buildSalesSummary(daysRange: request?.daysRange ?? 1);
    final rev = (s['total_revenue'] as num? ?? 0).toDouble();
    final profit = (s['total_profit'] as num? ?? 0).toDouble();
    final sales = (s['total_sales'] as num? ?? 0).toInt();

    final shopName = ShopSettings.shopName;
    final currency = ShopSettings.currency;
    final prompt =
        '''
You are Piki, the AI assistant for "$shopName".
Analyze today's POS business performance:
- Sales Count: $sales
- Revenue: $currency${rev.toStringAsFixed(2)}
- Profit: $currency${profit.toStringAsFixed(2)}
Write a short encouraging business brief (2-3 sentences) with one actionable recommendation for tomorrow.
Do not use markdown. Do not fabricate external market news or data you don't have.
''';
    String aiResponse;
    try {
      if (OpenRouterService.isEnabled) {
        aiResponse = await OpenRouterService.chat(
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          includeBusinessContext: false,
        );
      } else {
        throw Exception('AI is disabled');
      }
    } catch (e) {
      aiResponse =
          "Today you had $sales sales for $currency${rev.toStringAsFixed(2)} revenue. Keep up the momentum!";
    }

    return {
      'type': toolDailyBrief,
      'summary': aiResponse.trim().replaceAll('"', ''),
      'sales': sales,
      'revenue': rev,
      'profit': profit,
    };
  }

  static Future<Map<String, dynamic>> _buildPredictiveRestock({
    required int daysRange,
    required int limit,
  }) async {
    final safeDays = daysRange.clamp(3, 90).toInt();
    final range = _dateRangeForDays(safeDays);
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT
        p.id,
        p.name,
        p.stock,
        p.low_stock,
        p.unit,
        p.stock_unit,
        p.sale_unit,
        p.purchase_unit,
        p.price,
        p.cost,
        p.image_url,
        COALESCE(SUM(CASE WHEN s.id IS NOT NULL THEN si.quantity ELSE 0 END), 0) as total_qty_sold,
        COALESCE(SUM(CASE WHEN s.id IS NOT NULL THEN si.quantity * si.unit_price ELSE 0 END), 0) as total_revenue,
        MAX(s.created_at) as last_sold_at
      FROM products p
      LEFT JOIN sale_items si ON si.product_id = p.id
      LEFT JOIN sales s ON s.id = si.sale_id
        AND s.deleted_at IS NULL
        AND s.refund_for_sale_id IS NULL
        AND s.created_at >= ?
        AND s.created_at <= ?
        AND COALESCE(s.branch_id, ?) = ?
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(p.track_stock, 1) <> 0
      GROUP BY p.id
      ''',
      [
        range.start.toIso8601String(),
        range.end.toIso8601String(),
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );

    final forecastItems = <Map<String, dynamic>>[];
    for (final row in rows) {
      final sold = (row['total_qty_sold'] as num? ?? 0).toDouble();
      final stock = (row['stock'] as num? ?? 0).toDouble();
      final lowStock = (row['low_stock'] as num? ?? 0).toDouble();
      final avgDaily = sold / safeDays;
      final hasVelocity = avgDaily > 0.001;
      final daysCover = hasVelocity ? stock / avgDaily : null;
      final isLow = lowStock > 0 && stock <= lowStock;
      final shouldInclude =
          isLow || (daysCover != null && daysCover <= 14) || stock <= 0;
      if (!shouldInclude) continue;

      final targetByVelocity = hasVelocity ? avgDaily * 14 : lowStock * 2;
      final targetByThreshold = lowStock > 0 ? lowStock * 2 : targetByVelocity;
      final targetStock = targetByVelocity > targetByThreshold
          ? targetByVelocity
          : targetByThreshold;
      var recommendedQty = targetStock - stock;
      if (recommendedQty <= 0 && isLow) {
        recommendedQty = lowStock > stock ? lowStock - stock : 1;
      }
      if (recommendedQty <= 0) {
        recommendedQty = hasVelocity ? avgDaily * 7 : 1;
      }

      final urgency = stock <= 0
          ? 'critical'
          : daysCover != null && daysCover <= 3
          ? 'high'
          : isLow || (daysCover != null && daysCover <= 7)
          ? 'medium'
          : 'watch';
      final stockUnit =
          row['stock_unit'] as String? ??
          row['purchase_unit'] as String? ??
          row['unit'] as String? ??
          'pcs';

      forecastItems.add({
        ...row,
        'average_daily_sold': avgDaily,
        'days_of_cover': daysCover,
        'recommended_qty': recommendedQty.ceil(),
        'urgency': urgency,
        'unit': stockUnit,
        'forecast_reason': hasVelocity
            ? '${avgDaily.toStringAsFixed(1)} sold/day over $safeDays days'
            : 'Below stock threshold with no recent sales velocity',
      });
    }

    int urgencyRank(Map<String, dynamic> item) {
      return switch (item['urgency']) {
        'critical' => 0,
        'high' => 1,
        'medium' => 2,
        _ => 3,
      };
    }

    forecastItems.sort((a, b) {
      final urgencyCompare = urgencyRank(a).compareTo(urgencyRank(b));
      if (urgencyCompare != 0) return urgencyCompare;
      final aCover = (a['days_of_cover'] as num?)?.toDouble() ?? 9999;
      final bCover = (b['days_of_cover'] as num?)?.toDouble() ?? 9999;
      return aCover.compareTo(bCover);
    });

    final limited = forecastItems.take(limit.clamp(1, 20).toInt()).toList();
    return {
      'type': toolPredictiveRestock,
      'items': limited,
      'count': forecastItems.length,
      'days_range': safeDays,
      'summary': limited.isEmpty
          ? 'No urgent restock forecast found from the last $safeDays days.'
          : 'Forecasted ${limited.length} product(s) that may need restocking soon.',
      'details': limited.take(5).map((item) {
        final cover = (item['days_of_cover'] as num?)?.toDouble();
        final coverLabel = cover == null
            ? 'no recent velocity'
            : '${cover.toStringAsFixed(1)} days cover';
        return '${item['name']}: order ${item['recommended_qty']} ${item['unit']} ($coverLabel)';
      }).toList(),
    };
  }

  static Future<Map<String, dynamic>> _buildAnomalyAlerts({
    required int daysRange,
    required int limit,
  }) async {
    final safeDays = daysRange.clamp(3, 30).toInt();
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: safeDays - 1));
    final dailyRows = await DatabaseService.rawQuery(
      '''
      SELECT
        DATE(created_at) as sale_day,
        COUNT(*) as sale_count,
        COALESCE(SUM(total_amount), 0) as revenue
      FROM sales
      WHERE deleted_at IS NULL
        AND refund_for_sale_id IS NULL
        AND created_at >= ?
        AND COALESCE(branch_id, ?) = ?
      GROUP BY DATE(created_at)
      ORDER BY sale_day DESC
      ''',
      [
        start.toIso8601String(),
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );

    final alerts = <Map<String, dynamic>>[];
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    Map<String, dynamic>? todayRow;
    final previousRows = <Map<String, dynamic>>[];
    for (final row in dailyRows) {
      if (row['sale_day'] == todayKey) {
        todayRow = row;
      } else {
        previousRows.add(row);
      }
    }
    final todayRevenue = (todayRow?['revenue'] as num? ?? 0).toDouble();
    final todaySales = (todayRow?['sale_count'] as num? ?? 0).toInt();
    if (previousRows.isNotEmpty) {
      final avgRevenue =
          previousRows.fold<double>(
            0,
            (sum, row) => sum + (row['revenue'] as num? ?? 0).toDouble(),
          ) /
          previousRows.length;
      if (avgRevenue > 0 && todayRevenue < avgRevenue * 0.45) {
        alerts.add({
          'kind': 'sales_drop',
          'severity': 'high',
          'title': 'Sales are below the recent pattern',
          'body':
              'Today is at ${ShopSettings.currency}${todayRevenue.toStringAsFixed(2)} vs a recent daily average of ${ShopSettings.currency}${avgRevenue.toStringAsFixed(2)}.',
          'action_prompt': 'Show top products today and check missing stock.',
        });
      } else if (avgRevenue > 0 && todayRevenue > avgRevenue * 1.75) {
        alerts.add({
          'kind': 'sales_spike',
          'severity': 'info',
          'title': 'Sales are unusually strong',
          'body':
              'Today is at ${ShopSettings.currency}${todayRevenue.toStringAsFixed(2)}, well above the recent daily average.',
          'action_prompt': 'Check top products and protect stock for tomorrow.',
        });
      }
    } else if (todaySales == 0) {
      alerts.add({
        'kind': 'no_sales',
        'severity': 'medium',
        'title': 'No sales recorded today',
        'body': 'No sales are recorded for today yet.',
        'action_prompt': 'Confirm cashiers are using POS checkout.',
      });
    }

    final lowStock = await ProductRepository.getLowStock();
    if (lowStock.isNotEmpty) {
      alerts.add({
        'kind': 'low_stock',
        'severity': lowStock.length >= 5 ? 'high' : 'medium',
        'title': '${lowStock.length} low-stock item(s)',
        'body':
            'Top affected: ${lowStock.take(3).map((p) => p['name']).join(', ')}.',
        'action_prompt': 'Run predictive restock.',
      });
    }

    final expiryAlerts = await ProductRepository.getExpiryAlerts();
    if (expiryAlerts.isNotEmpty) {
      final expired = expiryAlerts
          .where((item) => (item['days_to_expiry'] as num? ?? 999).toInt() <= 0)
          .length;
      alerts.add({
        'kind': 'expiry_risk',
        'severity': expired > 0 ? 'high' : 'medium',
        'title': expired > 0
            ? '$expired expired batch(es)'
            : '${expiryAlerts.length} batch(es) expiring soon',
        'body':
            'Check ${expiryAlerts.take(3).map((b) => b['product_name']).join(', ')}.',
        'action_prompt': 'Open expiry check.',
      });
    }

    final overdue = await CustomerRepository.getKopeshaCustomers(
      filter: 'overdue',
    );
    if (overdue.isNotEmpty) {
      final amount = overdue.fold<double>(
        0,
        (sum, row) => sum + (row['overdue_amount'] as num? ?? 0).toDouble(),
      );
      alerts.add({
        'kind': 'customer_debt',
        'severity': amount >= 250 ? 'high' : 'medium',
        'title': '${overdue.length} overdue Kopesha customer(s)',
        'body':
            'Overdue amount totals ${ShopSettings.currency}${amount.toStringAsFixed(2)}.',
        'action_prompt': 'Prepare customer follow-ups.',
      });
    }

    try {
      final threshold = now.subtract(const Duration(hours: 12));
      final openShifts = await DatabaseService.rawQuery(
        '''
        SELECT id, cashier_name, opened_at
        FROM shifts
        WHERE deleted_at IS NULL
          AND LOWER(status) = 'open'
          AND opened_at <= ?
          AND COALESCE(branch_id, ?) = ?
        ORDER BY opened_at ASC
        LIMIT 5
        ''',
        [
          threshold.toIso8601String(),
          DatabaseService.defaultBranchId,
          DatabaseService.currentBranchId,
        ],
      );
      if (openShifts.isNotEmpty) {
        alerts.add({
          'kind': 'open_shift',
          'severity': 'medium',
          'title': '${openShifts.length} shift(s) open over 12 hours',
          'body':
              'Oldest open shift: ${openShifts.first['cashier_name'] ?? 'Cashier'}.',
          'action_prompt': 'Review shifts and close the drawer if needed.',
        });
      }
    } catch (_) {
      // Some older local databases may not have shift tracking enabled.
    }

    int severityRank(Map<String, dynamic> item) {
      return switch (item['severity']) {
        'high' => 0,
        'medium' => 1,
        'info' => 2,
        _ => 3,
      };
    }

    alerts.sort((a, b) => severityRank(a).compareTo(severityRank(b)));
    final limited = alerts.take(limit.clamp(1, 20).toInt()).toList();
    return {
      'type': toolAnomalyAlerts,
      'items': limited,
      'count': alerts.length,
      'days_range': safeDays,
      'summary': limited.isEmpty
          ? 'No major anomaly alerts found right now.'
          : 'Found ${limited.length} business alert(s) to review.',
      'details': limited
          .take(5)
          .map((item) => '${item['title']}: ${item['action_prompt']}')
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> _buildCustomerFollowups({
    String? filter,
    required int limit,
  }) async {
    final safeFilter = _normalizeKopeshaFilter(filter);
    final rows = await CustomerRepository.getKopeshaCustomers(
      filter: safeFilter,
    );
    final currency = ShopSettings.currency;
    final items = rows.take(limit.clamp(1, 20).toInt()).map((customer) {
      final balance =
          (customer['outstanding_balance'] as num? ??
                  customer['balance'] as num? ??
                  0)
              .toDouble();
      final dueDate =
          (customer['oldest_overdue_date'] as String?) ??
          (customer['next_due_date'] as String?);
      final message = MessagingService.balanceReminder(
        customerName: customer['name'] as String? ?? 'Customer',
        balance: '$currency${balance.toStringAsFixed(2)}',
        dueDate: dueDate,
      );
      return {
        'customer_id': customer['id'],
        'name': customer['name'],
        'phone': customer['phone'],
        'email': customer['email'],
        'outstanding_balance': balance,
        'overdue_amount': (customer['overdue_amount'] as num? ?? 0).toDouble(),
        'due_today_amount': (customer['due_today_amount'] as num? ?? 0)
            .toDouble(),
        'due_date': dueDate,
        'message': message,
        'channel': 'whatsapp',
      };
    }).toList();

    final total = items.fold<double>(
      0,
      (sum, item) =>
          sum + (item['outstanding_balance'] as num? ?? 0).toDouble(),
    );
    return {
      'type': toolCustomerFollowups,
      'items': items,
      'count': rows.length,
      'filter': safeFilter,
      'total_outstanding': total,
      'summary': items.isEmpty
          ? 'No Kopesha customers matched $safeFilter for follow-up.'
          : 'Prepared ${items.length} customer follow-up message draft(s).',
      'details': items
          .take(5)
          .map(
            (item) =>
                '${item['name']}: ${ShopSettings.currency}${(item['outstanding_balance'] as num).toStringAsFixed(2)}',
          )
          .toList(),
    };
  }

  static Future<Map<String, dynamic>> _buildDailyWhatsappReport({
    required int daysRange,
  }) async {
    final safeDays = daysRange.clamp(1, 30).toInt();
    final sales = await _buildSalesSummary(daysRange: safeDays);
    final topProducts = await ReportRepository.getTopProducts(
      daysRange: safeDays,
      limit: 3,
    );
    final restock = await _buildPredictiveRestock(daysRange: 30, limit: 3);
    final anomalies = await _buildAnomalyAlerts(daysRange: 7, limit: 3);
    final debtors = await CustomerRepository.getKopeshaCustomers(
      filter: 'overdue',
    );

    final revenue = (sales['total_revenue'] as num? ?? 0).toDouble();
    final profit = (sales['total_profit'] as num? ?? 0).toDouble();
    final count = (sales['total_sales'] as num? ?? 0).toInt();
    final currency = ShopSettings.currency;
    final period = periodLabelForDays(safeDays);

    String joinNames(List<Map<String, dynamic>> rows, String key) {
      if (rows.isEmpty) return 'None';
      return rows
          .take(3)
          .map((row) => row[key] as String? ?? row['name'] as String? ?? 'Item')
          .join(', ');
    }

    final restockItems =
        (restock['items'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    final anomalyItems =
        (anomalies['items'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    final message =
        '''
Piki Daily Report - ${ShopSettings.shopName}
Period: $period
Sales: $count transactions
Revenue: $currency${revenue.toStringAsFixed(2)}
Profit: $currency${profit.toStringAsFixed(2)}
Top products: ${joinNames(topProducts, 'product_name')}
Restock watch: ${joinNames(restockItems, 'name')}
Alerts: ${joinNames(anomalyItems, 'title')}
Overdue Kopesha customers: ${debtors.length}
Next action: Review alerts, follow up overdue customers, and restock fast movers.
'''
            .trim();

    return {
      'type': toolDailyWhatsappReport,
      'success': true,
      'channel': 'whatsapp',
      'message': message,
      'days_range': safeDays,
      'summary': 'Drafted a WhatsApp-ready daily owner report.',
      'details': message.split('\n'),
    };
  }

  static Future<Map<String, dynamic>> _buildCatalogOrders({
    required String? status,
    required int limit,
  }) async {
    final normalizedStatus = _normalizeCatalogOrderStatus(status);
    final safeLimit = limit.clamp(1, 50).toInt();
    final orders = await CatalogOrderService.fetchOrders(
      status: normalizedStatus,
    );
    final limited = orders.take(safeLimit).toList();
    final totalValue = orders.fold<double>(
      0,
      (sum, order) => sum + order.subtotal,
    );
    final counts = <String, int>{};
    for (final order in orders) {
      counts[order.status] = (counts[order.status] ?? 0) + 1;
    }
    final currency = ShopSettings.currency;
    final statusLabel = _catalogOrderStatusLabel(normalizedStatus);

    return {
      'type': toolCatalogOrders,
      'items': limited.map(_catalogOrderToMap).toList(),
      'count': orders.length,
      'status_filter': normalizedStatus,
      'status_counts': counts,
      'total_value': totalValue,
      'summary': orders.isEmpty
          ? 'No $statusLabel catalog orders found.'
          : '${orders.length} $statusLabel catalog order${orders.length == 1 ? '' : 's'} worth $currency${totalValue.toStringAsFixed(2)}.',
      'details': limited
          .take(6)
          .map(
            (order) =>
                '#${order.orderNumber}: ${order.customerName} - $currency${order.subtotal.toStringAsFixed(2)} (${_catalogOrderStatusLabel(order.status)})',
          )
          .toList(),
    };
  }

  static Map<String, dynamic> _catalogOrderToMap(CatalogOrder order) {
    return {
      'id': order.id,
      'order_number': order.orderNumber,
      'customer_name': order.customerName,
      'phone': order.phone,
      'delivery_address': order.deliveryAddress,
      'note': order.note,
      'status': order.status,
      'subtotal': order.subtotal,
      'item_count': order.itemCount,
      'created_at': order.createdAt?.toIso8601String(),
      'items': order.items
          .map(
            (item) => {
              'product_id': item.productId,
              'variant_id': item.variantId,
              'product_name': item.productName,
              'variant_name': item.variantName,
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              'line_total': item.lineTotal,
            },
          )
          .toList(),
    };
  }

  static String _catalogOrderStatusLabel(String status) {
    return switch (status) {
      'accepted' => 'accepted',
      'completed' => 'completed',
      'cancelled' => 'cancelled',
      'all' => 'all',
      _ => 'pending',
    };
  }

  static Map<String, dynamic> _buildVoiceCashierHelp() {
    final commands = [
      'Say "sell two breads" or "add milk" to add items to the cart.',
      'Say "remove milk", "same again", or "make sugar 3" to adjust the cart.',
      'Say "checkout" to move to payment or "hold sale" to park the cart.',
      'Use the microphone or auto-listen control on the POS screen for hands-free selling.',
    ];
    return {
      'type': toolVoiceCashierHelp,
      'items': commands
          .map((command) => {'name': command, 'command': command})
          .toList(),
      'summary': 'Voice cashier is available in Sell Mode on the POS screen.',
      'details': commands,
    };
  }

  static _PikiDateRange _dateRangeForDays(int daysRange) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: daysRange - 1));
    return _PikiDateRange(start: start, end: end);
  }

  static Future<Map<String, dynamic>> _buildSalesSummary({
    required int daysRange,
  }) async {
    final range = _dateRangeForDays(daysRange);
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT
        COUNT(*) as total_sales,
        COALESCE(SUM(s.total_amount), 0) as total_revenue,
        COALESCE(SUM(s.tax), 0) as total_tax,
        COALESCE(SUM(s.discount), 0) as total_discount,
        COALESCE(SUM(
          COALESCE((
            SELECT SUM(si.quantity * (si.unit_price - si.unit_cost))
            FROM sale_items si
            WHERE si.sale_id = s.id
          ), 0)
          + COALESCE((
            SELECT SUM(ssi.quantity * ssi.unit_price)
            FROM service_sale_items ssi
            WHERE ssi.sale_id = s.id
          ), 0)
          - COALESCE(s.discount, 0)
        ), 0) as total_profit
      FROM sales s
      WHERE s.deleted_at IS NULL
        AND s.refund_for_sale_id IS NULL
        AND s.created_at >= ?
        AND s.created_at <= ?
        AND COALESCE(s.branch_id, ?) = ?
      ''',
      [
        range.start.toIso8601String(),
        range.end.toIso8601String(),
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );
    return rows.isNotEmpty
        ? rows.first
        : {
            'total_sales': 0,
            'total_revenue': 0.0,
            'total_tax': 0.0,
            'total_discount': 0.0,
            'total_profit': 0.0,
          };
  }

  static int _extractDaysRange(String input) {
    if (input.contains('today')) return 1;
    if (input.contains('yesterday')) return 2;
    if (input.contains('this week') || input.contains('weekly')) return 7;
    if (input.contains('this month') || input.contains('monthly')) return 30;
    final explicitRange = RegExp(
      r'(?:last|past)\s+(\d{1,3})\s+(day|days|week|weeks|month|months)',
    ).firstMatch(input);
    if (explicitRange != null) {
      final count = int.tryParse(explicitRange.group(1) ?? '') ?? 1;
      final unit = explicitRange.group(2) ?? 'days';
      if (unit.startsWith('week')) return count * 7;
      if (unit.startsWith('month')) return count * 30;
      return count;
    }
    if (input.contains('30 day') || input.contains('30-day')) return 30;
    if (input.contains('7 day') || input.contains('7-day')) return 7;
    return 1;
  }

  static int _extractResultLimit(String input) {
    final match = RegExp(
      r'\b(?:top|show|list|find)\s+(\d{1,2})\b',
    ).firstMatch(input);
    final value = int.tryParse(match?.group(1) ?? '') ?? 10;
    return value.clamp(1, 20);
  }

  static String? _extractProductQuery(String input) {
    final patterns = [
      RegExp(
        r'^\s*(?:find|search|lookup|look up|show|check)\s+(?:product\s+)?(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'^\s*(?:tell me about|details for)\s+(.+)$',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input.trim());
      if (match != null) {
        final candidate = match.group(1)?.trim() ?? '';
        if (candidate.isNotEmpty &&
            !candidate.contains('sales') &&
            !candidate.contains('profit')) {
          return candidate;
        }
      }
    }
    return null;
  }

  // ─── Sell Mode NLP helpers ───────────────────────────────────────────────

  static String? _extractCustomerFilter(String input) {
    if (input.contains('due today')) return 'due_today';
    if (input.contains('risky') || input.contains('risk')) return 'risky';
    if (input.contains('overdue') || input.contains('late')) return 'overdue';
    if (input.contains('all customer') || input.contains('all kopesha')) {
      return 'all';
    }
    return null;
  }

  static String? _extractCatalogOrderStatus(String input) {
    if (input.contains('accepted') || input.contains('accept')) {
      return 'accepted';
    }
    if (input.contains('completed') || input.contains('complete')) {
      return 'completed';
    }
    if (input.contains('cancelled') || input.contains('canceled')) {
      return 'cancelled';
    }
    if (input.contains('all order') || input.contains('all oder')) {
      return 'all';
    }
    if (input.contains('pending') ||
        input.contains('new order') ||
        input.contains('new oder')) {
      return 'pending';
    }
    return null;
  }

  static String _normalizeCatalogOrderStatus(String? status) {
    final normalized = status?.trim().toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'accepted' || 'accept' => 'accepted',
      'completed' || 'complete' || 'done' => 'completed',
      'cancelled' || 'canceled' || 'cancel' => 'cancelled',
      'all' => 'all',
      _ => 'pending',
    };
  }

  static String _normalizeKopeshaFilter(String? filter) {
    final normalized = filter?.trim().toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'due' || 'due_today' || 'today' => 'due_today',
      'risky' || 'risk' => 'risky',
      'all' => 'all',
      _ => 'overdue',
    };
  }

  /// Parses a sell-mode utterance into a qty + product-query pair.
  /// Returns null when the text is a cart-control command, not an add request.
  static ({double qty, String query})? parseSellIntent(String text) {
    if (isClearCartCommand(text) || isCheckoutCommand(text)) return null;

    final lower = text.trim().toLowerCase();

    // "sell/add/ring up/give me/scan {qty} {product}"
    final verbQtyProduct = RegExp(
      r'^(?:sell|add|ring\s+up|give\s+me|scan|get)\s+(\d+(?:\.\d+)?)\s+(.+)$',
    );
    // "{product} x {qty}"
    final productXQty = RegExp(r'^(.+?)\s+x\s*(\d+(?:\.\d+)?)$');
    // "{qty} {product}"
    final qtyProduct = RegExp(r'^(\d+(?:\.\d+)?)\s+(.+)$');
    // "sell/add/etc {product}" (qty implied 1)
    final verbProduct = RegExp(
      r'^(?:sell|add|ring\s+up|give\s+me|scan|get)\s+(.+)$',
    );

    Match? m;

    m = verbQtyProduct.firstMatch(lower);
    if (m != null) {
      return (qty: double.parse(m.group(1)!), query: m.group(2)!.trim());
    }

    m = productXQty.firstMatch(lower);
    if (m != null) {
      return (qty: double.parse(m.group(2)!), query: m.group(1)!.trim());
    }

    m = qtyProduct.firstMatch(lower);
    if (m != null) {
      return (qty: double.parse(m.group(1)!), query: m.group(2)!.trim());
    }

    m = verbProduct.firstMatch(lower);
    if (m != null) {
      return (qty: 1.0, query: m.group(1)!.trim());
    }

    // Bare product name (no qty, no verb) — assume qty 1
    if (lower.isNotEmpty) {
      return (qty: 1.0, query: text.trim());
    }

    return null;
  }

  static bool isClearCartCommand(String text) {
    final lower = text.toLowerCase();
    return const [
      'clear cart',
      'empty cart',
      'remove all',
      'clear all',
      'reset cart',
      'cancel cart',
    ].any(lower.contains);
  }

  static bool isCheckoutCommand(String text) {
    final lower = text.toLowerCase();
    return const [
      'checkout',
      'check out',
      'go to pos',
      'process sale',
      'pay now',
      'complete sale',
      'done selling',
      'finish sale',
    ].any(lower.contains);
  }

  /// Fuzzy product search: matches name, barcode, or SKU.
  static Future<Map<String, dynamic>?> findProductForSale(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;

    final rows = await DatabaseService.rawQuery(
      '''
      SELECT * FROM products
      WHERE (LOWER(name) LIKE ? OR barcode = ? OR LOWER(sku) LIKE ?)
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY
        CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
        LENGTH(name) ASC
      LIMIT 1
      ''',
      [
        '%$q%',
        q,
        '%$q%',
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        q,
      ],
    );

    if (rows.isNotEmpty) return rows.first;

    if (OpenRouterService.isEnabled) {
      try {
        final categories = await CategoryRepository.getAll();
        final catNames = categories.map((c) => c['name']).join(', ');

        final prompt =
            '''
The user wants to find or sell a product in a point-of-sale system.
Their natural language query, misspelling, or local term is: "$query".
Available product categories: $catNames.
Analyze their intent (including Swahili or local language translations, misspellings, or general categories) and provide a list of up to 5 single-word or short-phrase synonyms or correctly spelled keywords that would likely match the English product name or brand in the database.
Return ONLY a valid JSON array of strings. Do not return any other text.
Example for "unga": ["flour", "maize", "baking"]
''';
        final aiResponse = await OpenRouterService.chat(
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          includeBusinessContext: false,
        );

        final List<dynamic> keywords = jsonDecode(aiResponse);
        for (final kw in keywords) {
          final kwStr = kw.toString().trim().toLowerCase();
          if (kwStr.isNotEmpty) {
            final fallbackRows = await DatabaseService.rawQuery(
              '''
              SELECT * FROM products
              WHERE (LOWER(name) LIKE ? OR barcode = ? OR LOWER(sku) LIKE ?)
                AND deleted_at IS NULL
                AND COALESCE(branch_id, ?) = ?
              ORDER BY
                CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
                LENGTH(name) ASC
              LIMIT 1
              ''',
              [
                '%$kwStr%',
                kwStr,
                '%$kwStr%',
                DatabaseService.defaultBranchId,
                DatabaseService.currentBranchId,
                kwStr,
              ],
            );
            if (fallbackRows.isNotEmpty) return fallbackRows.first;
          }
        }
      } catch (e, st) {
        debugPrint('PikiAgentService: product lookup failed: $e\n$st');
      }
    }

    return null;
  }

  static Future<PikiSellableProduct?> findSellableProductForSale(
    String query, {
    Map<String, String> aliases = const <String, String>{},
  }) async {
    final q = _resolveAlias(query, aliases).trim().toLowerCase();
    if (q.isEmpty) return null;

    final variantRows = await DatabaseService.rawQuery(
      '''
      SELECT
        p.*,
        pv.id AS matched_variant_id,
        pv.name AS matched_variant_name,
        pv.sku AS matched_variant_sku,
        pv.barcode AS matched_variant_barcode,
        pv.price AS matched_variant_price,
        pv.cost AS matched_variant_cost,
        pv.stock AS matched_variant_stock,
        pv.low_stock AS matched_variant_low_stock
      FROM products p
      JOIN product_variants pv
        ON pv.product_id = p.id
       AND pv.deleted_at IS NULL
       AND COALESCE(pv.branch_id, ?) = ?
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND (
          LOWER(p.name || ' ' || pv.name) LIKE ?
          OR LOWER(pv.name) LIKE ?
          OR LOWER(COALESCE(pv.sku, '')) LIKE ?
          OR pv.barcode = ?
        )
      ORDER BY
        CASE
          WHEN LOWER(p.name || ' ' || pv.name) = ? THEN 0
          WHEN LOWER(pv.name) = ? THEN 1
          ELSE 2
        END,
        LENGTH(p.name || pv.name) ASC
      LIMIT 1
      ''',
      [
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        '%$q%',
        '%$q%',
        '%$q%',
        q,
        q,
        q,
      ],
    );
    if (variantRows.isNotEmpty) {
      return _sellableFromVariantSearchRow(variantRows.first);
    }

    final rows = await ProductRepository.searchForPos(q);
    if (rows.isNotEmpty) {
      final row = rows.first;
      if (row['result_type'] == 'variant') {
        return _sellableFromVariantSearchRow(row);
      }
      return PikiSellableProduct(product: row);
    }

    final product = await findProductForSale(q);
    return product == null ? null : PikiSellableProduct(product: product);
  }

  static String resolveSaleAlias(String query, Map<String, String> aliases) {
    return _resolveAlias(query, aliases);
  }

  static PikiSellableProduct _sellableFromVariantSearchRow(
    Map<String, dynamic> row,
  ) {
    return PikiSellableProduct(
      product: row,
      variant: {
        'id': row['matched_variant_id'],
        'product_id': row['id'],
        'branch_id': row['branch_id'],
        'business_id': row['business_id'],
        'name': row['matched_variant_name'],
        'sku': row['matched_variant_sku'],
        'barcode': row['matched_variant_barcode'],
        'price': row['matched_variant_price'],
        'cost': row['matched_variant_cost'],
        'stock': row['matched_variant_stock'],
        'low_stock': row['matched_variant_low_stock'],
      },
    );
  }

  static String _resolveAlias(String query, Map<String, String> aliases) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || aliases.isEmpty) {
      return normalized;
    }
    return aliases[normalized]?.trim().toLowerCase() ?? normalized;
  }

  /// Fuzzy service search: matches name or category.
  static Future<Map<String, dynamic>?> findServiceForSale(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;

    final rows = await DatabaseService.rawQuery(
      '''
      SELECT * FROM services
      WHERE (LOWER(name) LIKE ? OR LOWER(category) LIKE ?)
        AND deleted_at IS NULL
        AND is_active = 1
        AND COALESCE(branch_id, ?) = ?
      ORDER BY
        CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
        LENGTH(name) ASC
      LIMIT 1
      ''',
      [
        '%$q%',
        '%$q%',
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        q,
      ],
    );

    if (rows.isNotEmpty) return rows.first;

    if (OpenRouterService.isEnabled) {
      try {
        final categoriesRows = await DatabaseService.rawQuery(
          'SELECT DISTINCT category FROM services WHERE category IS NOT NULL',
        );
        final catNames = categoriesRows.map((c) => c['category']).join(', ');

        final prompt =
            '''
The user wants to find or sell a service in a point-of-sale system.
Their natural language query, misspelling, or local term is: "$query".
Available service categories: $catNames.
Analyze their intent (including Swahili or local language translations, misspellings, or general categories) and provide a list of up to 5 single-word or short-phrase synonyms or correctly spelled keywords that would likely match the English service name in the database.
Return ONLY a valid JSON array of strings. Do not return any other text.
Example for "kinyozi": ["haircut", "barber", "shave"]
''';
        final aiResponse = await OpenRouterService.chat(
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          includeBusinessContext: false,
        );

        final List<dynamic> keywords = jsonDecode(aiResponse);
        for (final kw in keywords) {
          final kwStr = kw.toString().trim().toLowerCase();
          if (kwStr.isNotEmpty) {
            final fallbackRows = await DatabaseService.rawQuery(
              '''
              SELECT * FROM services
              WHERE (LOWER(name) LIKE ? OR LOWER(category) LIKE ?)
                AND deleted_at IS NULL
                AND is_active = 1
                AND COALESCE(branch_id, ?) = ?
              ORDER BY
                CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
                LENGTH(name) ASC
              LIMIT 1
              ''',
              [
                '%$kwStr%',
                '%$kwStr%',
                DatabaseService.defaultBranchId,
                DatabaseService.currentBranchId,
                kwStr,
              ],
            );
            if (fallbackRows.isNotEmpty) return fallbackRows.first;
          }
        }
      } catch (e, st) {
        debugPrint('PikiAgentService: service lookup failed: $e\n$st');
      }
    }

    return null;
  }

  static int _defaultDaysForTool(String tool) {
    return switch (tool) {
      toolSalesReport => 7,
      toolTopProducts => 30,
      toolExpenseSummary => 30,
      toolPurchaseHistory => 30,
      toolPredictiveRestock => 30,
      toolAnomalyAlerts => 7,
      _ => 1,
    };
  }

  static int _defaultLimitForTool(String tool) {
    return switch (tool) {
      toolExpenseSummary => 20,
      toolTopProducts => 8,
      toolPurchaseHistory => 10,
      toolPredictiveRestock => 10,
      toolAnomalyAlerts => 10,
      toolCustomerFollowups => 10,
      _ => 10,
    };
  }

  static int _coercePositiveInt(dynamic value, int fallback) {
    final parsed = switch (value) {
      int _ => value,
      num _ => value.toInt(),
      String _ => int.tryParse(value),
      _ => null,
    };
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }

  static String? _stringArg(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      final value = args[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static String _requiredStringArg(
    Map<String, dynamic> args,
    List<String> keys,
    String label,
  ) {
    final value = _stringArg(args, keys);
    if (value == null) {
      throw Exception('$label is required');
    }
    return value;
  }

  static double? _doubleArg(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      final value = args[key];
      if (value == null) continue;
      if (value is num) return value.toDouble();
      final cleaned = value
          .toString()
          .replaceAll(',', '')
          .replaceAll(RegExp(r'[^0-9.\-]'), '')
          .trim();
      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static double _requiredPositiveDoubleArg(
    Map<String, dynamic> args,
    List<String> keys,
    String label,
  ) {
    final value = _doubleArg(args, keys);
    if (value == null || value <= 0) {
      throw Exception('$label must be greater than zero');
    }
    return value;
  }

  static double _nonNegativeDoubleArg(
    Map<String, dynamic> args,
    List<String> keys,
    double fallback,
  ) {
    final value = _doubleArg(args, keys);
    return value == null || value < 0 ? fallback : value;
  }

  static int? _intArg(Map<String, dynamic> args, List<String> keys) {
    final value = _doubleArg(args, keys);
    return value?.toInt();
  }

  static bool _boolArg(
    Map<String, dynamic> args,
    List<String> keys, {
    bool fallback = false,
  }) {
    for (final key in keys) {
      final value = args[key];
      if (value == null) continue;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final text = value.toString().trim().toLowerCase();
      if (['true', 'yes', 'y', '1', 'required'].contains(text)) return true;
      if (['false', 'no', 'n', '0', 'optional'].contains(text)) return false;
    }
    return fallback;
  }

  static List<String> _stringListArg(
    Map<String, dynamic> args,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = args[key];
      if (value == null) continue;
      if (value is List) {
        return value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      return text
          .split(RegExp(r'[,|]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  static String _paymentTypeArg(Map<String, dynamic> args) {
    final raw = _stringArg(args, ['payment_type', 'paymentType', 'payment']);
    final normalized = raw?.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    return switch (normalized) {
      'card' || 'credit_card' || 'debit_card' => 'card',
      'mobile' || 'mobile_money' || 'mpesa' || 'm_pesa' => 'mobile_money',
      'kopesha' || 'credit' => 'kopesha',
      _ => 'cash',
    };
  }

  static String _currentUserId() => SessionService.currentUserId.isNotEmpty
      ? SessionService.currentUserId
      : 'admin';

  static Future<String?> _resolveProductCategoryId(
    Map<String, dynamic> args,
  ) async {
    final categoryId = _stringArg(args, ['category_id', 'categoryId']);
    if (categoryId != null) return categoryId;

    final categoryName = _stringArg(args, ['category', 'category_name']);
    if (categoryName == null) return null;
    final categories = await CategoryRepository.getAll();
    final normalized = categoryName.toLowerCase();
    for (final category in categories) {
      if ((category['name'] as String? ?? '').trim().toLowerCase() ==
          normalized) {
        return category['id'] as String?;
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _findService(String query) async {
    final services = await ServiceRepository.getServices(
      activeOnly: true,
      query: query,
    );
    if (services.isEmpty) return null;
    final normalized = query.trim().toLowerCase();
    for (final service in services) {
      if ((service['name'] as String? ?? '').trim().toLowerCase() ==
          normalized) {
        return service;
      }
    }
    return services.first;
  }

  static Future<Map<String, dynamic>> _createProduct(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'product_name',
    ], 'Product name');
    final price = _requiredPositiveDoubleArg(args, [
      'price',
      'unit_price',
      'selling_price',
    ], 'Product price');
    final cost = _doubleArg(args, ['cost', 'unit_cost']);
    final stock = _nonNegativeDoubleArg(args, ['stock', 'initial_stock'], 0);
    final lowStock = _nonNegativeDoubleArg(args, ['low_stock', 'lowStock'], 5);
    final unit = _stringArg(args, ['unit', 'sale_unit']) ?? 'pcs';
    final categoryId = await _resolveProductCategoryId(args);
    final id = await ProductRepository.create(
      name: name,
      price: price,
      cost: cost,
      brand: _stringArg(args, ['brand']),
      sku: _stringArg(args, ['sku']),
      barcode: _stringArg(args, ['barcode']),
      stock: stock,
      lowStock: lowStock,
      unit: unit,
      stockUnit: _stringArg(args, ['stock_unit', 'stockUnit']),
      saleUnit: _stringArg(args, ['sale_unit', 'saleUnit']),
      purchaseUnit: _stringArg(args, ['purchase_unit', 'purchaseUnit']),
      categoryId: categoryId,
      trackStock: _boolArg(args, ['track_stock', 'trackStock'], fallback: true),
    );

    return _enrichToolResult(toolCreateProduct, {
      'type': toolCreateProduct,
      'success': true,
      'id': id,
      'name': name,
      'price': price,
      'stock': stock,
      'summary':
          'Created product "$name" at ${ShopSettings.currency}${price.toStringAsFixed(2)}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _draftProduct(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'product_name',
    ], 'Product name');
    final price = _requiredPositiveDoubleArg(args, [
      'price',
      'unit_price',
      'selling_price',
    ], 'Product price');
    final imageUrl = _stringArg(args, ['image_url', 'imageUrl']);
    final cost = _doubleArg(args, ['cost', 'unit_cost']);
    final stock = _nonNegativeDoubleArg(args, ['stock', 'initial_stock'], 0);

    return _enrichToolResult(toolDraftProduct, {
      'type': toolDraftProduct,
      'success': true,
      'name': name,
      'price': price,
      'cost': cost,
      'stock': stock,
      'image_url': imageUrl,
      'draft_args': args,
      'summary': 'Drafted product "$name" for user review.',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _enhanceProductImage(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'query',
      'product_name',
      'name',
    ], 'Product query');
    final product = await findProductForSale(query);
    if (product == null) {
      throw Exception('Could not find product matching "$query".');
    }

    final imageSource = (product['image_url'] as String?)?.trim();
    if (imageSource == null || imageSource.isEmpty) {
      throw Exception(
        'Product "${product['name']}" does not have an image yet. Add or capture a product image first.',
      );
    }

    final enhancedPath = await OpenRouterService.enhanceProductImage(
      imageSource: imageSource,
      productName: product['name'] as String? ?? query,
      prompt: _stringArg(args, ['prompt', 'instruction', 'description']),
    );

    await ProductRepository.update(product['id'] as String, {
      'image_url': enhancedPath,
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    });

    return _enrichToolResult(toolEnhanceProductImage, {
      'type': toolEnhanceProductImage,
      'success': true,
      'product_id': product['id'],
      'name': product['name'],
      'image_url': enhancedPath,
      'image_model': OpenRouterService.imageModelName,
      'summary':
          'Enhanced product image for "${product['name']}" using ${OpenRouterService.imageModelName}.',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _imageOrderDraft(
    Map<String, dynamic> args,
  ) async {
    final imageSource = _requiredStringArg(args, [
      'image_source',
      'image_url',
      'imageUrl',
      'url',
      'path',
    ], 'Image source');
    final result = await OpenRouterService.analyzeOrderImage(
      imageSource: imageSource,
      note: _stringArg(args, ['note', 'prompt', 'instruction']),
    );
    final items =
        (result['items'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    return _enrichToolResult(toolImageOrderDraft, {
      'type': toolImageOrderDraft,
      'success': true,
      'items': items,
      'confidence': result['confidence'],
      'raw': result['raw'],
      'summary':
          result['summary'] as String? ??
          (items.isEmpty
              ? 'No clear item lines were detected in the image.'
              : 'Drafted ${items.length} item line(s) from the image.'),
      'details': items.take(5).map((item) {
        final qty = item['quantity'];
        final unit = item['unit'];
        final name = item['name'] ?? 'Item';
        final qtyLabel = qty == null ? '' : '$qty ';
        final unitLabel = unit == null ? '' : '$unit ';
        return '$qtyLabel$unitLabel$name'.trim();
      }).toList(),
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createService(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'service_name',
    ], 'Service name');
    final price = _requiredPositiveDoubleArg(args, [
      'price',
      'base_price',
      'unit_price',
    ], 'Service price');
    final id = await ServiceRepository.createService(
      name: name,
      category: _stringArg(args, ['category']),
      description: _stringArg(args, ['description', 'note']),
      basePrice: price,
      durationMinutes: _intArg(args, ['duration_minutes', 'duration']),
      isActive: true,
    );

    return _enrichToolResult(toolCreateService, {
      'type': toolCreateService,
      'success': true,
      'id': id,
      'name': name,
      'price': price,
      'summary':
          'Created service "$name" at ${ShopSettings.currency}${price.toStringAsFixed(2)}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _buildStorefront(
    Map<String, dynamic> args,
  ) async {
    final storefrontType = _requiredStorefrontType(args);
    final existing = await StorefrontBrandService.fetchSettings();
    final businessName =
        _stringArg(args, ['business_name', 'name', 'store_name']) ??
        existing.businessName;
    final tagline =
        _stringArg(args, ['tagline', 'headline']) ?? existing.tagline;
    final description =
        _stringArg(args, ['description', 'intro', 'copy']) ??
        existing.description;
    final primaryColor = _storefrontThemeColor(args, existing.primaryColor);
    final saved = await StorefrontBrandService.saveSettings(
      StorefrontBrandSettings(
        businessId: existing.businessId,
        businessName: businessName,
        branchId: existing.branchId,
        logoUrl: existing.logoUrl,
        coverUrl: existing.coverUrl,
        coverUrls: existing.coverUrls,
        primaryColor: primaryColor,
        tagline: tagline,
        description: description,
        updatedAt: existing.updatedAt,
      ),
    );

    final themeName =
        _stringArg(args, ['theme_name']) ?? '${saved.businessName} theme';
    final designChanges = _storefrontDesignChanges(
      args,
      accentColor: primaryColor,
    );
    final checkoutChanges = _storefrontCheckoutChanges(args);
    final themeDraft = await StorefrontThemeService.create(
      branchId: saved.branchId,
      storefrontType: storefrontType.apiValue,
      name: themeName,
      preset: _storefrontPreset(args),
      design: designChanges,
      checkout: checkoutChanges.isEmpty ? null : checkoutChanges,
      source: 'ai',
    );
    final shouldPublish =
        !args.containsKey('publish') || _boolArg(args, ['publish']);
    final storefrontTheme = shouldPublish
        ? await StorefrontThemeService.publish(themeDraft.id)
        : themeDraft;

    final makeMain = _boolArg(args, ['make_main', 'set_main']);
    if (makeMain) {
      await CatalogShareService.setPrimaryStorefront(storefrontType);
    }

    String? url;
    try {
      final links = await CatalogShareService.prepare(syncBeforeShare: false);
      final isAvailable = links.storefronts.any(
        (link) => link.type == storefrontType,
      );
      if (!isAvailable) {
        throw Exception(
          '${storefrontType.label} is not included in this plan.',
        );
      }
      url = storefrontType == links.primaryStorefrontType
          ? links.mainUrl
          : links.selectStorefront(storefrontType).url;
    } catch (_) {
      // Publishing the storefront has succeeded even if the link refresh is
      // temporarily unavailable, so do not turn a successful save into a failure.
    }

    final capabilities = switch (storefrontType) {
      CatalogStorefrontType.retail => const [
        'product catalogue',
        'variants and cart',
        'online order tracking',
      ],
      CatalogStorefrontType.services => const [
        'service catalogue',
        'booking requests',
        'online booking tracking',
      ],
      CatalogStorefrontType.restaurant => const [
        'restaurant menu',
        'customer orders',
        'kitchen-ready order flow',
      ],
    };
    return _enrichToolResult(toolBuildStorefront, {
      'type': toolBuildStorefront,
      'success': true,
      'storefront_type': storefrontType.apiValue,
      'business_name': saved.businessName,
      'tagline': saved.tagline,
      'primary_color': saved.primaryColor,
      'is_main': makeMain,
      'url': url,
      'features': capabilities,
      'theme_id': storefrontTheme.id,
      'theme_name': storefrontTheme.name,
      'theme_published': storefrontTheme.isPublished,
      'summary': shouldPublish
          ? '${storefrontType.label} website for "${saved.businessName}" was published${makeMain ? ' as the main business website' : ''}${url == null ? '.' : ': $url'}'
          : '${storefrontType.label} website theme for "${saved.businessName}" was saved as a draft for preview.',
    }, args: args);
  }

  static CatalogStorefrontType _requiredStorefrontType(
    Map<String, dynamic> args,
  ) {
    final type = CatalogStorefrontTypeDetails.fromApiValue(
      _stringArg(args, ['storefront_type', 'module', 'website_type', 'type']),
    );
    if (type == null) {
      throw Exception(
        'Choose retail, services, or restaurant for the website.',
      );
    }
    return type;
  }

  static String _storefrontThemeColor(
    Map<String, dynamic> args,
    String fallback,
  ) {
    final requested = _stringArg(args, ['primary_color', 'color']);
    final normalized = requested?.trim().startsWith('#') == true
        ? requested!.trim()
        : requested == null
        ? null
        : '#${requested.trim()}';
    if (normalized != null &&
        RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(normalized)) {
      return normalized.toLowerCase();
    }
    switch (_stringArg(args, ['theme'])?.toLowerCase()) {
      case 'warm':
        return '#c65d36';
      case 'fresh':
        return '#0f9f8e';
      case 'elegant':
        return '#7357d6';
      case 'bold':
        return '#e23d6f';
      case 'dark':
        return '#d19a28';
      case 'modern':
        return '#2563eb';
      default:
        return fallback;
    }
  }

  static Future<Map<String, dynamic>> _customizeStorefrontCheckout(
    Map<String, dynamic> args,
  ) async {
    final storefrontType = _requiredStorefrontType(args);
    final brand = await StorefrontBrandService.fetchSettings();
    final collection = await StorefrontThemeService.list(
      branchId: brand.branchId,
      storefrontType: storefrontType.apiValue,
    );
    final requestedThemeId = _stringArg(args, ['theme_id']);
    StorefrontTheme? selected;
    if (requestedThemeId != null) {
      for (final theme in collection.themes) {
        if (theme.id == requestedThemeId) {
          selected = theme;
          break;
        }
      }
      if (selected == null) {
        throw Exception('The selected storefront theme was not found.');
      }
    } else {
      for (final theme in collection.themes) {
        if (theme.isPublished) {
          selected = theme;
          break;
        }
      }
      selected ??= collection.themes.isEmpty ? null : collection.themes.first;
    }

    selected ??= await StorefrontThemeService.create(
      branchId: brand.branchId,
      storefrontType: storefrontType.apiValue,
      name: '${brand.businessName} checkout',
      preset: 'studio',
      source: 'ai',
    );
    final draft = selected.isPublished
        ? await StorefrontThemeService.duplicate(
            selected.id,
            name: '${selected.name} checkout draft',
            source: 'ai',
          )
        : selected;
    final checkout = _storefrontCheckoutChanges(args, draft.checkout);
    if (checkout.isEmpty) {
      throw Exception('Describe at least one checkout setting to change.');
    }
    final updated = await StorefrontThemeService.update(draft.id, {
      'checkout': checkout,
      'source': 'ai',
    });
    final shouldPublish = _boolArg(args, ['publish']);
    final result = shouldPublish
        ? await StorefrontThemeService.publish(updated.id)
        : updated;
    return _enrichToolResult(toolCustomizeCheckout, {
      'type': toolCustomizeCheckout,
      'success': true,
      'theme_id': result.id,
      'theme_name': result.name,
      'storefront_type': result.storefrontType,
      'published': result.isPublished,
      'payment_methods': result.checkout.paymentMethods,
      'fulfillment_methods': result.checkout.fulfillmentMethods,
      'summary': result.isPublished
          ? 'Published the customized checkout for ${storefrontType.label}.'
          : 'Created a checkout draft for ${storefrontType.label}. Preview it, then publish when ready.',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _setupStorefrontPaymentGateway(
    Map<String, dynamic> args,
  ) async {
    final provider = (_stringArg(args, ['provider']) ?? 'mpesa')
        .trim()
        .toLowerCase();
    if (provider != 'mpesa') {
      throw Exception('Piki currently supports secure setup for M-Pesa only.');
    }
    final existing = await PosPaymentService.fetchBusinessMpesaSettings();
    final credentialsReady = const [
      'consumerKey',
      'consumerSecret',
      'passkey',
    ].every((key) => (existing.secretConfig[key]?.toString() ?? '').isNotEmpty);
    final hasEnableArgument =
        args.containsKey('enable') || args.containsKey('is_active');
    final requestedEnabled = hasEnableArgument
        ? _boolArg(args, ['enable', 'is_active'])
        : existing.isActive;
    final shortcode =
        _stringArg(args, ['shortcode', 'till', 'paybill']) ??
        existing.publicConfig['shortcode']?.toString() ??
        '';
    if (shortcode.trim().isEmpty) {
      throw Exception('Add the M-Pesa Till or PayBill number.');
    }
    final transactionType =
        _stringArg(args, ['transaction_type']) ??
        existing.publicConfig['transactionType']?.toString() ??
        'CustomerPayBillOnline';
    final accountReference =
        _stringArg(args, ['account_reference']) ??
        existing.publicConfig['accountReference']?.toString() ??
        'PikiPOS';
    final configured = await PosPaymentService.configureBusinessMpesaSettings(
      isActive: requestedEnabled && credentialsReady,
      displayName: _stringArg(args, ['display_name']) ?? existing.displayName,
      shortcode: shortcode,
      transactionType: transactionType,
      accountReference: accountReference,
      sendSms: args.containsKey('send_sms')
          ? _boolArg(args, ['send_sms'])
          : existing.publicConfig['sendSms'] == true,
    );
    final needsCredentials = requestedEnabled && !credentialsReady;
    return _enrichToolResult(toolSetupPaymentGateway, {
      'type': toolSetupPaymentGateway,
      'success': true,
      'provider': 'mpesa',
      'display_name': configured.displayName,
      'shortcode': configured.publicConfig['shortcode'],
      'enabled': configured.isActive,
      'needs_credentials': needsCredentials,
      'summary': needsCredentials
          ? 'Saved the public M-Pesa settings as inactive. The owner must add Consumer Key, Consumer Secret, and Passkey in Settings > Payment Methods before Piki can enable it.'
          : configured.isActive
          ? 'M-Pesa is configured and enabled for storefront checkout.'
          : 'M-Pesa public settings were saved and the gateway remains disabled.',
    }, args: args);
  }

  static String _storefrontPreset(Map<String, dynamic> args) {
    final requested = (_stringArg(args, ['preset', 'theme']) ?? 'studio')
        .toLowerCase();
    return switch (requested) {
      'minimal' => 'minimal',
      'warm' || 'elegant' => 'warm',
      'fresh' => 'fresh',
      'bold' || 'dark' => 'bold',
      _ => 'studio',
    };
  }

  static Map<String, dynamic> _storefrontDesignChanges(
    Map<String, dynamic> args, {
    String? accentColor,
  }) {
    final result = <String, dynamic>{};
    if (accentColor != null && accentColor.trim().isNotEmpty) {
      result['accentColor'] = accentColor.trim();
    }
    const fields = {
      'background_color': 'backgroundColor',
      'text_color': 'textColor',
      'muted_color': 'mutedColor',
      'surface_color': 'surfaceColor',
      'surface_elevated_color': 'surfaceElevatedColor',
      'border_color': 'borderColor',
      'font_family': 'fontFamily',
      'hero_style': 'heroStyle',
      'card_style': 'cardStyle',
      'image_ratio': 'imageRatio',
      'density': 'density',
      'corner_style': 'cornerStyle',
    };
    for (final entry in fields.entries) {
      final value = _stringArg(args, [entry.key]);
      if (value != null) result[entry.value] = value;
    }
    return result;
  }

  static Map<String, dynamic> _storefrontCheckoutChanges(
    Map<String, dynamic> args, [
    StorefrontCheckoutSettings? existing,
  ]) {
    final result = existing == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(existing.toJson());
    final paymentMethods = _stringListArg(args, ['payment_methods'])
        .map((item) => item.toLowerCase())
        .where((item) => item == 'manual' || item == 'mpesa')
        .toSet()
        .toList();
    if (paymentMethods.isNotEmpty) {
      result['paymentMethods'] = paymentMethods;
      result['defaultPaymentMethod'] =
          paymentMethods.contains(existing?.defaultPaymentMethod)
          ? existing!.defaultPaymentMethod
          : paymentMethods.first;
    }
    final fulfillmentMethods = _stringListArg(args, ['fulfillment_methods'])
        .map((item) => item.toLowerCase())
        .where((item) => item == 'pickup' || item == 'delivery')
        .toSet()
        .toList();
    if (fulfillmentMethods.isNotEmpty) {
      result['fulfillmentMethods'] = fulfillmentMethods;
      result['defaultFulfillmentMethod'] =
          fulfillmentMethods.contains(existing?.defaultFulfillmentMethod)
          ? existing!.defaultFulfillmentMethod
          : fulfillmentMethods.first;
    }
    const boolFields = {
      'show_delivery_address': 'showDeliveryAddress',
      'show_order_note': 'showOrderNote',
      'show_order_tracking': 'showOrderTracking',
    };
    for (final entry in boolFields.entries) {
      if (args.containsKey(entry.key)) {
        result[entry.value] = _boolArg(args, [entry.key]);
      }
    }
    const textFields = {
      'checkout_title': 'checkoutTitle',
      'checkout_button_label': 'checkoutButtonLabel',
      'success_message': 'successMessage',
    };
    for (final entry in textFields.entries) {
      final value = _stringArg(args, [entry.key]);
      if (value != null) result[entry.value] = value;
    }
    return result;
  }

  static Future<Map<String, dynamic>> _recordProductSale(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'product_name',
      'query',
      'name',
    ], 'Product name');
    final sellable = await findSellableProductForSale(query);
    if (sellable == null) {
      throw Exception('No product found matching "$query"');
    }
    final product = sellable.product;
    final variant = sellable.variant;
    final quantity = _requiredPositiveDoubleArg(
      {'quantity': args['quantity'] ?? 1},
      ['quantity'],
      'Quantity',
    );
    final saleToStockFactor = (product['sale_to_stock_factor'] as num? ?? 1)
        .toDouble();
    final unitPrice =
        _doubleArg(args, ['unit_price', 'price']) ??
        (variant?['price'] as num? ?? product['price'] as num? ?? 0).toDouble();
    if (unitPrice <= 0) {
      throw Exception('Unit price must be greater than zero');
    }
    final unitCost =
        ((variant?['cost'] as num? ?? product['cost'] as num? ?? 0)
            .toDouble()) *
        saleToStockFactor;
    final total = quantity * unitPrice;
    final saleId = await SaleRepository.createSale(
      totalAmount: total,
      tax: 0,
      discount: 0,
      paymentType: _paymentTypeArg(args),
      userId: _currentUserId(),
      items: [
        {
          'line_type': 'product',
          'product_id': product['id'],
          'product_name': sellable.label,
          'quantity': quantity,
          'unit_price': unitPrice,
          'unit_cost': unitCost,
          'unit':
              product['sale_unit'] as String? ??
              product['unit'] as String? ??
              'pcs',
          'sale_to_stock_factor': saleToStockFactor,
          'stock_unit':
              product['stock_unit'] as String? ??
              product['unit'] as String? ??
              'pcs',
          'track_stock': product['track_stock'] ?? 1,
          'variant_id': variant?['id'],
        },
      ],
    );

    return _enrichToolResult(toolRecordProductSale, {
      'type': toolRecordProductSale,
      'success': true,
      'id': saleId,
      'product_id': product['id'],
      'variant_id': variant?['id'],
      'product_name': sellable.label,
      'quantity': quantity,
      'total': total,
      'summary':
          'Recorded sale of $quantity x ${sellable.label} for ${ShopSettings.currency}${total.toStringAsFixed(2)}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _recordServiceSale(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'service_name',
      'query',
      'name',
    ], 'Service name');
    final service = await _findService(query);
    if (service == null) {
      throw Exception('No active service found matching "$query"');
    }
    final quantity = _requiredPositiveDoubleArg(
      {'quantity': args['quantity'] ?? 1},
      ['quantity'],
      'Quantity',
    );
    final unitPrice =
        _doubleArg(args, ['unit_price', 'price']) ??
        (service['base_price'] as num? ?? 0).toDouble();
    if (unitPrice <= 0) {
      throw Exception('Unit price must be greater than zero');
    }
    final serviceName = service['name'] as String? ?? query;
    final serviceId = service['id'] as String;
    final total = quantity * unitPrice;
    final now = DateTime.now().toIso8601String();
    final assignedStaff = ServiceRepository.defaultAssignedStaffName();
    final orderId = await ServiceRepository.createOrder(
      serviceId: serviceId,
      serviceName: serviceName,
      customerName: _stringArg(args, ['customer_name', 'customer']),
      entryMode: 'walk_in',
      checkedInAt: now,
      status: 'completed',
      assignedStaff: assignedStaff,
      assignedStaffUserId: ServiceRepository.currentAssignedStaffUserIdFor(
        assignedStaff,
      ),
      price: total,
      note: _stringArg(args, ['note']),
    );
    final saleId = await SaleRepository.createSale(
      totalAmount: total,
      tax: 0,
      discount: 0,
      paymentType: _paymentTypeArg(args),
      userId: _currentUserId(),
      items: [
        {
          'line_type': 'service',
          'product_id': 'service:$orderId',
          'product_name': serviceName,
          'quantity': quantity,
          'unit_price': unitPrice,
          'service_order_id': orderId,
          'service_id': serviceId,
        },
      ],
    );

    return _enrichToolResult(toolRecordServiceSale, {
      'type': toolRecordServiceSale,
      'success': true,
      'id': saleId,
      'service_order_id': orderId,
      'service_id': serviceId,
      'service_name': serviceName,
      'quantity': quantity,
      'total': total,
      'summary':
          'Recorded service sale of $quantity x $serviceName for ${ShopSettings.currency}${total.toStringAsFixed(2)}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createCategory(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'category',
    ], 'Category name');
    final id = await CategoryRepository.create(
      name: name,
      color: _stringArg(args, ['color']),
    );
    return _enrichToolResult(toolCreateCategory, {
      'type': toolCreateCategory,
      'success': true,
      'id': id,
      'name': name,
      'summary': 'Created product category "$name"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createExpenseCategory(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'category',
    ], 'Expense category name');
    final id = await ExpenseRepository.createCategory(
      name: name,
      color: _stringArg(args, ['color']),
    );
    return _enrichToolResult(toolCreateExpenseCategory, {
      'type': toolCreateExpenseCategory,
      'success': true,
      'id': id,
      'name': name,
      'summary': 'Created expense category "$name"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createCustomer(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'customer_name',
    ], 'Customer name');
    final id = await CustomerRepository.create(
      name: name,
      phone: _stringArg(args, ['phone']),
      email: _stringArg(args, ['email']),
    );
    return _enrichToolResult(toolCreateCustomer, {
      'type': toolCreateCustomer,
      'success': true,
      'id': id,
      'name': name,
      'summary': 'Created customer "$name"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createSupplier(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'supplier_name',
    ], 'Supplier name');
    final id = await PurchaseRepository.createSupplier(
      name: name,
      phone: _stringArg(args, ['phone']),
      email: _stringArg(args, ['email']),
      address: _stringArg(args, ['address']),
      note: _stringArg(args, ['note']),
    );
    return _enrichToolResult(toolCreateSupplier, {
      'type': toolCreateSupplier,
      'success': true,
      'id': id,
      'name': name,
      'summary': 'Created supplier "$name"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _reconcileStock(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'product_name',
      'query',
      'name',
    ], 'Product name');
    final product = await findProductForSale(query);
    if (product == null) {
      throw Exception('No product found matching "$query"');
    }
    final newCount = _doubleArg(args, ['new_count', 'count', 'stock']);
    if (newCount == null || newCount < 0) {
      throw Exception('New stock count must be zero or greater');
    }
    final oldCount = (product['stock'] as num? ?? 0).toDouble();
    await ProductRepository.update(product['id'] as String, {
      'stock': newCount,
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    });
    return _enrichToolResult(toolReconcileStock, {
      'type': toolReconcileStock,
      'success': true,
      'product_id': product['id'],
      'product_name': product['name'],
      'old_stock': oldCount,
      'new_stock': newCount,
      'summary': 'Updated ${product['name']} stock from $oldCount to $newCount',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _addServiceField(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'service_name',
      'query',
      'name',
    ], 'Service name');
    final service = await _findService(query);
    if (service == null) {
      throw Exception('No active service found matching "$query"');
    }
    final label = _requiredStringArg(args, [
      'field_label',
      'label',
    ], 'Field label');
    final fieldType =
        _stringArg(args, ['field_type', 'type'])?.toLowerCase() ?? 'text';
    final serviceId = service['id'] as String;
    final fields = await ServiceRepository.getFieldsForService(serviceId);
    fields.add({
      'label': label,
      'field_type': fieldType,
      'options': _stringListArg(args, ['options']),
      'is_required': _boolArg(args, ['is_required', 'required']),
      'sort_order': fields.length,
    });
    await ServiceRepository.updateService(
      id: serviceId,
      name: service['name'] as String? ?? query,
      category: service['category'] as String?,
      description: service['description'] as String?,
      basePrice: (service['base_price'] as num? ?? 0).toDouble(),
      durationMinutes: (service['duration_minutes'] as num?)?.toInt(),
      isActive: (service['is_active'] as num? ?? 1) != 0,
      fields: fields,
    );
    return _enrichToolResult(toolAddServiceField, {
      'type': toolAddServiceField,
      'success': true,
      'service_id': serviceId,
      'service_name': service['name'],
      'field_label': label,
      'summary': 'Added "$label" field to ${service['name']}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _searchCustomers(
    Map<String, dynamic> args,
  ) async {
    final query = _stringArg(args, ['query', 'name', 'customer_name']) ?? '';
    final limit = _coercePositiveInt(args['limit'], 10).clamp(1, 20);
    final customers = await CustomerRepository.search(query);
    final limited = customers.take(limit).toList();
    return _enrichToolResult(toolCustomerSearch, {
      'type': toolCustomerSearch,
      'items': limited,
      'count': customers.length,
      'searched_query': query,
      'summary': query.isEmpty
          ? '${customers.length} customers found'
          : '${customers.length} customer matches for "$query"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _searchSuppliers(
    Map<String, dynamic> args,
  ) async {
    final query = _stringArg(args, ['query', 'name', 'supplier_name']) ?? '';
    final limit = _coercePositiveInt(args['limit'], 10).clamp(1, 20);
    final normalized = query.toLowerCase();
    final suppliers = await PurchaseRepository.getSuppliers();
    final matches = normalized.isEmpty
        ? suppliers
        : suppliers.where((supplier) {
            final haystack = [
              supplier['name'],
              supplier['phone'],
              supplier['email'],
              supplier['address'],
            ].whereType<Object>().join(' ').toLowerCase();
            return haystack.contains(normalized);
          }).toList();
    final limited = matches.take(limit).toList();
    return _enrichToolResult(toolSupplierSearch, {
      'type': toolSupplierSearch,
      'items': limited,
      'count': matches.length,
      'searched_query': query,
      'summary': query.isEmpty
          ? '${matches.length} suppliers found'
          : '${matches.length} supplier matches for "$query"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _webSearch(
    Map<String, dynamic> args,
  ) async {
    final query = (args['query'] ?? args['q'] ?? '').toString().trim();
    if (query.isEmpty) {
      throw Exception('Web search query is required.');
    }

    final result = await OpenRouterService.webSearch(
      query: query,
      location: (args['location'] as String?)?.trim(),
      countryCode:
          (args['countryCode'] as String?)?.trim() ??
          (args['gl'] as String?)?.trim(),
      language:
          (args['language'] as String?)?.trim() ??
          (args['hl'] as String?)?.trim(),
      limit: _coercePositiveInt(args['limit'], 5).clamp(1, 10),
    );
    final results =
        (result['results'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    final citations = results
        .where((item) => (item['link'] as String? ?? '').isNotEmpty)
        .take(5)
        .map(
          (item) => {
            'label': item['title'] as String? ?? 'Web result',
            'detail': item['link'] as String? ?? '',
          },
        )
        .toList();

    return _enrichToolResult(toolWebSearch, {
      ...result,
      'items': results,
      'citations': citations,
      'summary':
          result['summary'] as String? ??
          '${results.length} web result(s) found for "$query"',
    }, args: args);
  }

  static Map<String, dynamic> _enrichToolResult(
    String tool,
    Map<String, dynamic> result, {
    required Map<String, dynamic> args,
  }) {
    final enriched = Map<String, dynamic>.from(result);
    enriched['tool'] = tool;
    enriched['title'] = _toolLabels[tool] ?? enriched['title'] ?? tool;
    final existingCitations =
        (enriched['citations'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    enriched['citations'] = existingCitations.isNotEmpty
        ? existingCitations
        : _citationsForTool(tool, result, args: args);
    return enriched;
  }

  static List<Map<String, dynamic>> _citationsForTool(
    String tool,
    Map<String, dynamic> result, {
    required Map<String, dynamic> args,
  }) {
    final period = periodLabelForDays(
      _coercePositiveInt(args['daysRange'], _defaultDaysForTool(tool)),
    );
    final query = (args['query'] as String?)?.trim();
    return switch (tool) {
      toolLowStock => [
        {
          'label': 'Inventory records',
          'detail':
              'Pulled from local product stock and low-stock thresholds for the current branch.',
        },
      ],
      toolTodaySummary || toolProfitSummary => [
        {
          'label': 'Sales ledger',
          'detail':
              'Calculated from sales and sale items for $period in the current branch.',
        },
      ],
      toolRestockList => [
        {
          'label': 'Restock analysis',
          'detail':
              'Built from current stock versus low-stock thresholds in the local product catalog.',
        },
      ],
      toolSalesReport => [
        {
          'label': 'Recent sales',
          'detail':
              'Listed from recorded sales between the selected start and end dates for $period.',
        },
      ],
      toolProductSearch => [
        {
          'label': 'Product catalog',
          'detail': query == null || query.isEmpty
              ? 'Read from the local product catalog for the current branch.'
              : 'Matched against local product name, barcode, or SKU using "$query".',
        },
      ],
      toolShiftSummary => [
        {
          'label': 'Closed shifts',
          'detail':
              'Loaded from the most recent closed shifts in the current branch.',
        },
      ],
      toolExpiryCheck => [
        {
          'label': 'Stock batches',
          'detail': 'Based on stored batch expiry dates and remaining stock.',
        },
      ],
      toolTopDebtors => [
        {
          'label': 'Credit balances',
          'detail':
              'Ranked from customer balances and open Kopesha sales in the current branch.',
        },
      ],
      toolTopProducts => [
        {
          'label': 'Top products',
          'detail':
              'Ranked from sale item quantities and revenue for $period in the current branch.',
        },
      ],
      toolExpenseSummary => [
        {
          'label': 'Expense log',
          'detail':
              'Summarized from recorded operating expenses for $period in the current branch.',
        },
      ],
      toolPurchaseHistory => [
        {
          'label': 'Purchase history',
          'detail':
              'Read from stock-in batches joined with purchase invoices and suppliers.',
        },
      ],
      toolPurchaseDraft => [
        {
          'label': 'Draft inputs',
          'detail':
              'Built from low-stock items and the latest supplier and unit-cost history found locally.',
        },
      ],
      toolPredictiveRestock => [
        {
          'label': 'Predictive restock',
          'detail':
              'Forecast from current product stock and sale item velocity for $period.',
        },
      ],
      toolAnomalyAlerts => [
        {
          'label': 'Business alerts',
          'detail':
              'Scanned local sales, inventory, expiry, Kopesha, and shift records.',
        },
      ],
      toolCustomerFollowups => [
        {
          'label': 'Kopesha customers',
          'detail':
              'Prepared from customer balances and open credit sales in the current branch.',
        },
      ],
      toolDailyWhatsappReport => [
        {
          'label': 'Daily report draft',
          'detail':
              'Compiled from local sales, top products, restock forecasts, and alerts.',
        },
      ],
      toolCatalogOrders => [
        {
          'label': 'Catalog orders',
          'detail':
              'Read from customer orders submitted through the public catalog link.',
        },
      ],
      toolImageOrderDraft => [
        {
          'label': 'Image AI analysis',
          'detail':
              'Read from the provided product or order image through the configured OpenRouter model.',
        },
      ],
      toolCustomerSearch => [
        {
          'label': 'Customer records',
          'detail': 'Read from local customers in the current branch.',
        },
      ],
      toolSupplierSearch => [
        {
          'label': 'Supplier records',
          'detail': 'Read from local supplier records in the current branch.',
        },
      ],
      toolWebSearch => [
        {
          'label': 'Web search',
          'detail': query == null || query.isEmpty
              ? 'Searched live Google results through the backend SerpAPI proxy.'
              : 'Searched live Google results for "$query" through the backend SerpAPI proxy.',
        },
      ],
      toolCreateProduct ||
      toolDeleteProduct ||
      toolCreateService ||
      toolRecordProductSale ||
      toolRecordServiceSale ||
      toolCreateCategory ||
      toolCreateExpenseCategory ||
      toolCreateCustomer ||
      toolCreateSupplier ||
      toolReconcileStock ||
      toolAddServiceField => [
        {
          'label': 'Local POS write',
          'detail':
              'Executed against the local POS database for the current branch.',
        },
      ],
      _ => const <Map<String, dynamic>>[],
    };
  }

  static Future<Map<String, dynamic>> _createPurchaseDraft({
    required Map<String, dynamic> args,
    required Map<String, dynamic> memory,
  }) async {
    final limit = _coercePositiveInt(args['limit'], 8).clamp(1, 20);
    final memoryRestock = memory[toolRestockList];
    final memoryLowStock = memory[toolLowStock];
    List<Map<String, dynamic>> baseItems =
        (memoryRestock is Map<String, dynamic>
                ? (memoryRestock['items'] as List?)
                : null)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        <Map<String, dynamic>>[];

    if (baseItems.isEmpty) {
      baseItems =
          (memoryLowStock is Map<String, dynamic>
                  ? (memoryLowStock['items'] as List?)
                  : null)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          <Map<String, dynamic>>[];
    }

    if (baseItems.isEmpty) {
      final lowStockResult = await executeAgentTool(toolRestockList);
      baseItems = ((lowStockResult['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    final suppliers = await PurchaseRepository.getSuppliers();
    final purchaseRows = await DatabaseService.rawQuery(
      '''
      SELECT
        sb.product_id,
        pi.supplier_id,
        pi.supplier_name,
        sb.unit_cost,
        sb.received_at
      FROM stock_batches sb
      LEFT JOIN purchase_invoices pi ON pi.id = sb.purchase_id
      WHERE sb.deleted_at IS NULL
        AND COALESCE(sb.branch_id, ?) = ?
      ORDER BY sb.received_at DESC
      ''',
      [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );

    final latestByProduct = <String, Map<String, dynamic>>{};
    for (final row in purchaseRows) {
      final productId = row['product_id'] as String?;
      if (productId == null || latestByProduct.containsKey(productId)) {
        continue;
      }
      latestByProduct[productId] = row;
    }

    final draftItems = <Map<String, dynamic>>[];
    for (final item in baseItems.take(limit)) {
      final productId = item['id'] as String? ?? item['product_id'] as String?;
      if (productId == null || productId.isEmpty) {
        continue;
      }
      final history = latestByProduct[productId];
      final reorderQty =
          (item['reorder_qty'] as num? ??
                  (((item['low_stock'] as num? ?? 0).toDouble() * 2) -
                      (item['stock'] as num? ?? 0).toDouble()))
              .toDouble();
      draftItems.add({
        'product_id': productId,
        'product_name': item['name'] ?? item['product_name'],
        'recommended_qty': reorderQty <= 0 ? 1.0 : reorderQty,
        'unit':
            item['purchase_unit'] ??
            item['stock_unit'] ??
            item['unit'] ??
            'pcs',
        'last_unit_cost':
            (history?['unit_cost'] as num? ?? item['cost'] as num? ?? 0)
                .toDouble(),
        'suggested_supplier_name': history?['supplier_name'],
        'suggested_supplier_id': history?['supplier_id'],
        'last_received_at': history?['received_at'],
      });
    }

    final supplierCounts = <String, int>{};
    for (final item in draftItems) {
      final supplierName = (item['suggested_supplier_name'] as String?)?.trim();
      if (supplierName == null || supplierName.isEmpty) {
        continue;
      }
      supplierCounts[supplierName] = (supplierCounts[supplierName] ?? 0) + 1;
    }
    final topSupplier = supplierCounts.entries.isEmpty
        ? null
        : (supplierCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;

    final knownSupplierNames = suppliers
        .map((supplier) => supplier['name'] as String?)
        .whereType<String>()
        .take(5)
        .toList();
    final supplierGroups = <String, List<Map<String, dynamic>>>{};
    for (final item in draftItems) {
      final supplierName =
          (item['suggested_supplier_name'] as String?)?.trim() ?? '';
      final key = supplierName.isEmpty ? 'Unassigned supplier' : supplierName;
      supplierGroups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(item);
    }
    final groupedPreview =
        supplierGroups.entries.map((entry) {
          final items = entry.value;
          final estimatedTotal = items.fold<double>(
            0,
            (sum, item) =>
                sum +
                ((item['recommended_qty'] as num? ?? 0).toDouble() *
                    (item['last_unit_cost'] as num? ?? 0).toDouble()),
          );
          return {
            'supplier_name': entry.key,
            'item_count': items.length,
            'estimated_total': estimatedTotal,
            'items': items
                .take(3)
                .map(
                  (item) => {
                    'product_name': item['product_name'],
                    'recommended_qty': item['recommended_qty'],
                    'unit': item['unit'],
                  },
                )
                .toList(),
          };
        }).toList()..sort(
          (a, b) => (b['item_count'] as int).compareTo(a['item_count'] as int),
        );

    return _enrichToolResult(toolPurchaseDraft, {
      'type': 'purchase_draft',
      'items': draftItems,
      'count': draftItems.length,
      'preferred_supplier': topSupplier,
      'supplier_groups': groupedPreview,
      'known_suppliers': knownSupplierNames,
      'summary': draftItems.isEmpty
          ? 'No purchase draft could be built because there are no low-stock items yet.'
          : topSupplier == null
          ? 'Prepared a purchase draft for ${draftItems.length} low-stock items.'
          : 'Prepared a purchase draft for ${draftItems.length} items. $topSupplier is the best supplier match from recent history.',
      'details': draftItems.take(4).map((item) {
        final qty = (item['recommended_qty'] as num? ?? 0).toDouble();
        final supplier = item['suggested_supplier_name'] as String?;
        return supplier == null || supplier.isEmpty
            ? '${item['product_name']}: order ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} ${item['unit']}'
            : '${item['product_name']}: order ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} ${item['unit']} from $supplier';
      }).toList(),
    }, args: args);
  }

  static Future<Map<String, dynamic>> _editProduct(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'query',
      'name',
      'product_name',
    ], 'Product query');
    final products = await ProductRepository.searchForPos(query);
    if (products.isEmpty) {
      throw Exception('Could not find product matching "$query".');
    }
    final target = products.first;
    final isVariant = target['result_type'] == 'variant';
    final id = isVariant
        ? target['matched_variant_id'] as String
        : target['id'] as String;

    final updates = <String, dynamic>{};
    final newName = _stringArg(args, ['new_name']);
    if (newName != null) updates['name'] = newName;
    final price = _doubleArg(args, ['price']);
    if (price != null) updates['price'] = price;
    final cost = _doubleArg(args, ['cost']);
    if (cost != null) updates['cost'] = cost;
    final lowStock = _doubleArg(args, ['low_stock']);
    if (lowStock != null && lowStock >= 0) updates['low_stock'] = lowStock;
    final barcode = _stringArg(args, ['barcode']);
    if (barcode != null) updates['barcode'] = barcode;

    if (updates.isEmpty) {
      throw Exception('No valid fields provided to edit.');
    }

    updates['updated_at'] = DateTime.now().toIso8601String();
    updates['sync_status'] = 'pending';

    if (isVariant) {
      await ProductVariantRepository.update(id, updates);
    } else {
      await ProductRepository.update(id, updates);
    }

    return {
      'tool': toolEditProduct,
      'summary':
          'Updated ${isVariant ? 'variant' : 'product'} "${target['name']}" with new details.',
      'updates': updates,
    };
  }

  static Future<Map<String, dynamic>> _deleteProduct(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'query',
      'name',
      'product_name',
      'sku',
      'barcode',
    ], 'Product query');
    final products = await ProductRepository.searchForPos(query);
    if (products.isEmpty) {
      throw Exception('Could not find product matching "$query".');
    }

    final target = _resolveSingleDeleteTarget(products, query);
    final isVariant = target['result_type'] == 'variant';
    final productId = target['id'] as String?;
    if (productId == null || productId.trim().isEmpty) {
      throw Exception('Product id is missing for "$query".');
    }

    if (isVariant) {
      final variantId = target['matched_variant_id'] as String?;
      final variantName =
          target['matched_variant_name']?.toString() ?? 'variant';
      final productName = target['name']?.toString() ?? 'product';
      if (variantId == null || variantId.trim().isEmpty) {
        throw Exception('Variant id is missing for "$query".');
      }
      await ProductVariantRepository.delete(variantId);
      await ProductVariantRepository.syncAggregateStock(productId);
      return _enrichToolResult(toolDeleteProduct, {
        'type': toolDeleteProduct,
        'success': true,
        'deleted_type': 'variant',
        'product_id': productId,
        'variant_id': variantId,
        'product_name': productName,
        'variant_name': variantName,
        'summary':
            'Deleted variant "$variantName" from product "$productName".',
      }, args: args);
    }

    final productName = target['name']?.toString() ?? query;
    await ProductRepository.delete(productId);
    return _enrichToolResult(toolDeleteProduct, {
      'type': toolDeleteProduct,
      'success': true,
      'deleted_type': 'product',
      'product_id': productId,
      'product_name': productName,
      'summary': 'Deleted product "$productName".',
    }, args: args);
  }

  static Map<String, dynamic> _resolveSingleDeleteTarget(
    List<Map<String, dynamic>> products,
    String query,
  ) {
    final normalizedQuery = _normalizeLookupText(query);
    final exactMatches = products.where((row) {
      final values = <String?>[
        row['name']?.toString(),
        row['sku']?.toString(),
        row['barcode']?.toString(),
        row['matched_variant_name']?.toString(),
        row['matched_variant_sku']?.toString(),
        row['matched_variant_barcode']?.toString(),
        if (row['matched_variant_name'] != null)
          '${row['name']} ${row['matched_variant_name']}',
        if (row['matched_variant_name'] != null)
          '${row['name']} - ${row['matched_variant_name']}',
      ];
      return values.any(
        (value) => _normalizeLookupText(value) == normalizedQuery,
      );
    }).toList();

    if (exactMatches.length == 1) return exactMatches.first;
    if (exactMatches.isEmpty && products.length == 1) return products.first;

    final matches = (exactMatches.isNotEmpty ? exactMatches : products)
        .take(5)
        .map(_deleteTargetLabel)
        .join(', ');
    throw Exception(
      'I found more than one product matching "$query": $matches. Please use the exact product name, variant name, SKU, or barcode to delete.',
    );
  }

  static String _deleteTargetLabel(Map<String, dynamic> row) {
    final productName = row['name']?.toString() ?? 'Product';
    if (row['result_type'] == 'variant') {
      final variantName = row['matched_variant_name']?.toString();
      if (variantName != null && variantName.trim().isNotEmpty) {
        return '$productName - $variantName';
      }
    }
    return productName;
  }

  static String _normalizeLookupText(Object? value) {
    return value
            ?.toString()
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ') ??
        '';
  }

  static Future<Map<String, dynamic>> _addVariant(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'query',
      'product_name',
      'name',
    ], 'Product query');
    final products = await ProductRepository.search(query);
    if (products.isEmpty) {
      throw Exception('Could not find parent product matching "$query".');
    }
    final target = products.first;
    final productId = target['id'] as String;

    final variantName = _requiredStringArg(args, [
      'variant_name',
      'name',
    ], 'Variant name');
    final price = _requiredPositiveDoubleArg(args, ['price'], 'Variant price');
    final cost = _doubleArg(args, ['cost']);
    final sku = _stringArg(args, ['sku']);
    final barcode = _stringArg(args, ['barcode']);
    final stock = _nonNegativeDoubleArg(args, ['stock'], 0);
    final lowStock = _nonNegativeDoubleArg(args, ['low_stock'], 0);

    final id = await ProductVariantRepository.create(
      productId: productId,
      name: variantName,
      price: price,
      cost: cost,
      sku: sku,
      barcode: barcode,
      stock: stock,
      lowStock: lowStock,
    );

    await ProductVariantRepository.setProductHasVariants(productId, true);
    await ProductVariantRepository.syncAggregateStock(productId);

    return {
      'tool': toolAddVariant,
      'summary': 'Added variant "$variantName" to product "${target['name']}".',
      'variant_id': id,
    };
  }
}

class _PikiDateRange {
  final DateTime start;
  final DateTime end;

  const _PikiDateRange({required this.start, required this.end});
}
