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
- [ ] PG schema: `gift_cards`
- [ ] syncTables.js registration
- [ ] Backend routes (`/api/gift-cards` GET/POST, `:code` GET, redeem POST)
- [ ] Entitlement key `gift_cards` in subscriptionPlans.js (GROWTH+)
- [ ] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [ ] Gift card repository
- [ ] Gift card screen (issue, list, search & redeem)
- [ ] POS checkout: gift card payment method
- [ ] App shell navigation + entitlement gating
- [ ] flutter analyze clean

### Feature 3: Advanced Promotions Engine
- [ ] PG schema: `promotions`, `promotion_rules`
- [ ] syncTables.js registration
- [ ] Backend routes (`/api/promotions` CRUD, `/api/promotions/active`)
- [ ] Entitlement key `promotions` in subscriptionPlans.js (GROWTH+)
- [ ] Flutter SQLite schema (version bump, CREATE tables, _branchAwareTables)
- [ ] Promotion repository (CRUD, getActive, evaluatePromotions)
- [ ] Promotion screen (rule builder: buy X get Y, bundle, % off, happy hour)
- [ ] POS cart: auto-apply promotions, discount breakdown
- [ ] App shell navigation + entitlement gating
- [ ] flutter analyze clean

### Feature 4: Tax Reports (VAT/KRA)
- [ ] Backend routes (`/api/reports/tax-summary`, `/api/reports/sales-summary`, `/api/reports/inventory-valuation`, `/api/reports/profit-loss`)
- [ ] Flutter tax report screen (date range, VAT summary, CSV/PDF export)
- [ ] Reports screen: add "Tax / VAT Report" card
- [ ] flutter analyze clean

### Feature 5: Custom Roles & Granular Permissions
- [ ] PG schema: `custom_roles`, ALTER `users` ADD `custom_role_id`
- [ ] syncTables.js registration (custom_roles)
- [ ] Backend routes (`/api/roles` CRUD)
- [ ] Entitlement key `custom_roles` in subscriptionPlans.js (GROWTH+)
- [ ] Flutter SQLite schema (version bump, CREATE table, ALTER users, _branchAwareTables)
- [ ] Role repository
- [ ] Role management screen (per-module permission matrix)
- [ ] Settings screen: "Roles & Permissions" section
- [ ] session_service / UserAccessProfile: integrate custom role permissions
- [ ] App shell navigation + entitlement gating
- [ ] flutter analyze clean

## Phase 2 — Significant (competitive parity)

### Feature 6: Supplier Aging / AP Reports
- [ ] Backend routes (`/api/suppliers/:id/statement`, `/api/suppliers/aging`)
- [ ] Supplier statement screen (running ledger, aging buckets)
- [ ] Purchases screen: link to supplier statements
- [ ] flutter analyze clean

### Feature 7: Serial Number Tracking
- [ ] PG schema: `product_serials`
- [ ] syncTables.js registration
- [ ] Backend routes (`/api/serials` assign/list)
- [ ] Entitlement key `serial_tracking`
- [ ] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [ ] Serial number repository
- [ ] Product detail: assign serials on stock-in
- [ ] POS: sell-by-serial option
- [ ] Warranty tracking view
- [ ] flutter analyze clean

### Feature 8: Stocktake / Cycle Counting
- [ ] PG schema: `stocktake_sessions`, `stocktake_items`
- [ ] syncTables.js registration
- [ ] Backend routes (`/api/stocktapes` CRUD)
- [ ] Entitlement key `stocktake`
- [ ] Flutter SQLite schema (version bump, CREATE tables, _branchAwareTables)
- [ ] Stocktake repository
- [ ] Stocktake screen (guided count, reconciliation, auto-adjust)
- [ ] flutter analyze clean

### Feature 9: Bulk SMS Marketing Campaigns
- [ ] PG schema: `sms_campaigns`
- [ ] syncTables.js registration
- [ ] Backend routes (`/api/campaigns` CRUD, send)
- [ ] Entitlement key `sms_campaigns`
- [ ] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [ ] Campaign repository
- [ ] Campaign builder screen (segment, compose, send)
- [ ] flutter analyze clean

### Feature 10: Multi-Currency Support
- [ ] PG schema: `exchange_rates`
- [ ] syncTables.js registration
- [ ] Backend routes (`/api/exchange-rates` CRUD)
- [ ] Entitlement key `multi_currency`
- [ ] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [ ] Exchange rate repository
- [ ] Settings: configure secondary currency + rate
- [ ] POS: dual-display toggle
- [ ] flutter analyze clean

### Feature 11: Inventory Reorder Suggestions
- [ ] Backend route (`/api/reports/reorder-suggestions`)
- [ ] Reorder suggestion computation (sales velocity + lead time)
- [ ] Dashboard widget
- [ ] Stock list: reorder suggestions section
- [ ] flutter analyze clean

### Feature 12: Wastage / Spoilage Tracking
- [ ] PG schema: `wastage_logs`
- [ ] syncTables.js registration
- [ ] Backend routes (`/api/wastage` CRUD)
- [ ] Entitlement key `wastage`
- [ ] Flutter SQLite schema (version bump, CREATE table, _branchAwareTables)
- [ ] Wastage repository
- [ ] Wastage recording screen (auto-decrement stock)
- [ ] flutter analyze clean

## Phase 3 — Differentiators

### Feature 13: Restaurant / Hospitality Mode
- [ ] PG schema: `restaurant_tables`, `table_orders`
- [ ] syncTables.js registration
- [ ] Backend routes
- [ ] Entitlement key `restaurant_mode`
- [ ] Flutter SQLite schema
- [ ] Floor plan screen
- [ ] Kitchen display system (KDS)
- [ ] Bill splitting
- [ ] flutter analyze clean

### Feature 14: Full E-commerce Checkout
- [ ] Backend: `/api/online-orders` with payment, `/api/delivery/*`
- [ ] Storefront-web: online payment gateway (Stripe/PayPal)
- [ ] Delivery zones + tracking
- [ ] flutter analyze clean

### Feature 15: Employee Attendance
- [ ] PG schema: `employee_attendance`
- [ ] syncTables.js registration
- [ ] Backend routes
- [ ] Entitlement key `attendance`
- [ ] Flutter SQLite schema
- [ ] Attendance repository
- [ ] Clock-in/out screen
- [ ] Attendance reports
- [ ] flutter analyze clean

### Feature 16: Customer Groups / Segments
- [ ] PG schema: `customer_groups`, `customer_group_members`
- [ ] syncTables.js registration
- [ ] Backend routes
- [ ] Entitlement key `customer_segments`
- [ ] Flutter SQLite schema
- [ ] Group repository
- [ ] Group management screen
- [ ] Integrate with SMS campaigns
- [ ] flutter analyze clean

### Feature 17: Purchase Approval Workflows
- [ ] Backend: threshold-based approval on purchases
- [ ] purchase_orders status workflow extension
- [ ] Approval screen for managers
- [ ] flutter analyze clean

### Feature 18: Delivery Management
- [ ] PG schema: `delivery_zones`, `deliveries`
- [ ] syncTables.js registration
- [ ] Backend routes
- [ ] Entitlement key `delivery`
- [ ] Flutter SQLite schema
- [ ] Delivery zone config
- [ ] Delivery tracking screen
- [ ] flutter analyze clean

### Feature 19: Customer Self-Service Portal
- [ ] Web portal: view statements, make M-Pesa payments
- [ ] Backend: customer auth + statement/payment endpoints
- [ ] flutter analyze clean

### Feature 20: Advanced BI Dashboard
- [ ] Backend: CLV, forecasting, cohort, turnover aggregation endpoints
- [ ] BI dashboard screen (charts, insights)
- [ ] flutter analyze clean
