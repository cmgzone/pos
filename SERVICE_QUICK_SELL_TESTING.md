# Service Quick Sell - Testing Guide

## Pre-Testing Setup

### Requirements
1. ✅ At least one active service in the system
2. ✅ Service has a base price set
3. ✅ User has permission to access POS services
4. ✅ Cart functionality is working

### Test Environment
- Navigate to: **POS → Services Tab**
- Ensure you're in the Service Desk view

---

## Test Cases

### Test 1: Quick Sell Mode - Add Service to Cart
**Steps:**
1. Ensure "Quick Sell" mode is selected (should be default)
2. Click on any service card
3. Observe the snackbar notification

**Expected Results:**
- ✅ Snackbar appears: "✓ [Service Name] added to cart"
- ✅ Cart count increases by 1
- ✅ Service appears in cart with correct name and price
- ✅ No dialog opens

**Pass/Fail:** ___________

---

### Test 2: Quick Sell Mode - Visual Indicators
**Steps:**
1. Ensure "Quick Sell" mode is selected
2. Observe the service cards

**Expected Results:**
- ✅ "Quick Sell" button is highlighted/selected
- ✅ Each service card shows a green "Quick ⚡" badge
- ✅ Lightning icon visible in toggle button

**Pass/Fail:** ___________

---

### Test 3: Queue Mode - Open Service Order Dialog
**Steps:**
1. Click "Queue" in the mode toggle
2. Click on any service card
3. Observe the behavior

**Expected Results:**
- ✅ "Queue" button is highlighted/selected
- ✅ Service order dialog opens
- ✅ Dialog shows customer name field, custom fields, etc.
- ✅ No "Quick" badge on service cards

**Pass/Fail:** ___________

---

### Test 4: Mode Toggle - Switch Between Modes
**Steps:**
1. Start in "Quick Sell" mode
2. Click "Queue" button
3. Click "Quick Sell" button again
4. Repeat several times

**Expected Results:**
- ✅ Mode switches instantly without page reload
- ✅ Visual indicators update immediately
- ✅ Service card badges appear/disappear correctly
- ✅ No errors in console

**Pass/Fail:** ___________

---

### Test 5: Quick Sell - Multiple Services
**Steps:**
1. Ensure "Quick Sell" mode is selected
2. Click service card #1
3. Wait for snackbar to appear
4. Click service card #2
5. Click service card #3

**Expected Results:**
- ✅ All three services added to cart
- ✅ Cart count shows 3 items
- ✅ Each service has correct name and price
- ✅ Snackbar appears for each addition

**Pass/Fail:** ___________

---

### Test 6: Quick Sell - Checkout Flow
**Steps:**
1. Add a service using Quick Sell
2. Navigate to cart (or open cart panel)
3. Click "Checkout"
4. Select payment method (Cash/Kopesha)
5. Complete payment

**Expected Results:**
- ✅ Service appears in cart correctly
- ✅ Checkout dialog opens
- ✅ Payment methods available
- ✅ Payment completes successfully
- ✅ Receipt shows service details
- ✅ Service order status updates to "paid"

**Pass/Fail:** ___________

---

### Test 7: Quick Sell - Error Handling
**Steps:**
1. Disconnect from database (if possible) or simulate error
2. Try to add service in Quick Sell mode

**Expected Results:**
- ✅ Error snackbar appears: "⚠ Could not add [Service Name] to cart"
- ✅ Service not added to cart
- ✅ App doesn't crash
- ✅ User can try again

**Pass/Fail:** ___________

---

### Test 8: Category Filter with Quick Sell
**Steps:**
1. Ensure "Quick Sell" mode is selected
2. Click different category chips
3. Add services from different categories

**Expected Results:**
- ✅ Category filter works correctly
- ✅ Quick Sell works for all categories
- ✅ "Quick" badge visible on all filtered services
- ✅ Mode persists when changing categories

**Pass/Fail:** ___________

---

### Test 9: Queue Mode - Full Service Order
**Steps:**
1. Switch to "Queue" mode
2. Click a service card
3. Fill in customer details
4. Add custom field values (if any)
5. Create the order

**Expected Results:**
- ✅ Service order dialog opens
- ✅ All fields are editable
- ✅ Order creates successfully
- ✅ Navigates to queue board (optional)
- ✅ Order appears in queue with correct status

**Pass/Fail:** ___________

---

### Test 10: Responsive Design
**Steps:**
1. Test on desktop (wide screen)
2. Test on tablet (medium screen)
3. Test on mobile (narrow screen)

**Expected Results:**
- ✅ Mode toggle visible and functional on all screens
- ✅ Service cards layout adjusts appropriately
- ✅ "Quick" badges visible on all screen sizes
- ✅ Touch targets are adequate (min 44x44px)

**Pass/Fail:** ___________

---

### Test 11: Permission Check
**Steps:**
1. Test with user who has service POS access
2. Test with user who doesn't have service POS access (if possible)

**Expected Results:**
- ✅ Authorized users can use Quick Sell
- ✅ Unauthorized users see appropriate message
- ✅ No crashes or errors

**Pass/Fail:** ___________

---

### Test 12: Cart Integration
**Steps:**
1. Add a product to cart
2. Add a service using Quick Sell
3. View cart contents

**Expected Results:**
- ✅ Both product and service appear in cart
- ✅ Service shows correct icon/indicator
- ✅ Service quantity is 1 (not editable)
- ✅ Service can be removed from cart
- ✅ Totals calculate correctly

**Pass/Fail:** ___________

---

## Performance Tests

### Test 13: Quick Sell Speed
**Steps:**
1. Time how long it takes to add a service in Quick Sell mode
2. Compare with Queue mode time

**Expected Results:**
- ✅ Quick Sell completes in < 2 seconds
- ✅ Significantly faster than Queue mode
- ✅ No noticeable lag or delay

**Pass/Fail:** ___________

---

### Test 14: Multiple Rapid Clicks
**Steps:**
1. Rapidly click the same service card 5 times
2. Observe cart and behavior

**Expected Results:**
- ✅ Service added only once (or appropriate number)
- ✅ No duplicate entries
- ✅ No crashes or errors
- ✅ Snackbar appears appropriately

**Pass/Fail:** ___________

---

## Edge Cases

### Test 15: Service with $0 Price
**Steps:**
1. Create a service with base price = $0
2. Try to add it using Quick Sell

**Expected Results:**
- ✅ Service adds to cart
- ✅ Shows $0.00 price
- ✅ Can checkout successfully

**Pass/Fail:** ___________

---

### Test 16: Service with Long Name
**Steps:**
1. Create a service with a very long name (50+ characters)
2. Add it using Quick Sell
3. View in cart

**Expected Results:**
- ✅ Name truncates appropriately on card
- ✅ Full name visible in cart
- ✅ No layout issues
- ✅ Snackbar shows truncated name if needed

**Pass/Fail:** ___________

---

### Test 17: No Active Services
**Steps:**
1. Deactivate all services
2. Navigate to Service Desk

**Expected Results:**
- ✅ Shows empty state message
- ✅ Mode toggle still visible
- ✅ No errors or crashes

**Pass/Fail:** ___________

---

## Regression Tests

### Test 18: Existing Queue Functionality
**Steps:**
1. Use Queue mode to create a detailed service order
2. Verify all existing features work

**Expected Results:**
- ✅ All custom fields work
- ✅ Scheduling works
- ✅ Bay assignment works
- ✅ Queue board shows order
- ✅ No functionality broken

**Pass/Fail:** ___________

---

### Test 19: Existing Cart Functionality
**Steps:**
1. Add products to cart (traditional way)
2. Add services using Quick Sell
3. Test all cart operations

**Expected Results:**
- ✅ Products can be added/removed
- ✅ Services can be added/removed
- ✅ Quantities work correctly
- ✅ Hold/Resume works
- ✅ Checkout works

**Pass/Fail:** ___________

---

## Accessibility Tests

### Test 20: Keyboard Navigation
**Steps:**
1. Use Tab key to navigate
2. Use Enter/Space to activate buttons
3. Navigate through all interactive elements

**Expected Results:**
- ✅ Can tab to mode toggle
- ✅ Can tab to service cards
- ✅ Enter/Space activates elements
- ✅ Focus indicators visible

**Pass/Fail:** ___________

---

### Test 21: Screen Reader (Optional)
**Steps:**
1. Enable screen reader
2. Navigate through Service Desk
3. Add service using Quick Sell

**Expected Results:**
- ✅ Mode toggle announced correctly
- ✅ Service cards announced with name and price
- ✅ Snackbar notifications announced
- ✅ All actions accessible

**Pass/Fail:** ___________

---

## Summary

**Total Tests:** 21
**Tests Passed:** _____
**Tests Failed:** _____
**Pass Rate:** _____%

### Critical Issues Found:
1. ___________________________________
2. ___________________________________
3. ___________________________________

### Minor Issues Found:
1. ___________________________________
2. ___________________________________
3. ___________________________________

### Recommendations:
1. ___________________________________
2. ___________________________________
3. ___________________________________

---

**Tested By:** ___________________
**Date:** ___________________
**Environment:** ___________________
**Build Version:** ___________________

**Overall Status:** ⬜ Pass  ⬜ Fail  ⬜ Pass with Issues

---

## Notes
- Test in both development and production environments
- Test with real data when possible
- Document any unexpected behavior
- Take screenshots of issues
- Report critical bugs immediately
