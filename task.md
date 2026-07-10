# Piki POS Feature Gap Implementation Tasks

## Phase 1 — Critical (deal-breakers in demos)

### Feature 1: Loyalty & Rewards Program
- [x] PG schema: `loyalty_rules`, `loyalty_ledger`, `customers.loyalty_points`
- [x] syncTables.js registration (loyalty_rules, loyalty_ledger)
- [x] Backend routes (`/api/loyalty/rules`, `/api/loyalty/points/:customerId`, `/api/loyalty/ledger`)
- [x] Entitlement key `loyalty` in subscriptionPlans.js (GROWTH+)
- [x] Flutter SQLite schema (version bump, CREATE tables, ALTER customers, _branchAwareTables)
- [x] Loyalty repository (`lib/features/loyalty/data/loyalty_repository.dart`)
- [x] Loyalty config screen (`lib/features/loyalty/presentation/loyalty_screen.dart`)
- [x] POS checkout integration (auto-earn on sale, redeem option in payment dialog)
- [x] Loyalty redemption auto-refund (points reversed if checkout cancelled, customer switched, or sale fails to save)
- [x] Contacts screen points display
- [x] App shell navigation + entitlement gating
- [x] flutter analyze clean

### Feature 2: Gift Cards / Vouchers
- [x] PG schema: `gift_cards`
- [x] syncTables.js registration
- [x] Backend routes (`/api/gift-cards` GET/POST, `:code` GET, redeem POST)
- [x] Entitlement key `gift_cards` in subscriptionPlans.js (GROWTH+)
- [x] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [x] Gift card repository
- [x] Gift card screen (issue, list, search & redeem)
- [x] POS checkout: gift card payment method
- [x] App shell navigation + entitlement gating
- [x] flutter analyze clean

### Feature 3: Advanced Promotions Engine
- [x] PG schema: `promotions`, `promotion_rules`
- [x] syncTables.js registration
- [x] Backend routes (`/api/promotions` CRUD, `/api/promotions/active`)
- [x] Entitlement key `promotions` in subscriptionPlans.js (GROWTH+)
- [x] Flutter SQLite schema (version bump, CREATE tables, _branchAwareTables)
- [x] Promotion repository (CRUD, getActive, evaluatePromotions)
- [x] Promotion screen (rule builder: buy X get Y, bundle, % off, happy hour)
- [x] POS cart: auto-apply promotions, discount breakdown
- [x] App shell navigation + entitlement gating
- [x] flutter analyze clean

### Feature 4: Tax Reports (VAT/KRA)
- [x] Backend routes (`/api/reports/tax-summary`, `/api/reports/sales-summary`, `/api/reports/inventory-valuation`, `/api/reports/profit-loss`)
- [x] Flutter tax report screen (date range, VAT summary, CSV/PDF export)
- [x] Reports screen: add "Tax / VAT Report" card
- [x] flutter analyze clean

### Feature 5: Custom Roles & Granular Permissions
- [x] PG schema: `custom_roles`, ALTER `users` ADD `custom_role_id`
- [x] syncTables.js registration (custom_roles)
- [x] Backend routes (`/api/roles` CRUD)
- [x] Entitlement key `custom_roles` in subscriptionPlans.js (GROWTH+)
- [x] Flutter SQLite schema (version bump, CREATE table, ALTER users, _branchAwareTables)
- [x] Role repository
- [x] Role management screen (per-module permission matrix)
- [x] Settings screen: "Roles & Permissions" section
- [x] session_service / UserAccessProfile: integrate custom role permissions
- [x] App shell navigation + entitlement gating
- [x] flutter analyze clean

## Phase 2 — Significant (competitive parity)

### Feature 6: Supplier Aging / AP Reports
- [x] Backend routes (`/api/suppliers/:id/statement`, `/api/suppliers/aging`)
- [x] Supplier statement screen (running ledger, aging buckets)
- [x] Purchases screen: link to supplier statements
- [x] flutter analyze clean

### Feature 7: Serial Number Tracking
- [x] PG schema: `product_serials`
- [x] syncTables.js registration
- [x] Backend routes (`/api/serials` assign/list)
- [x] Entitlement key `serial_tracking`
- [x] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [x] Serial number repository
- [x] Product detail: assign serials on stock-in
- [x] POS: sell-by-serial option
- [x] Warranty tracking view
- [x] flutter analyze clean

### Feature 8: Stocktake / Cycle Counting
- [x] PG schema: `stocktake_sessions`, `stocktake_items`
- [x] syncTables.js registration
- [x] Backend routes (`/api/stocktakes` CRUD)
- [x] Entitlement key `stocktake`
- [x] Flutter SQLite schema (version bump, CREATE tables, _branchAwareTables)
- [x] Stocktake repository
- [x] Stocktake screen (guided count, reconciliation, auto-adjust)
- [x] flutter analyze clean

### Feature 9: Bulk SMS Marketing Campaigns
- [x] PG schema: `sms_campaigns`
- [x] syncTables.js registration
- [x] Backend routes (`/api/campaigns` CRUD, send)
- [x] Entitlement key `sms_campaigns`
- [x] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [x] Campaign repository
- [x] Campaign builder screen (segment, compose, send)
- [x] flutter analyze clean

### Feature 10: Multi-Currency Support
- [x] PG schema: `exchange_rates`
- [x] syncTables.js registration
- [x] Backend routes (`/api/exchange-rates` CRUD)
- [x] Entitlement key `multi_currency`
- [x] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [x] Exchange rate repository
- [x] Settings: configure secondary currency + rate
- [x] POS: dual-display toggle
- [x] flutter analyze clean

### Feature 11: Inventory Reorder Suggestions
- [x] Backend route (`/api/reports/reorder-suggestions`)
- [x] Reorder suggestion computation (sales velocity + lead time)
- [x] Dashboard widget
- [x] Stock list: reorder suggestions section
- [x] flutter analyze clean

### Feature 12: Wastage / Spoilage Tracking
- [x] PG schema: `wastage_logs`
- [x] syncTables.js registration
- [x] Backend routes (`/api/wastage` CRUD)
- [x] Entitlement key `wastage`
- [x] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [x] Wastage repository
- [x] Wastage recording screen (auto-decrement stock)
- [x] flutter analyze clean

## Phase 3 — Differentiators

### Feature 13: Restaurant / Hospitality Mode
- [x] PG schema: `restaurant_tables`, `table_orders`
- [x] syncTables.js registration
- [x] Backend routes
- [x] Entitlement key `restaurant_mode`
- [x] Flutter SQLite schema
- [x] Floor plan screen
- [x] Kitchen display system (KDS)
- [x] Bill splitting
- [x] flutter analyze clean

### Feature 14: Full E-commerce Checkout
- [x] Backend: `/api/online-orders` with payment, `/api/delivery/*`
- [x] Storefront-web: online payment gateway (Stripe/PayPal)
- [x] Delivery zones + tracking
- [x] flutter analyze clean

### Feature 15: Employee Attendance
- [x] PG schema: `employee_attendance`
- [x] syncTables.js registration
- [x] Backend routes
- [x] Entitlement key `attendance`
- [x] Flutter SQLite schema
- [x] Attendance repository
- [x] Clock-in/out screen
- [x] Attendance reports
- [x] flutter analyze clean

### Feature 16: Customer Groups / Segments
- [x] PG schema: `customer_groups`, `customer_group_members`
- [x] syncTables.js registration
- [x] Backend routes
- [x] Entitlement key `customer_segments`
- [x] Flutter SQLite schema
- [x] Group repository
- [x] Group management screen
- [x] Integrate with SMS campaigns
- [x] flutter analyze clean

### Feature 17: Purchase Approval Workflows
- [x] Backend: threshold-based approval on purchases
- [x] purchase_orders status workflow extension
- [x] Approval screen for managers
- [x] flutter analyze clean

### Feature 18: Delivery Management
- [x] PG schema: `delivery_zones`, `deliveries`
- [x] syncTables.js registration
- [x] Backend routes
- [x] Entitlement key `delivery`
- [x] Flutter SQLite schema
- [x] Delivery zone config
- [x] Delivery tracking screen
- [x] flutter analyze clean

### Feature 19: Customer Self-Service Portal
- [x] Web portal: view statements, make M-Pesa payments
- [x] Backend: customer auth + statement/payment endpoints
- [x] flutter analyze clean

### Feature 20: Advanced BI Dashboard
- [x] Backend: CLV, forecasting, cohort, turnover aggregation endpoints
- [x] BI dashboard screen (charts, insights)
- [x] flutter analyze clean
