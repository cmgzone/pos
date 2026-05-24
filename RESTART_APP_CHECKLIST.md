# ✅ Restart App Checklist

## The Problem
You can't see the Kopesha button or due date section because the app hasn't loaded the new payment methods from the database yet.

## The Solution
**Restart the app!**

---

## Step-by-Step Instructions

### 1. Stop the App
```bash
# In the terminal where Flutter is running, press:
Ctrl + C

# Or click the Stop button in your IDE
```

### 2. Start the App Again
```bash
flutter run
```

### 3. Navigate to Payment Dialog
1. Open the app
2. Go to **POS** screen
3. Add some items to cart
4. Click **"Checkout"** button

### 4. What You Should See Now

#### ✅ Payment Method Buttons (Top Section)
```
Payment Methods
┌──────┐ ┌──────┐ ┌──────┐ ┌──────────────┐
│ Cash │ │M-Pesa│ │ Card │ │Bank Transfer │
└──────┘ └──────┘ └──────┘ └──────────────┘
```

#### ✅ Credit Payment Section (Middle Section)
```
═══════════════════════════════════════════

Credit Payment (Kopesha)

Due Date
┌───────┐ ┌────────┐ ┌────────┐ ┌──────────┐
│7 Days │ │14 Days │ │30 Days │ │📅 Custom │
└───────┘ └────────┘ └────────┘ └──────────┘
```

#### ✅ Customer Section (Below Due Date)
```
Customer (Required for Kopesha)
┌─────────────────────────────────────┐
│ 🔍 Search customer...               │
└─────────────────────────────────────┘
```

#### ✅ Kopesha Button (Bottom Right)
```
[Cancel]              [Pay with Kopesha] 💰
```

---

## Quick Test

### Test 1: See the Due Date Section
- [ ] Open payment dialog
- [ ] Look for "Credit Payment (Kopesha)" heading
- [ ] See four due date options: 7 Days, 14 Days, 30 Days, Custom
- [ ] Click "7 Days" - should turn orange
- [ ] Click "14 Days" - should turn orange

### Test 2: See the Kopesha Button
- [ ] Look at bottom right of dialog
- [ ] See orange button labeled "Pay with Kopesha"
- [ ] Button has wallet icon 💰

### Test 3: Try Kopesha Payment (Without Customer)
- [ ] Click "Pay with Kopesha" button
- [ ] Should see error: "Please select a customer for Kopesha"
- [ ] This confirms the button is working!

### Test 4: Complete Kopesha Payment
- [ ] Select due date (e.g., 14 Days)
- [ ] Search for a customer
- [ ] Select a customer from the list
- [ ] Click "Pay with Kopesha" button
- [ ] Payment should complete successfully
- [ ] Customer balance should increase

---

## If You Still Don't See It

### Option 1: Hot Restart (Faster)
```bash
# In the terminal where Flutter is running, press:
R

# Or type:
r
```

### Option 2: Full Restart (Recommended)
```bash
# Stop the app completely
Ctrl + C

# Run again
flutter run
```

### Option 3: Clear and Rebuild
```bash
# Stop the app
flutter clean
flutter pub get
flutter run
```

### Option 4: Check Database
```bash
# Verify payment methods exist
sqlite3 .dart_tool/sqflite_common_ffi/databases/Piki_pos.db "SELECT name, is_credit FROM payment_methods ORDER BY sort_order;"

# Should show:
# Cash|0
# Kopesha|1  ← This is the key!
# M-Pesa|0
# Card|0
# Bank Transfer|0
```

---

## What I Already Fixed

✅ Created payment_methods table  
✅ Added Kopesha with is_credit = 1  
✅ Added 4 other payment methods  
✅ Added is_cash_drawer column to sales table  
✅ Seeded default data  

**Everything is ready in the database - the app just needs to restart to load it!**

---

## Visual Reference

### Before Restart (What You See Now)
```
Payment Dialog
├── Payment Methods: (empty or old data)
├── Customer section
└── Actions: [Cancel] [Cart] ← Wrong button
```

### After Restart (What You Should See)
```
Payment Dialog
├── Payment Methods: Cash, M-Pesa, Card, Bank Transfer
├── ═══════════════════════════════════════
├── Credit Payment (Kopesha)
│   └── Due Date: [7 Days] [14 Days] [30 Days] [Custom]
├── ───────────────────────────────────────
├── Customer section
│   └── Search and select customer
└── Actions: [Cancel] [Pay with Kopesha] ← Correct!
```

---

## Summary

1. ✅ Database is fixed (I already did this)
2. ⏳ **You need to:** Restart the app
3. ✅ Then you'll see: Due date section + Kopesha button
4. ✅ Then you can: Test Kopesha payments

**Just restart the app and everything will work!** 🚀

---

## Need Help?

If after restarting you still don't see it:
1. Check the console/terminal for errors
2. Run the database verification command above
3. Try hot restart (press R)
4. Try full restart (Ctrl+C then flutter run)

The code is correct, the database is fixed - it's just a matter of restarting the app to load the new data! 💪
