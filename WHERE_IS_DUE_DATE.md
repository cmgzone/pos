# Where to Find the Due Date Selection

## Payment Dialog Layout

After restarting the app, the payment dialog will look like this:

```
┌─────────────────────────────────────────────────────────┐
│  📦 Select Payment Method                               │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  💰 Sale Total: $100.00                                 │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│                                                         │
│  Payment Methods                                        │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────────────┐          │
│  │ Cash │ │M-Pesa│ │ Card │ │Bank Transfer │          │
│  └──────┘ └──────┘ └──────┘ └──────────────┘          │
│                                                         │
│  ═════════════════════════════════════════════════════  │
│                                                         │
│  Credit Payment (Kopesha)                              │
│                                                         │
│  Due Date                                              │
│  ┌───────┐ ┌────────┐ ┌────────┐ ┌──────────┐        │
│  │7 Days │ │14 Days │ │30 Days │ │📅 Custom │  ← HERE │
│  └───────┘ └────────┘ └────────┘ └──────────┘        │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│                                                         │
│  Customer (Required for Kopesha)                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │ 🔍 Search customer...                           │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  [Customer list appears here when you search]          │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                          [Cancel] [Pay with Kopesha] 💰│
└─────────────────────────────────────────────────────────┘
```

## Step-by-Step Location

### 1. Open Payment Dialog
- Go to POS screen
- Add items to cart
- Click "Checkout"

### 2. Scroll Down (if needed)
The dialog has several sections from top to bottom:
1. **Sale Total** (at the top)
2. **Payment Methods** buttons (Cash, M-Pesa, Card, Bank Transfer)
3. **Divider line** (horizontal line)
4. **"Credit Payment (Kopesha)"** heading ← Look for this!
5. **"Due Date"** label
6. **Due date chips** (7 Days, 14 Days, 30 Days, Custom) ← HERE!
7. **Another divider line**
8. **Customer section** (search and select customer)
9. **Buttons at bottom** (Cancel, Pay with Kopesha)

### 3. The Due Date Section
It's located:
- ✅ **After** the payment method buttons (Cash, M-Pesa, etc.)
- ✅ **After** a divider line
- ✅ **Under** the "Credit Payment (Kopesha)" heading
- ✅ **Before** the customer search section

## What the Due Date Chips Look Like

### Default State (14 Days selected)
```
Due Date
┌───────┐ ┌────────┐ ┌────────┐ ┌──────────────┐
│7 Days │ │14 Days │ │30 Days │ │📅 12/15/2024 │
└───────┘ └────────┘ └────────┘ └──────────────┘
          ↑ Orange/highlighted
```

### After Clicking "7 Days"
```
Due Date
┌───────┐ ┌────────┐ ┌────────┐ ┌──────────────┐
│7 Days │ │14 Days │ │30 Days │ │📅 12/8/2024  │
└───────┘ └────────┘ └────────┘ └──────────────┘
↑ Orange/highlighted
```

### After Clicking Custom Date Button
A date picker will appear where you can select any future date.

## Why You Might Not See It

### Reason 1: App Not Restarted ❌
**Solution:** Restart the app
```bash
# Stop the app
# Run again
flutter run
```

### Reason 2: No Kopesha Payment Method ❌
The due date section only shows if Kopesha exists in the database.

**Check:**
```bash
sqlite3 .dart_tool/sqflite_common_ffi/databases/velora_pos.db "SELECT name, is_credit FROM payment_methods WHERE is_credit = 1;"
```

Should show:
```
Kopesha|1
```

**Solution:** I already fixed this - just restart the app!

### Reason 3: Dialog Too Small ❌
If your screen is small, you might need to scroll down in the dialog.

**Solution:** Scroll down in the dialog to see the Kopesha section.

### Reason 4: Payment Methods Not Loading ❌
Check the console for errors when opening the payment dialog.

**Solution:** Look for error messages in the terminal/console.

## How to Use the Due Date

### Quick Presets
1. Click "7 Days" - Due date will be 7 days from today
2. Click "14 Days" - Due date will be 14 days from today (default)
3. Click "30 Days" - Due date will be 30 days from today

### Custom Date
1. Click the date button (shows current selected date like "📅 12/15/2024")
2. A calendar picker will appear
3. Select any future date
4. Click OK

### Visual Feedback
- **Selected chip:** Orange/yellow background with orange border
- **Unselected chips:** Gray background with gray border
- **Custom date button:** Shows the currently selected date

## Complete Kopesha Payment Flow

1. **Open checkout dialog**
2. **Scroll to "Credit Payment (Kopesha)" section**
3. **Select due date** (7 Days, 14 Days, 30 Days, or Custom)
4. **Scroll down to customer section**
5. **Search and select a customer** (required!)
6. **Click "Pay with Kopesha" button at the bottom**
7. **Payment completes** - customer balance increases

## Testing the Due Date

### Test 1: Select 7 Days
1. Open payment dialog
2. Find "Credit Payment (Kopesha)" section
3. Click "7 Days" chip
4. Chip should turn orange
5. Custom date button should show date 7 days from today

### Test 2: Select Custom Date
1. Click the date button (📅 with date)
2. Calendar picker appears
3. Select a date (e.g., 2 weeks from now)
4. Click OK
5. Date button should show your selected date
6. All preset chips (7/14/30 Days) should be unselected (gray)

### Test 3: Complete Payment
1. Select due date (e.g., 14 Days)
2. Select a customer
3. Click "Pay with Kopesha"
4. Check customer account - balance should increase by sale amount
5. Check customer details - should show due date you selected

## Troubleshooting

### "I still don't see the due date section"

**Step 1:** Verify Kopesha exists
```bash
sqlite3 .dart_tool/sqflite_common_ffi/databases/velora_pos.db "SELECT * FROM payment_methods WHERE name = 'Kopesha';"
```

**Step 2:** Restart the app
```bash
flutter run
```

**Step 3:** Check console for errors
Look for any errors when opening the payment dialog

**Step 4:** Try hot restart
Press `R` in the terminal where Flutter is running

### "The section is there but looks different"

That's okay! The important parts are:
- ✅ "Due Date" label
- ✅ Clickable chips (7 Days, 14 Days, 30 Days)
- ✅ Date button for custom date
- ✅ Visual feedback when clicking (chip turns orange)

## Summary

**Location:** Middle of the payment dialog, between payment method buttons and customer section

**Look for:**
1. Divider line
2. "Credit Payment (Kopesha)" heading
3. "Due Date" label
4. Four clickable options: 7 Days, 14 Days, 30 Days, Custom date

**Action needed:** Restart the app to load the payment methods from the database

**The due date section is already in the code - just restart the app to see it!** 🚀

---

**Quick Check:**
```bash
# 1. Verify database is fixed
sqlite3 .dart_tool/sqflite_common_ffi/databases/velora_pos.db "SELECT name FROM payment_methods;"

# Should show:
# Cash
# Kopesha  ← This makes the due date section appear
# M-Pesa
# Card
# Bank Transfer

# 2. Restart app
flutter run

# 3. Go to POS → Add items → Checkout → Look for "Credit Payment (Kopesha)" section
```
