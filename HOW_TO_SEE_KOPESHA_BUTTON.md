# How to See the Kopesha Button

## ✅ FIXED - Database Updated!

The payment_methods table has been created and Kopesha has been added to your database.

---

## Quick Steps to See the Button

### 1. Restart Your App
```bash
# Stop the app (Ctrl+C in terminal or stop button)
# Then run again:
flutter run
```

### 2. Go to Checkout
1. Open the app
2. Go to POS screen
3. Add some items to cart
4. Click **"Checkout"** button

### 3. Look for the Kopesha Button
The payment dialog will show:

```
┌─────────────────────────────────────────┐
│  Select Payment Method                  │
├─────────────────────────────────────────┤
│                                         │
│  Payment Methods:                       │
│  [Cash] [M-Pesa] [Card] [Bank Transfer]│
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  Credit Payment (Kopesha)               │
│  Due Date: [7 Days] [14 Days] [30 Days]│
│                                         │
│  ─────────────────────────────────────  │
│                                         │
│  Customer (Required for Kopesha):       │
│  [Search customer...]                   │
│                                         │
├─────────────────────────────────────────┤
│  [Cancel]      [Pay with Kopesha] ← HERE│
└─────────────────────────────────────────┘
```

The **"Pay with Kopesha"** button is at the **bottom right** of the dialog, next to the Cancel button.

---

## Button Appearance

- **Color:** Orange/Yellow (Warning color)
- **Icon:** Wallet icon 💰
- **Text:** "Pay with Kopesha"
- **Location:** Bottom right of dialog (in actions section)

---

## Testing the Button

### Test 1: Without Customer (Should Show Error)
1. Click "Checkout"
2. Click "Pay with Kopesha" button
3. **Expected:** Error message "Please select a customer for Kopesha"

### Test 2: With Customer (Should Work)
1. Click "Checkout"
2. Search and select a customer
3. Select a due date (e.g., 14 Days)
4. Click "Pay with Kopesha" button
5. **Expected:** Payment completes, customer balance increases

---

## What Was Fixed

I manually ran this SQL to fix your database:

```sql
-- Created payment_methods table
CREATE TABLE payment_methods (...);

-- Added 5 payment methods including:
INSERT INTO payment_methods VALUES
  ('pm-kopesha-001', 'Kopesha', 0, 1, 1, 1, ...);
  --                              ↑ is_credit = 1
  -- This flag makes the Kopesha button appear!
```

---

## Verification

Check if payment methods exist:
```bash
sqlite3 .dart_tool/sqflite_common_ffi/databases/velora_pos.db "SELECT name, is_credit FROM payment_methods;"
```

Should show:
```
Cash|0
Kopesha|1  ← This makes the button show!
M-Pesa|0
Card|0
Bank Transfer|0
```

---

## Still Not Seeing It?

### Option 1: Hot Restart
Press `R` in the terminal where Flutter is running

### Option 2: Full Restart
```bash
# Stop the app
# Run again
flutter run
```

### Option 3: Check Database
```bash
sqlite3 .dart_tool/sqflite_common_ffi/databases/velora_pos.db "SELECT * FROM payment_methods WHERE name = 'Kopesha';"
```

Should show Kopesha with is_credit = 1

---

## Summary

✅ Database fixed  
✅ Payment methods created  
✅ Kopesha added with is_credit = 1  
⏳ **Action needed:** Restart your app  
🎯 **Result:** Kopesha button will appear at bottom of payment dialog

---

**The button is there - just restart the app to see it!** 🚀
