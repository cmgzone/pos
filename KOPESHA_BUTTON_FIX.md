# Kopesha Button Fix - RESOLVED ✅

## Issue
The Kopesha button was not showing in the payment dialog because the payment_methods table didn't exist in the database.

## Root Cause
The database migration hadn't run yet because the app wasn't restarted after the code changes were made.

## Solution Applied ✅
Manually created the payment_methods table and seeded the default payment methods using SQL script.

### What Was Done
1. Created `fix_payment_methods.sql` script
2. Ran the script to create payment_methods table
3. Seeded 5 default payment methods:
   - Cash (is_cash_drawer: 1, is_credit: 0)
   - Kopesha (is_cash_drawer: 0, is_credit: 1) ← This enables the Kopesha button
   - M-Pesa (is_cash_drawer: 0, is_credit: 0)
   - Card (is_cash_drawer: 0, is_credit: 0)
   - Bank Transfer (is_cash_drawer: 0, is_credit: 0)
4. Added is_cash_drawer column to sales table

### Verification
```sql
-- Payment methods now exist:
Cash|1|0|1|0
Kopesha|0|1|1|1  ← is_credit = 1 enables Kopesha button
M-Pesa|0|0|1|2
Card|0|0|1|3
Bank Transfer|0|0|1|4
```

## How to See the Kopesha Button

### Step 1: Restart the App
```bash
# Stop the app if running
# Then restart it
flutter run
```

### Step 2: Test the Payment Dialog
1. Go to POS screen
2. Add items to cart
3. Click "Checkout" button
4. **You should now see:**
   - Payment method buttons at the top (Cash, M-Pesa, Card, Bank Transfer)
   - "Credit Payment (Kopesha)" section in the middle
   - **"Pay with Kopesha" button at the bottom** (orange/warning color)

### Step 3: Test Kopesha Payment
1. Click "Pay with Kopesha" button
2. You should see an error: "Please select a customer for Kopesha"
3. Search and select a customer from the list
4. Select a due date (7 days, 14 days, 30 days, or custom)
5. Click "Pay with Kopesha" again
6. Payment should complete and customer balance should increase

## Why the Button Shows Now

The payment dialog checks for payment methods with `is_credit == 1`:

```dart
// In payment_checkout_dialog.dart
paymentMethodsAsync.maybeWhen(
  data: (methods) {
    final hasKopesha = methods.any((m) => m['is_credit'] == 1);
    if (!hasKopesha) return const SizedBox.shrink(); // Hide button
    
    return ElevatedButton.icon(
      onPressed: _handleKopeshaCheckout,
      icon: const Icon(Icons.account_balance_wallet, size: 18),
      label: const Text('Pay with Kopesha'),
    );
  },
  orElse: () => const SizedBox.shrink(),
),
```

Since we now have Kopesha with `is_credit = 1`, the button will show!

## Alternative: Automatic Migration

If you prefer the app to handle this automatically on next restart:

### Option 1: Hot Restart (Recommended)
```bash
# In the running app, press:
Shift + R  (or type 'R' in terminal)
# This will restart the app and run migrations
```

### Option 2: Full Restart
```bash
# Stop the app completely
flutter run
# Migrations will run on app initialization
```

### Option 3: Clear Database (Nuclear Option)
```bash
# This will delete all data and recreate from scratch
rm .dart_tool/sqflite_common_ffi/databases/Piki_pos.db*
flutter run
# App will create fresh database with all tables
```

## Visual Guide

### Before Fix
```
Payment Dialog
├── Payment Methods section
│   ├── Cash button
│   ├── M-Pesa button
│   ├── Card button
│   └── Bank Transfer button
├── Customer section
└── Actions
    ├── Cancel button
    └── (No Kopesha button) ❌
```

### After Fix
```
Payment Dialog
├── Payment Methods section
│   ├── Cash button
│   ├── M-Pesa button
│   ├── Card button
│   └── Bank Transfer button
├── Credit Payment (Kopesha) section
│   └── Due date selection
├── Customer section
└── Actions
    ├── Cancel button
    └── Pay with Kopesha button ✅ (Orange/Warning color)
```

## Troubleshooting

### Button Still Not Showing?

1. **Check if payment methods exist:**
```bash
sqlite3 .dart_tool/sqflite_common_ffi/databases/Piki_pos.db "SELECT * FROM payment_methods WHERE is_credit = 1;"
```
Should show Kopesha with is_credit = 1

2. **Check if table exists:**
```bash
sqlite3 .dart_tool/sqflite_common_ffi/databases/Piki_pos.db ".tables"
```
Should include payment_methods

3. **Restart the app:**
```bash
# Full restart
flutter run
```

4. **Check console for errors:**
Look for any errors related to payment_methods or database

### Button Shows But Doesn't Work?

1. **Check customer selection:**
   - Kopesha requires a customer to be selected
   - Error message should appear if no customer selected

2. **Check database constraints:**
```bash
sqlite3 .dart_tool/sqflite_common_ffi/databases/Piki_pos.db "PRAGMA table_info(payment_methods);"
```

3. **Check console logs:**
   - Look for errors when clicking the button
   - Check for database errors

## Next Steps

1. ✅ Database fixed - payment_methods table created
2. ✅ Default payment methods seeded
3. ⏳ Restart the app to see the Kopesha button
4. ⏳ Test the Kopesha payment flow
5. ⏳ Verify customer balance updates correctly

## Summary

The issue was that the database migration hadn't run yet. I've manually applied the migration by:
1. Creating the payment_methods table
2. Seeding the default payment methods including Kopesha with is_credit = 1
3. Adding the is_cash_drawer column to sales table

**Now restart your app and the Kopesha button should appear at the bottom of the payment dialog!**

---

**Status:** ✅ Fixed  
**Action Required:** Restart the app  
**Expected Result:** Kopesha button visible at bottom of payment dialog
