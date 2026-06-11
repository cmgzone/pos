# How to Import Products via Excel/CSV

## 📍 Where to Find Import Feature

### On Desktop/Tablet (Large Screen):
1. Open the app
2. Navigate to **Products** section (from sidebar or main menu)
3. Look for the **"Import"** button at the top of the products list
4. Click **"Import"** button with upload icon (📤)

### On Mobile (Small Screen):
1. Open the app
2. Navigate to **Products** section
3. Tap the **three-dot menu** (⋮) at the top right
4. Select **"Import Products"** from the dropdown menu

---

## 📊 Excel/CSV File Format

### Supported File Types:
- ✅ **Excel (.xlsx)**
- ✅ **CSV (.csv)**

### Required Columns:

Your spreadsheet must have at least ONE of these identifier columns:
- **name** - Product name (required for new products)
- **sku** - Stock Keeping Unit code
- **barcode** - Product barcode

### Recommended Columns:

| Column Name | Description | Example | Required |
|-------------|-------------|---------|----------|
| `name` | Product name | "Coca Cola 500ml" | ✅ Yes (for new) |
| `price` | Selling price | 50 | ✅ Recommended |
| `cost` | Cost price | 35 | ⚠️ Optional |
| `sku` | Product SKU | "CC-500" | ⚠️ Optional |
| `barcode` | Barcode number | "123456789" | ⚠️ Optional |
| `category` | Category name | "Beverages" | ⚠️ Optional |
| `stock` | Current stock | 100 | ⚠️ Optional |
| `low_stock` | Reorder level | 10 | ⚠️ Optional |
| `unit` | Unit of measure | "pcs", "kg", "liter" | ⚠️ Optional |
| `brand` | Brand name | "Coca Cola" | ⚠️ Optional |
| `track_stock` | Track inventory | TRUE/FALSE | ⚠️ Optional |
| `image_url` | Product image URL | "https://..." | ⚠️ Optional |

### Advanced Columns (Stock Management):

| Column Name | Description | Example |
|-------------|-------------|---------|
| `stock_unit` | Unit for stock tracking | "pieces" |
| `sale_unit` | Unit for sales | "pack" |
| `sale_to_stock_factor` | Conversion factor | 6 (1 pack = 6 pieces) |
| `purchase_unit` | Unit for purchasing | "carton" |
| `purchase_to_stock_factor` | Purchase conversion | 24 (1 carton = 24 pieces) |
| `expiry_date` | Product expiry | "2026-12-31" |
| `batch_number` | Batch/lot number | "BATCH-001" |

---

## 📝 Sample Excel Template

### Example 1: Basic Product Import

| name | price | cost | sku | barcode | category | stock | low_stock | unit |
|------|-------|------|-----|---------|----------|-------|-----------|------|
| Coca Cola 500ml | 50 | 35 | CC-500 | 12345 | Beverages | 100 | 10 | pcs |
| Fanta Orange 500ml | 50 | 35 | FO-500 | 12346 | Beverages | 80 | 10 | pcs |
| Bread White | 60 | 45 | BR-001 | 12347 | Bakery | 50 | 5 | pcs |
| Milk 1L | 120 | 90 | ML-001 | 12348 | Dairy | 30 | 5 | liter |

### Example 2: With Stock Units

| name | price | stock | stock_unit | sale_unit | sale_to_stock_factor |
|------|-------|-------|------------|-----------|---------------------|
| Soda Cans | 50 | 144 | cans | pack | 6 |
| Water Bottles | 30 | 240 | bottles | carton | 24 |

### Example 3: Update Existing Products

To update existing products, include the `sku` or `barcode` that matches your existing inventory:

| sku | price | stock |
|-----|-------|-------|
| CC-500 | 55 | 120 |
| FO-500 | 55 | 90 |

---

## 🚀 Import Process

### Step-by-Step:

1. **Prepare Your Excel/CSV File**
   - Use the template above
   - Fill in your product data
   - Save as `.xlsx` or `.csv`

2. **Open Import Dialog**
   - Desktop: Click "Import" button
   - Mobile: Menu (⋮) → "Import Products"

3. **Select Your File**
   - File picker dialog will appear
   - Select your Excel or CSV file
   - Click "Open"

4. **AI Import Preview** (Piki AI Check)
   - Piki AI analyzes your file
   - Shows column mapping
   - Displays preview of products to import
   - Shows warnings for any issues

5. **Review Preview**
   - Check detected columns
   - Verify product count
   - Read any AI suggestions

6. **Confirm Import**
   - Click **"Import Products"** button
   - Wait for import to complete

7. **View Results**
   - Success message shows:
     - Number of products created
     - Number of products updated
     - Number of stock batches received
     - Any errors encountered

---

## 🤖 AI-Powered Features

Piki AI automatically:
- ✅ **Detects column names** (even with different spelling)
- ✅ **Maps data correctly** (name, price, sku, etc.)
- ✅ **Validates data** (checks for errors)
- ✅ **Suggests fixes** (if something looks wrong)
- ✅ **Creates categories** (if they don't exist)
- ✅ **Matches existing products** (updates instead of duplicating)

---

## ✅ Import Behavior

### Creating New Products:
- If `sku` or `barcode` doesn't exist → **New product created**
- Requires: `name` column
- Optional: all other columns

### Updating Existing Products:
- If `sku` or `barcode` matches → **Existing product updated**
- Updates: price, cost, and other provided columns
- Doesn't change: product name (unless you want to)

### Adding Stock:
- If product exists and you provide `stock` → **Stock added**
- Creates new stock batch
- Tracks with `expiry_date` and `batch_number` if provided

### Creating Categories:
- If category doesn't exist → **Category created automatically**
- Categories are matched by name
- Case-insensitive matching

---

## 📋 Column Name Variations

Piki AI understands different column names:

### Product Name:
- `name`, `product_name`, `product`, `item_name`, `item`

### Price:
- `price`, `selling_price`, `sale_price`, `retail_price`

### Cost:
- `cost`, `cost_price`, `buy_price`, `purchase_price`

### SKU:
- `sku`, `code`, `product_code`, `item_code`

### Stock:
- `stock`, `quantity`, `qty`, `inventory`, `stock_quantity`

### Category:
- `category`, `category_name`, `product_category`

**The AI is smart enough to detect what each column contains!**

---

## ⚠️ Common Issues & Solutions

### Issue 1: "No name column found"
**Solution:** Make sure your Excel has a column called `name`, `product_name`, or similar.

### Issue 2: "Price must be greater than zero"
**Solution:** Check that price column has valid numbers, not text or empty cells.

### Issue 3: Products duplicated instead of updated
**Solution:** Include `sku` or `barcode` column to match existing products.

### Issue 4: Categories not matching
**Solution:** Use exact category names as they appear in your system (or new ones will be created).

### Issue 5: Stock not updated
**Solution:** Make sure `track_stock` is TRUE for products you want to track inventory.

### Issue 6: Import button disabled/grayed out
**Solution:** Wait for any previous import to finish. Only one import can run at a time.

---

## 💡 Tips & Best Practices

### 1. **Start Small**
- Test with 5-10 products first
- Verify the import works correctly
- Then import your full catalog

### 2. **Use Unique SKUs**
- Assign unique SKU codes to each product
- Makes updating easier
- Prevents duplicates

### 3. **Keep a Master File**
- Save your Excel file as a master template
- Use it for future imports
- Makes bulk updates easy

### 4. **Include Categories**
- Add category column
- Keeps products organized
- Categories created automatically

### 5. **Track Stock from Start**
- Set `track_stock` to TRUE
- Include initial stock quantities
- Set `low_stock` reorder levels

### 6. **Use Consistent Units**
- Standardize units (pcs, kg, liter, etc.)
- Set up unit conversions
- Accurate for multi-unit products

---

## 📥 Download Sample Template

Create an Excel file with these headers:

```
name | price | cost | sku | barcode | category | stock | low_stock | unit | track_stock
```

**Example data:**
```
Coca Cola 500ml | 50 | 35 | CC-500 | 12345 | Beverages | 100 | 10 | pcs | TRUE
Fanta Orange 500ml | 50 | 35 | FO-500 | 12346 | Beverages | 80 | 10 | pcs | TRUE
```

---

## 🔄 Re-Importing / Updating Products

To update existing products in bulk:

1. **Export your current products** (if available)
2. **Edit in Excel:**
   - Keep the `sku` or `barcode` columns
   - Change prices, stock, or other data
3. **Re-import the file**
4. Piki will:
   - Match by SKU/barcode
   - Update the changed fields
   - Keep unchanged data intact

---

## 📞 Troubleshooting

### Still Having Issues?

1. **Check file format:**
   - Use `.xlsx` (Excel) or `.csv`
   - Remove any special formatting
   - Plain text in cells only

2. **Check column headers:**
   - Must be in first row
   - Simple names (avoid special characters)
   - No merged cells

3. **Check data format:**
   - Numbers for price/cost/stock
   - Text for names
   - TRUE/FALSE for boolean fields
   - YYYY-MM-DD for dates

4. **Check file size:**
   - Keep under 10,000 products per import
   - Split large catalogs into batches

5. **Contact support** if issue persists

---

## 🎯 Quick Reference

**Location:**
- Desktop: Products → Import button
- Mobile: Products → Menu (⋮) → Import Products

**File Types:**
- Excel (.xlsx) ✅
- CSV (.csv) ✅

**Minimum Required:**
- `name` column (for new products)
- OR `sku`/`barcode` (for updates)

**AI Features:**
- Smart column detection ✅
- Auto category creation ✅
- Duplicate prevention ✅
- Data validation ✅

---

**That's it!** You're ready to import products into Piki POS using Excel or CSV files. 🚀

The AI-powered import makes it easy, even if your column names don't match exactly. Just prepare your file and let Piki do the rest!
