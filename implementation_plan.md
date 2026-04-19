# Velora POS Implementation Plan

This roadmap tracks the remaining work to move the current app from a strong local MVP into a production-ready POS.

## Current Focus Order

- [x] Milestone 1: Customer Kopesha detail page
  - Customer statement screen added
  - Open credit sales with due dates and balances added
  - Repayment history view added
  - Linked from the main `Kopesha` customer list
- [x] Milestone 2: Returns and refunds
  - [x] Reverse a sale safely from sales history
  - [x] Restock returned items automatically
  - [x] Track refund payment type and audit trail
  - [x] Add partial returns
  - [x] Add refund receipt / print flow
- [x] Milestone 3: Backup and restore
  - [x] Export local database
  - [x] Restore shop data from saved backups
  - [x] Add a simple restore warning/confirmation flow
- [x] Milestone 4: Purchases and suppliers
  - [x] Supplier records
  - [x] Purchase invoices
  - [x] Stock-in linked to supplier history
- [x] Milestone 5: Expenses
  - [x] Record operating expenses
  - [x] Add expense categories
  - [x] Include expenses in profit and loss
- [x] Milestone 6: Unit conversion rules
  - [x] Phase 6.1: Data model and conversion helpers
    - Add product-level base stock unit and optional sale/purchase unit configuration
    - Add conversion ratio storage so related units can map into one stock unit
    - Extend `UnitUtils` with unit families and conversion helpers
    - Keep unsupported cross-family conversions blocked, for example `kg` to `ml`
  - [x] Phase 6.2: Product form setup
    - Let a product define its stock unit and optional sale unit
    - Support common presets like `1000 g = 1 kg` and `1000 ml = 1 litre`
    - Show a clear preview explaining how entered stock, price, and low-stock values will be stored
    - Keep simple products on a no-conversion path so `pcs`, `box`, and similar units stay easy
  - [x] Phase 6.3: Inventory storage consistency
    - Store aggregate stock in one canonical unit per product
    - Convert opening stock and low-stock alerts into that canonical unit before save
    - Convert purchase stock-in quantities into canonical stock before writing batches
    - Keep batch costing aligned with the converted quantity
  - [x] Phase 6.4: POS and cart behavior
    - Sell in the configured sale unit while decrementing stock in canonical unit
    - Show available stock in both sale-facing and base units when helpful
    - Prevent selling quantities that exceed converted stock on hand
    - Keep cart quantity editing and receipt labels readable
  - [x] Phase 6.5: History, reports, and returns compatibility
    - Preserve the displayed unit on sale items and receipts
    - Ensure returns restock the correct converted quantity
    - Keep dashboard and low-stock widgets consistent with the stored stock unit
    - Review purchase history and product batch screens for mixed-unit clarity
  - [x] Phase 6.6: Migration and test coverage
    - DB migration for conversion fields handled by `_ensureProductUnitConversionSchema` (safe additive ALTER TABLE with defaults)
    - Existing products kept on their current unit with factor = 1
    - Focused widget coverage added for product-form conversion presets and edit-mode preview; broader checkout-flow widget tests can follow in a future test milestone

## Milestone 6 Implementation Notes

- Current code already supports unit labels and decimal quantities in `UnitUtils`, `product_form_screen.dart`, and `pos_screen.dart`.
- The missing piece is relational conversion, because products currently store a single `unit` and a single aggregate `stock`.
- The safest design is:
  - One canonical stock unit per product
  - Optional display/sale unit for checkout
  - A numeric conversion factor between them
- Example:
  - Sugar can store stock in `g`
  - Sell in `kg`
  - `1 kg` sold deducts `1000 g` from stock
- Likely files involved:
  - `lib/core/utils/unit_utils.dart`
  - `lib/core/services/database_service.dart`
  - `lib/features/products/data/product_repository.dart`
  - `lib/features/products/presentation/product_form_screen.dart`
  - `lib/features/purchases/presentation/purchase_management_screen.dart`
  - `lib/features/sales/data/cart_provider.dart`
  - `lib/features/sales/data/sale_repository.dart`
  - `lib/features/sales/presentation/pos_screen.dart`

## Secondary Production Gaps

- [x] Real user management
  - [x] Staff accounts
  - [x] Roles and permissions
  - [x] Password change flow
  - [x] Cashier tracking
- [x] Cloud sync completion
  - [x] Finish backend sync integration
    - Backend sync API now supports server-owned revision cursors for safer incremental pull/status reads
    - Backend push responses now surface applied/unchanged/invalid/conflict summaries
    - Flutter client now pushes pending local rows, stores the server cursor, and applies pulled cloud updates locally
  - [x] Conflict handling
    - Flutter sync now consumes backend conflict payloads and resolves stale local rows with the server copy
  - [x] Sync status visibility
    - Settings screen now shows backend URL, auto-sync control, cursor/device info, last sync time, and manual sync actions
    - POS app bar now shows live sync state instead of a hardcoded badge
- [x] Better reports
  - [x] Top products (best/worst sellers by qty and revenue, filterable by period)
  - [x] Top debtors (customers sorted by outstanding Kopesha balance)
  - [x] Overdue aging (Kopesha aging buckets: current, 1-7, 8-30, 31-60, 60+ days)
  - [x] Stock movement (stock-in vs sold per product per period)
  - [x] Daily cashier summary
- [ ] Mobile polish
  - Tighten dialogs and dense screens
  - Improve small-screen navigation and actions
- [ ] Receipt printing improvements
  - [ ] Proper Unicode-capable PDF font
  - [x] Repayment receipts
- [ ] Search and filtering upgrades
  - Filter by unit
  - Filter by overdue days
  - Filter by customer contact
  - Filter by category and stock state
- [x] Full analyzer cleanup
  - [x] Resolve remaining lints and warnings
  - [x] Work around local analyzer permission issue

## Notes

- The app is already strong in local POS checkout, inventory, Kopesha credit, repayments, and dashboard basics.
- We will implement the roadmap one milestone at a time and keep this file updated as each item ships.
- The next active milestone is `Receipt printing improvements`, with `Mobile polish` and `Search and filtering upgrades` still open after cloud sync completion shipped.
