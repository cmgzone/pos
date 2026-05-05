# Neon Database Migration Guide - Payment Methods

## Overview

This guide covers migrating the Velora POS database schema to Neon PostgreSQL to include the new payment methods system.

## Changes Made

### 1. Database Schema Updates

#### New Table: `payment_methods`
```sql
CREATE TABLE payment_methods (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  is_cash_drawer integer NOT NULL DEFAULT 0,
  is_credit integer NOT NULL DEFAULT 0,
  is_active integer NOT NULL DEFAULT 1,
  sort_order integer NOT NULL DEFAULT 0,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);
```

**Indexes:**
- `idx_payment_methods_business_revision` - For cursor-based sync
- `idx_payment_methods_business_active` - For active methods lookup
- `idx_payment_methods_sort_order` - For ordered display

#### Updated Table: `sales`
```sql
ALTER TABLE sales ADD COLUMN is_cash_drawer integer NOT NULL DEFAULT 0;
```

**Index:**
- `idx_sales_is_cash_drawer` - For cash drawer queries

### 2. Backend Sync Configuration

Updated `backend/src/syncTables.js`:
- Added `payment_methods` to sync tables list
- Added `is_cash_drawer` to sales columns

## Migration Steps

### Step 1: Backup Your Database

```bash
# If using Neon, create a branch for safety
# Or export your current data
pg_dump $NEON_DATABASE_URL > backup_before_payment_migration.sql
```

### Step 2: Run the Migration

#### Option A: Using the Migration File (Recommended)

```bash
cd backend
psql $NEON_DATABASE_URL -f sql/migration_payment_methods.sql
```

#### Option B: Using the Updated init.sql

```bash
cd backend
npm run db:init
```

This will run the complete `sql/init.sql` which now includes payment methods.

### Step 3: Seed Default Payment Methods

For each existing business, seed default payment methods:

```sql
-- Replace 'YOUR_BUSINESS_ID' with actual business ID
DO $$
DECLARE
  business_id_var text := 'YOUR_BUSINESS_ID';
BEGIN
  -- Cash
  INSERT INTO payment_methods (
    id, business_id, name, is_cash_drawer, is_credit, is_active, 
    sort_order, created_at, updated_at, sync_status
  ) VALUES (
    gen_random_uuid()::text,
    business_id_var,
    'Cash',
    1, 0, 1, 0,
    NOW(), NOW(), 'synced'
  ) ON CONFLICT (id) DO NOTHING;

  -- Kopesha
  INSERT INTO payment_methods (
    id, business_id, name, is_cash_drawer, is_credit, is_active, 
    sort_order, created_at, updated_at, sync_status
  ) VALUES (
    gen_random_uuid()::text,
    business_id_var,
    'Kopesha',
    0, 1, 1, 1,
    NOW(), NOW(), 'synced'
  ) ON CONFLICT (id) DO NOTHING;

  -- M-Pesa
  INSERT INTO payment_methods (
    id, business_id, name, is_cash_drawer, is_credit, is_active, 
    sort_order, created_at, updated_at, sync_status
  ) VALUES (
    gen_random_uuid()::text,
    business_id_var,
    'M-Pesa',
    0, 0, 1, 2,
    NOW(), NOW(), 'synced'
  ) ON CONFLICT (id) DO NOTHING;

  -- Card
  INSERT INTO payment_methods (
    id, business_id, name, is_cash_drawer, is_credit, is_active, 
    sort_order, created_at, updated_at, sync_status
  ) VALUES (
    gen_random_uuid()::text,
    business_id_var,
    'Card',
    0, 0, 1, 3,
    NOW(), NOW(), 'synced'
  ) ON CONFLICT (id) DO NOTHING;

  -- Bank Transfer
  INSERT INTO payment_methods (
    id, business_id, name, is_cash_drawer, is_credit, is_active, 
    sort_order, created_at, updated_at, sync_status
  ) VALUES (
    gen_random_uuid()::text,
    business_id_var,
    'Bank Transfer',
    0, 0, 1, 4,
    NOW(), NOW(), 'synced'
  ) ON CONFLICT (id) DO NOTHING;
END $$;
```

#### Seed for All Businesses

```sql
-- Seed default payment methods for all existing businesses
INSERT INTO payment_methods (
  id, business_id, name, is_cash_drawer, is_credit, is_active, 
  sort_order, created_at, updated_at, sync_status
)
SELECT 
  gen_random_uuid()::text,
  b.id,
  method.name,
  method.is_cash_drawer,
  method.is_credit,
  1, -- is_active
  method.sort_order,
  NOW(),
  NOW(),
  'synced'
FROM businesses b
CROSS JOIN (
  VALUES 
    ('Cash', 1, 0, 0),
    ('Kopesha', 0, 1, 1),
    ('M-Pesa', 0, 0, 2),
    ('Card', 0, 0, 3),
    ('Bank Transfer', 0, 0, 4)
) AS method(name, is_cash_drawer, is_credit, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM payment_methods pm 
  WHERE pm.business_id = b.id AND pm.name = method.name
);
```

### Step 4: Backfill Existing Sales Data

Update existing sales to set `is_cash_drawer` flag:

```sql
-- Set is_cash_drawer = 1 for all cash sales
UPDATE sales 
SET is_cash_drawer = 1 
WHERE LOWER(payment_type) = 'cash' 
  AND is_cash_drawer = 0
  AND deleted_at IS NULL;

-- Verify the update
SELECT 
  payment_type,
  is_cash_drawer,
  COUNT(*) as count
FROM sales
WHERE deleted_at IS NULL
GROUP BY payment_type, is_cash_drawer
ORDER BY payment_type;
```

### Step 5: Verify Migration

```sql
-- Check payment_methods table exists
SELECT COUNT(*) FROM payment_methods;

-- Check sales has is_cash_drawer column
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sales' AND column_name = 'is_cash_drawer';

-- Check indexes were created
SELECT indexname 
FROM pg_indexes 
WHERE tablename IN ('payment_methods', 'sales')
  AND indexname LIKE '%payment%' OR indexname LIKE '%cash_drawer%';

-- Verify default payment methods per business
SELECT 
  b.name as business_name,
  COUNT(pm.id) as payment_methods_count
FROM businesses b
LEFT JOIN payment_methods pm ON pm.business_id = b.id
GROUP BY b.id, b.name
ORDER BY b.name;
```

### Step 6: Restart Backend Server

```bash
cd backend
npm run start
```

The backend will now sync payment_methods table with Flutter clients.

## Files Modified

### Backend Files
1. ✅ `backend/sql/init.sql` - Added payment_methods table and is_cash_drawer column
2. ✅ `backend/sql/migration_payment_methods.sql` - **NEW** - Standalone migration file
3. ✅ `backend/src/syncTables.js` - Added payment_methods to sync configuration

### Flutter Files (Already Done)
1. ✅ `lib/core/services/database_service.dart` - Local SQLite schema
2. ✅ `lib/features/settings/data/payment_method_repository.dart` - Repository
3. ✅ `lib/features/sales/presentation/payment_checkout_dialog.dart` - UI
4. ✅ `lib/core/services/seed_service.dart` - Local seeding

## Testing Checklist

### Backend Testing

- [ ] Run migration on Neon database
- [ ] Verify payment_methods table exists
- [ ] Verify sales.is_cash_drawer column exists
- [ ] Seed default payment methods for test business
- [ ] Restart backend server
- [ ] Check backend logs for errors

### Sync Testing

- [ ] Open Flutter app
- [ ] Trigger sync (Settings → Sync)
- [ ] Verify payment methods sync down from Neon
- [ ] Create new payment method in app
- [ ] Verify it syncs up to Neon
- [ ] Check Neon database for new payment method

### Sales Testing

- [ ] Create cash sale in app
- [ ] Verify `is_cash_drawer = 1` in local DB
- [ ] Sync to Neon
- [ ] Verify `is_cash_drawer = 1` in Neon
- [ ] Create M-Pesa sale
- [ ] Verify `is_cash_drawer = 0` in both DBs

### Report Testing (Future)

Once reports are updated to use payment method flags:
- [ ] Shift reports show correct cash totals
- [ ] Sales analytics include all payment methods
- [ ] Profit/loss reports are accurate

## Rollback Plan

If something goes wrong:

```sql
-- Drop payment_methods table
DROP TABLE IF EXISTS payment_methods CASCADE;

-- Remove is_cash_drawer column from sales
ALTER TABLE sales DROP COLUMN IF EXISTS is_cash_drawer;

-- Remove from sync configuration
-- Edit backend/src/syncTables.js and remove payment_methods entry
```

Then restore from backup:
```bash
psql $NEON_DATABASE_URL < backup_before_payment_migration.sql
```

## Common Issues

### Issue 1: "relation payment_methods does not exist"

**Solution:** Run the migration:
```bash
psql $NEON_DATABASE_URL -f backend/sql/migration_payment_methods.sql
```

### Issue 2: Sync fails with "unknown table payment_methods"

**Solution:** Restart the backend server after migration:
```bash
cd backend
npm run start
```

### Issue 3: No default payment methods after migration

**Solution:** Run the seed script for your business (Step 3 above)

### Issue 4: Existing sales don't have is_cash_drawer set

**Solution:** Run the backfill script (Step 4 above)

## Production Deployment

### Pre-Deployment

1. **Test on staging** with a copy of production data
2. **Notify users** of brief downtime (if needed)
3. **Backup production database**
4. **Schedule during low-traffic period**

### Deployment Steps

1. **Backup production Neon database**
2. **Run migration** on production Neon
3. **Seed default payment methods** for all businesses
4. **Backfill existing sales data**
5. **Deploy updated backend** code
6. **Deploy updated Flutter app** (or trigger sync)
7. **Monitor logs** for sync errors
8. **Verify** with test transactions

### Post-Deployment

1. Monitor sync logs for 24 hours
2. Check that new sales have correct `is_cash_drawer` values
3. Verify payment methods appear in all client apps
4. Collect user feedback

## Support

If you encounter issues:

1. Check backend logs: `npm run start` output
2. Check Neon query logs in Neon console
3. Verify schema with: `\d payment_methods` in psql
4. Check sync status in Flutter app
5. Review `PAYMENT_SYSTEM_FIX.md` for technical details

## Next Steps

After successful migration:

1. **Update reports** to use payment method flags (see `PAYMENT_SYSTEM_FIX.md`)
2. **Add payment method analytics** dashboard
3. **Implement payment method icons** in UI
4. **Add payment method filtering** in reports
5. **Create admin panel** for payment method management

---

**Migration Status:** ✅ **READY TO DEPLOY**  
**Estimated Downtime:** < 5 minutes  
**Risk Level:** Low (additive changes only)  
**Rollback Time:** < 2 minutes  
