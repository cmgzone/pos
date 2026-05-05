# Quick Migration Steps - Payment Methods to Neon

## 🚀 Fast Track (5 Minutes)

### 1. Backup (30 seconds)
```bash
pg_dump $NEON_DATABASE_URL > backup.sql
```

### 2. Run Migration (1 minute)
```bash
cd backend
psql $NEON_DATABASE_URL -f sql/migration_payment_methods.sql
```

### 3. Seed Payment Methods (2 minutes)
```sql
-- Connect to Neon
psql $NEON_DATABASE_URL

-- Seed for all businesses
INSERT INTO payment_methods (
  id, business_id, name, is_cash_drawer, is_credit, is_active, 
  sort_order, created_at, updated_at, sync_status
)
SELECT 
  gen_random_uuid()::text, b.id, method.name,
  method.is_cash_drawer, method.is_credit, 1,
  method.sort_order, NOW(), NOW(), 'synced'
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

### 4. Backfill Sales (30 seconds)
```sql
UPDATE sales 
SET is_cash_drawer = 1 
WHERE LOWER(payment_type) = 'cash' 
  AND is_cash_drawer = 0
  AND deleted_at IS NULL;
```

### 5. Restart Backend (1 minute)
```bash
cd backend
npm run start
```

## ✅ Verify (1 minute)

```sql
-- Check payment methods exist
SELECT COUNT(*) FROM payment_methods;

-- Check sales column exists
\d sales

-- Check per business
SELECT b.name, COUNT(pm.id) as methods
FROM businesses b
LEFT JOIN payment_methods pm ON pm.business_id = b.id
GROUP BY b.name;
```

## 🎉 Done!

Your Neon database now supports the flexible payment system.

---

## 📋 Checklist

- [ ] Backup created
- [ ] Migration ran successfully
- [ ] Payment methods seeded
- [ ] Sales backfilled
- [ ] Backend restarted
- [ ] Verification passed
- [ ] Flutter app synced

---

## 🆘 Quick Rollback

```sql
DROP TABLE IF EXISTS payment_methods CASCADE;
ALTER TABLE sales DROP COLUMN IF EXISTS is_cash_drawer;
```

Then restore:
```bash
psql $NEON_DATABASE_URL < backup.sql
```

---

**Total Time:** ~5 minutes  
**Downtime:** ~1 minute (backend restart)  
**Risk:** Low ✅
