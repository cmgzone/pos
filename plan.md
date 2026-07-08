# Piki POS — Feature Gap Roadmap & Implementation Plan

## Goal
Close the competitive feature gaps vs Kenyan POS competitors (Forty POS, Kiotapay, Slade POS). Implement missing features end-to-end, mark each complete in `task.md` as it ships.

## Architecture: How a new sync-tracked feature is added (10 layers)

Every feature touches these layers. Reference: `expenses` is the cleanest model.

| # | Layer | File | What to do |
|---|-------|------|------------|
| 1 | PostgreSQL schema | `backend/sql/init.sql` | `CREATE TABLE IF NOT EXISTS` with `business_id`, `sync_status`, `created_at`, `updated_at`, `deleted_at` |
| 2 | Sync table registry | `backend/src/syncTables.js` | Add `{ name, columns: [...] }` to `syncTables` array |
| 3 | Backend routes | `backend/src/server.js` | Add inline routes (`app.get/post/put/delete`) following existing CRUD pattern + business scoping via `resolveBusinessAccess` |
| 4 | Entitlement keys | `backend/src/subscriptionPlans.js` | Add `FEATURE_KEYS.xxx`, add to plan feature lists (TRIAL/STARTER/GROWTH/ALL) |
| 5 | Flutter SQLite schema | `lib/core/services/database_service.dart` | Bump `_databaseVersion`, add `CREATE TABLE` in `_runMigrations`, add table to `_branchAwareTables` |
| 6 | Flutter repository | `lib/features/{name}/data/{name}_repository.dart` | CRUD methods with branch scoping (`COALESCE(branch_id, ?) = ?`) + audit logging |
| 7 | Flutter screen | `lib/features/{name}/presentation/{name}_screen.dart` | UI (mobile-first, clean spacing per taste) |
| 8 | Navigation | `lib/features/app/app_shell.dart` | Add nav item gated by `license.entitlements.features.contains(key)` |
| 9 | Entitlement gating | `lib/core/services/license_service.dart` + `session_service.dart` | Feature key wired into `allowsFeature` checks |
| 10 | Admin-web | `admin-web/src/...` | Plan feature management toggle (when applicable) |

## Key conventions (from codebase)
- Branch scoping: `COALESCE(branch_id, ?) = ?` with `DatabaseService.defaultBranchId` + `currentBranchId`
- Sync columns: every table has `sync_status`, `created_at`, `updated_at`, `deleted_at`
- IDs: UUID v4 (`Uuid().v4()`)
- Audit logging: `AuditLogService.log(...)` on every mutation
- Currency: KES (Kenyan market) — `ShopSettings.currencySymbolFor`
- Error handling: user-friendly messages, never raw dev errors (per taste)
- Subscription gating: features gated by plan entitlements (per taste)

---

## PHASE 1 — Critical (deal-breakers in demos)

### Feature 1: Loyalty & Rewards Program
**Entitlement key:** `loyalty` (GROWTH+ plans)
**New sync tables:** `loyalty_rules` (per-branch config), `loyalty_ledger` (customer point transactions)
**Modified table:** `customers` — add `loyalty_points` column

### Feature 2: Gift Cards / Vouchers
**Entitlement key:** `gift_cards` (GROWTH+ plans)
**New sync table:** `gift_cards`; new payment method `gift_card`

### Feature 3: Advanced Promotions Engine
**Entitlement key:** `promotions` (GROWTH+ plans)
**New sync tables:** `promotions`, `promotion_rules`

### Feature 4: Tax Reports (VAT/KRA)
**Entitlement key:** covered by `reports`
**New backend route group:** `/api/reports/*` (server-side generated reports)

### Feature 5: Custom Roles & Granular Permissions
**Entitlement key:** `custom_roles` (GROWTH+ plans)
**New sync table:** `custom_roles`; modified `users` table

---

## PHASE 2 — Significant (competitive parity)

### Feature 6: Supplier Aging / AP Reports
### Feature 7: Serial Number Tracking
### Feature 8: Stocktake / Cycle Counting
### Feature 9: Bulk SMS Marketing Campaigns
### Feature 10: Multi-Currency Support
### Feature 11: Inventory Reorder Suggestions
### Feature 12: Wastage / Spoilage Tracking

---

## PHASE 3 — Differentiators

### Feature 13: Restaurant / Hospitality Mode
### Feature 14: Full E-commerce Checkout
### Feature 15: Employee Attendance
### Feature 16: Customer Groups / Segments
### Feature 17: Purchase Approval Workflows
### Feature 18: Delivery Management
### Feature 19: Customer Self-Service Portal
### Feature 20: Advanced BI Dashboard

## Execution order
Implement features 1→20 sequentially. After each feature:
1. Run `flutter analyze` — must pass clean
2. Mark all sub-tasks `[x]` in task.md
3. Deploy to GitHub + migrate Neon DB (per taste)

## Verification
- After each feature: `flutter analyze` clean, manual smoke test of CRUD + sync
- Backend: `node src/initDb.js` to apply schema, restart server, hit new endpoints
- Full regression after each phase
