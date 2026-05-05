# Service Quick Sell - UI Guide

## Visual Overview

### Header Section (New Toggle)
```
┌─────────────────────────────────────────────────────────────────┐
│ Service Desk                                                     │
│                                                                  │
│  [⚡ Quick Sell] [📋 Queue]  [Queue Board]  [+ New Walk-in]    │
│   ▔▔▔▔▔▔▔▔▔▔▔▔                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Service Cards - Quick Sell Mode
```
┌──────────────────────────────────┐
│  [🔧]                    [⏱ 30min]│
│                                   │
│                                   │
│  Car Wash                         │
│  Automotive          [Quick ⚡]   │
│                                   │
│  $25.00                      [+]  │
└──────────────────────────────────┘
```

### Service Cards - Queue Mode
```
┌──────────────────────────────────┐
│  [🔧]                    [⏱ 30min]│
│                                   │
│                                   │
│  Car Wash                         │
│  Automotive                       │
│                                   │
│  $25.00                      [+]  │
└──────────────────────────────────┘
```

## Mode Comparison

### Quick Sell Mode (⚡)
**Visual Indicators:**
- Segmented button shows "Quick Sell" selected
- Green "Quick ⚡" badge on each service card
- Lightning icon in the toggle button

**Behavior:**
- Click card → Service added to cart immediately
- Shows snackbar: "✓ Car Wash added to cart"
- No dialog, no forms, instant action

**Best For:**
- Walk-in customers
- Simple transactions
- High-volume quick sales
- Standard pricing

---

### Queue Mode (📋)
**Visual Indicators:**
- Segmented button shows "Queue" selected
- No badge on service cards
- Note icon in the toggle button

**Behavior:**
- Click card → Opens service order dialog
- Fill customer details, custom fields
- Set scheduling, bay assignment
- Creates detailed order in queue

**Best For:**
- Appointments
- Custom pricing
- Special requirements
- Detailed tracking

## User Interactions

### Quick Sell Flow
```
1. User clicks service card
   ↓
2. System creates service order (status: ready)
   ↓
3. System adds to cart
   ↓
4. Shows snackbar notification
   ↓
5. User continues shopping or checks out
```

### Queue Flow
```
1. User clicks service card
   ↓
2. Dialog opens with form
   ↓
3. User fills details
   ↓
4. Creates order (status: booked/checked_in)
   ↓
5. Navigates to queue board
```

## Snackbar Notifications

### Success
```
┌────────────────────────────────────┐
│ ✓  Car Wash added to cart          │
└────────────────────────────────────┘
```

### Error
```
┌────────────────────────────────────┐
│ ⚠  Could not add Car Wash to cart  │
└────────────────────────────────────┘
```

## Color Scheme

### Quick Sell Mode
- **Toggle Button**: Primary blue (selected)
- **Badge Background**: Success green (15% opacity)
- **Badge Text**: Success green
- **Badge Icon**: Lightning bolt (⚡)
- **Snackbar Success**: Success green

### Queue Mode
- **Toggle Button**: Primary blue (selected)
- **No special colors**: Standard card styling

## Responsive Behavior

### Desktop (Wide Screen)
- Full header with all buttons visible
- Grid layout: 3-4 cards per row
- Toggle button shows full text labels

### Tablet (Medium Screen)
- Header wraps if needed
- Grid layout: 2-3 cards per row
- Toggle button shows full text labels

### Mobile (Narrow Screen)
- Header stacks vertically
- Grid layout: 1-2 cards per row
- Toggle button may show icons only

## Accessibility

- **Keyboard Navigation**: Tab through toggle and cards
- **Screen Readers**: Announces mode changes
- **Touch Targets**: Minimum 44x44 pixels
- **Color Contrast**: WCAG AA compliant
- **Focus Indicators**: Visible focus states

## Animation & Feedback

### Mode Toggle
- Smooth transition between modes
- Instant card badge appearance/disappearance
- No page reload required

### Card Interaction
- Hover effect: Slight elevation
- Tap feedback: Ripple effect
- Quick Sell: Immediate snackbar
- Queue: Dialog slide-in animation

## Tips for Users

💡 **Quick Tip**: Use Quick Sell for most walk-in customers to save time!

💡 **Pro Tip**: Switch to Queue mode when you need to schedule appointments or add custom details.

💡 **Efficiency Tip**: Keep Quick Sell as default for fastest checkout experience.

---

**UI Status**: ✅ Implemented
**Design System**: Follows existing app patterns
**Accessibility**: WCAG 2.1 AA compliant
