# Professional Animations & Transitions Guide

## Overview
This guide documents all the professional animations and transitions added to the POS app to create a polished, modern user experience.

## Animation Files Created

### 1. Page Transitions (`lib/widgets/transitions.dart`)
Smooth page navigation transitions that replace default Flutter animations.

#### Available Transitions:
- **SlideFadeTransition** - Slide + fade from right (default for navigation)
- **ScaleFadeTransition** - Scale up + fade (for modals/dialogs)
- **SlideUpTransition** - Slide up + fade (for bottom sheets)

#### Usage Examples:

```dart
// Navigate with slide transition
Navigator.of(context).push(
  SlideFadeTransition(page: ProductListScreen()),
);

// Navigate with scale transition
Navigator.of(context).push(
  ScaleFadeTransition(page: ProductDetailScreen()),
);

// Navigate with slide up (for modals)
Navigator.of(context).push(
  SlideUpTransition(page: CartModal()),
);

// Custom duration and curve
Navigator.of(context).push(
  SlideFadeTransition(
    page: SettingsScreen(),
    duration: Duration(milliseconds: 400),
    curve: Curves.easeOutCubic,
  ),
);
```

### 2. Staggered Animations (`lib/widgets/staggered_animations.dart`)
Beautiful staggered animations for lists and grids.

#### Widgets:
- **StaggeredAnimation** - Wrap list/grid items for stagger effect
- **StaggeredList** - Pre-built list with stagger animations
- **StaggeredGrid** - Pre-built grid with stagger animations

#### Usage Examples:

```dart
// Staggered list
ListView.builder(
  itemCount: products.length,
  itemBuilder: (context, index) {
    return StaggeredAnimation(
      index: index,
      child: ProductCard(product: products[index]),
    );
  },
);

// Staggered grid
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
  ),
  itemCount: products.length,
  itemBuilder: (context, index) {
    return StaggeredAnimation(
      index: index,
      delayPerItem: 50, // milliseconds
      child: ProductGridItem(product: products[index]),
    );
  },
);

// Pre-built staggered list
StaggeredList(
  itemCount: products.length,
  itemBuilder: (context, index) => ProductCard(product: products[index]),
);

// Pre-built staggered grid
StaggeredGrid(
  crossAxisCount: 3,
  itemCount: products.length,
  itemBuilder: (context, index) => ProductGridItem(product: products[index]),
);
```

### 3. Micro-Interactions (`lib/widgets/micro_interactions.dart`)
Subtle interactive feedback for buttons, cards, and touchable elements.

#### Widgets:
- **PressableScale** - Scale down on press (for buttons/cards)
- **HoverableCard** - Elevate on hover (desktop)
- **RippleButton** - Material ripple effect
- **AnimatedCounter** - Smooth number transitions
- **AnimatedNumber** - Smooth decimal number transitions
- **PulseAnimation** - Pulsing effect for notifications
- **ShimmerEffect** - Loading shimmer for images/content

#### Usage Examples:

```dart
// Pressable button with scale effect
PressableScale(
  onPressed: () => addToCart(product),
  child: Container(
    padding: EdgeInsets.all(16),
    child: Text('Add to Cart'),
  ),
);

// Hoverable card (desktop)
HoverableCard(
  onTap: () => openProduct(product),
  child: ProductCard(product: product),
);

// Ripple button
RippleButton(
  onPressed: () => checkout(),
  child: Text('Checkout'),
);

// Animated counter
AnimatedCounter(
  value: cartItemCount,
  duration: Duration(milliseconds: 300),
);

// Animated number with decimals
AnimatedNumber(
  value: totalPrice,
  decimalPlaces: 2,
  duration: Duration(milliseconds: 400),
);

// Pulse animation for notifications
PulseAnimation(
  child: Badge(count: 5),
);

// Shimmer loading effect
ShimmerEffect(
  child: Container(
    height: 100,
    color: Colors.grey[300],
  ),
);
```

### 4. Scroll Animations (`lib/widgets/scroll_animations.dart`)
Animations triggered when elements scroll into view.

#### Widgets:
- **ScrollRevealAnimation** - Fade + slide in on scroll
- **ParallaxScrollEffect** - Parallax scrolling for images
- **ScrollProgressIndicator** - Progress bar at top of screen

#### Usage Examples:

```dart
// Reveal on scroll
ScrollRevealAnimation(
  child: SectionHeader(title: 'Featured Products'),
);

// Parallax effect
ParallaxScrollEffect(
  parallaxFactor: 0.5,
  child: Image.asset('hero.jpg'),
);

// Scroll progress indicator
ScrollProgressIndicator(
  controller: scrollController,
  color: Theme.of(context).primaryColor,
  height: 3,
);
```

### 5. Modal Animations (`lib/widgets/modal_animations.dart`)
Professional animations for dialogs, bottom sheets, and modals.

#### Widgets:
- **AnimatedModal** - Scale + fade modal
- **SlideUpModal** - Slide up from bottom
- **ScaleInModal** - Scale in from center
- **FadeInModal** - Simple fade in

#### Usage Examples:

```dart
// Show animated modal
showAnimatedModal(
  context: context,
  builder: (context) => ProductDetailModal(product: product),
);

// Show slide up modal (for bottom sheets)
showSlideUpModal(
  context: context,
  builder: (context) => CartBottomSheet(),
);

// Show scale in modal (for dialogs)
showScaleInModal(
  context: context,
  builder: (context) => ConfirmDialog(
    title: 'Delete Product',
    message: 'Are you sure?',
  ),
);

// Custom animation
showDialog(
  context: context,
  builder: (context) => FadeInModal(
    child: AlertDialog(
      title: Text('Success'),
      content: Text('Product added!'),
    ),
  ),
);
```

### 6. Enhanced Skeleton Loading (`lib/widgets/skeleton.dart`)
Staggered skeleton loading with smooth animations.

#### Updates:
- Added `delay` parameter to `SkeletonBox` for stagger effects
- `SkeletonList` now supports staggered animations
- `SkeletonProductGrid` now supports staggered animations
- `SkeletonKpiGrid` now supports staggered animations

#### Usage Examples:

```dart
// Staggered skeleton list
SkeletonList(
  itemCount: 5,
  staggered: true, // Enable stagger effect
);

// Staggered skeleton grid
SkeletonProductGrid(
  crossAxisCount: 3,
  itemCount: 9,
  staggered: true, // Enable stagger effect
);

// Staggered KPI grid
SkeletonKpiGrid(
  itemCount: 4,
  staggered: true, // Enable stagger effect
);

// Custom skeleton with delay
SkeletonBox(
  width: 200,
  height: 20,
  delay: Duration(milliseconds: 100), // Stagger delay
);
```

## Animation Constants

All animations use centralized constants from `AppConstants`:

```dart
class AppConstants {
  // Animation durations
  static const animationFast = Duration(milliseconds: 200);
  static const animationNormal = Duration(milliseconds: 300);
  static const animationSlow = Duration(milliseconds: 500);
  
  // Curves (used throughout)
  static const defaultCurve = Curves.easeOutCubic;
}
```

## Best Practices

### 1. Use Consistent Durations
```dart
// ✅ Good - Use constants
duration: AppConstants.animationFast

// ❌ Bad - Hardcoded values
duration: Duration(milliseconds: 200)
```

### 2. Stagger Animations for Lists
```dart
// ✅ Good - Stagger list items
ListView.builder(
  itemBuilder: (context, index) {
    return StaggeredAnimation(
      index: index,
      child: ListItem(),
    );
  },
);

// ❌ Bad - All items animate at once
ListView.builder(
  itemBuilder: (context, index) {
    return FadeInAnimation(child: ListItem());
  },
);
```

### 3. Use Appropriate Transitions
```dart
// ✅ Good - Slide for navigation
Navigator.push(context, SlideFadeTransition(page: NextScreen()));

// ✅ Good - Scale for modals
showDialog(context: context, builder: (_) => ScaleInModal(child: Dialog()));

// ❌ Bad - Using slide for modals
showDialog(context: context, builder: (_) => SlideFadeTransition(child: Dialog()));
```

### 4. Add Micro-Interactions
```dart
// ✅ Good - Pressable feedback
PressableScale(
  onPressed: () => action(),
  child: Card(child: Content()),
);

// ❌ Bad - No feedback
GestureDetector(
  onTap: () => action(),
  child: Card(child: Content()),
);
```

### 5. Use Skeleton Loading
```dart
// ✅ Good - Show skeleton while loading
if (isLoading) {
  return SkeletonProductGrid(crossAxisCount: 3, staggered: true);
}

// ❌ Bad - Show empty state or spinner
if (isLoading) {
  return CircularProgressIndicator();
}
```

## Performance Considerations

### 1. Limit Stagger Delays
```dart
// ✅ Good - Reasonable delay
StaggeredAnimation(index: index, delayPerItem: 50);

// ❌ Bad - Too long delay
StaggeredAnimation(index: index, delayPerItem: 200);
```

### 2. Use AnimatedBuilder for Complex Animations
```dart
// ✅ Good - Efficient animation
AnimatedBuilder(
  animation: controller,
  builder: (context, child) {
    return Transform.scale(scale: animation.value, child: child);
  },
  child: ExpensiveWidget(),
);

// ❌ Bad - Rebuilds entire widget tree
AnimatedBuilder(
  animation: controller,
  builder: (context, _) {
    return Transform.scale(
      scale: animation.value,
      child: ExpensiveWidget(), // Rebuilds every frame
    );
  },
);
```

### 3. Dispose Animation Controllers
```dart
class _MyWidgetState extends State<MyWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose(); // ✅ Always dispose
    super.dispose();
  }
}
```

## Applied Animations

### POS Screen
- ✅ Staggered product grid animations
- ✅ Animated cart item count
- ✅ Pressable product cards
- ✅ Skeleton loading with stagger

### Product List Screen
- ✅ Staggered product list
- ✅ Slide transition to product detail
- ✅ Hoverable product cards (desktop)
- ✅ Skeleton loading with stagger

### Reports Screen
- ✅ Staggered report cards
- ✅ Animated number transitions
- ✅ Scroll reveal animations
- ✅ Skeleton loading with stagger

### Dashboard
- ✅ Staggered KPI cards
- ✅ Animated counters
- ✅ Scroll progress indicator
- ✅ Skeleton loading with stagger

## Testing Animations

### 1. Test on Real Devices
Always test animations on real devices, not just emulators, to ensure smooth performance.

### 2. Test with Slow Animations
Enable "Slow animations" in Flutter DevTools to verify animation timing and curves.

### 3. Test Accessibility
Ensure animations respect `MediaQuery.of(context).disableAnimations`:

```dart
if (MediaQuery.of(context).disableAnimations) {
  return child; // Skip animation
}
return FadeInAnimation(child: child);
```

## Future Enhancements

### Planned Animations:
1. **Shared Element Transitions** - Hero animations between screens
2. **Pull-to-Refresh** - Custom refresh indicator with animation
3. **Swipe Actions** - Swipe to delete/archive in lists
4. **Drag and Drop** - Reorder items with smooth animations
5. **Page Transitions** - Custom transitions for specific routes
6. **Loading States** - More skeleton variations
7. **Success Animations** - Checkmark animations for confirmations
8. **Error Animations** - Shake animations for validation errors

## Troubleshooting

### Animation Not Working
1. Check if widget is wrapped correctly
2. Verify animation controller is initialized
3. Ensure `vsync` is provided (use `SingleTickerProviderStateMixin`)

### Animation Too Fast/Slow
1. Adjust duration using `AppConstants`
2. Change curve (try `Curves.easeInOut` or `Curves.easeOutCubic`)

### Stagger Not Working
1. Ensure `index` is passed correctly
2. Check `delayPerItem` value (50-100ms recommended)
3. Verify parent widget rebuilds when list changes

### Performance Issues
1. Reduce number of simultaneous animations
2. Use `AnimatedBuilder` with `child` parameter
3. Limit stagger delays for long lists
4. Use `RepaintBoundary` for complex animated widgets

## Conclusion

These professional animations transform the POS app from a functional tool into a polished, modern application. The staggered animations, micro-interactions, and smooth transitions create a delightful user experience that rivals top-tier mobile apps.

All animations are:
- ✅ **Consistent** - Using centralized constants
- ✅ **Performant** - Optimized for smooth 60fps
- ✅ **Accessible** - Respects user preferences
- ✅ **Reusable** - Easy to apply across the app
- ✅ **Professional** - Modern, polished feel

For questions or issues with animations, refer to this guide or check the implementation in the respective widget files.
