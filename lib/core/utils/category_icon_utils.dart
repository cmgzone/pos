import 'package:flutter/material.dart';

/// 3-level fallback icon resolution for product categories.
///
/// Level 1 — exact name match (hardcoded well-known categories).
/// Level 2 — keyword inference from the category name.
/// Level 3 — neutral fallback icon.
///
/// Add new entries to [_exactIcons] or [_keywordRules] for full control
/// without ever touching UI code.
class CategoryIconUtils {
  CategoryIconUtils._();

  // ── Level 1: exact name → specific icon ──────────────────────────────────
  static const Map<String, IconData> _exactIcons = {
    // Food & Beverage
    'food': Icons.restaurant_outlined,
    'foods': Icons.restaurant_outlined,
    'beverages': Icons.local_drink_outlined,
    'beverage': Icons.local_drink_outlined,
    'drinks': Icons.local_drink_outlined,
    'drink': Icons.local_drink_outlined,
    'snacks': Icons.cookie_outlined,
    'snack': Icons.cookie_outlined,
    'bakery': Icons.bakery_dining_outlined,
    'dairy': Icons.egg_outlined,
    'meat': Icons.set_meal_outlined,
    'seafood': Icons.set_meal_outlined,
    'fruits': Icons.energy_savings_leaf_outlined,
    'vegetables': Icons.energy_savings_leaf_outlined,
    'fresh produce': Icons.energy_savings_leaf_outlined,
    'frozen food': Icons.ac_unit,
    'frozen foods': Icons.ac_unit,
    'condiments': Icons.blur_circular_outlined,
    'cereals': Icons.breakfast_dining_outlined,
    'bread': Icons.breakfast_dining_outlined,
    'coffee': Icons.coffee_outlined,
    'tea': Icons.emoji_food_beverage_outlined,
    'juice': Icons.local_drink_outlined,
    'water': Icons.water_drop_outlined,
    'alcohol': Icons.liquor_outlined,
    'wine': Icons.wine_bar_outlined,
    'beer': Icons.sports_bar_outlined,

    // Health & Pharmacy
    'pharmacy': Icons.local_pharmacy_outlined,
    'medicine': Icons.medication_outlined,
    'medicines': Icons.medication_outlined,
    'supplements': Icons.medical_services_outlined,
    'health': Icons.health_and_safety_outlined,
    'wellness': Icons.spa_outlined,
    'personal care': Icons.face_outlined,
    'hygiene': Icons.soap_outlined,

    // Electronics & Technology
    'electronics': Icons.devices_outlined,
    'electronic': Icons.devices_outlined,
    'accessories': Icons.cable_outlined,
    'phones': Icons.phone_android_outlined,
    'mobile': Icons.phone_android_outlined,
    'computers': Icons.computer_outlined,
    'gadgets': Icons.watch_outlined,
    'chargers': Icons.electrical_services_outlined,
    'batteries': Icons.battery_charging_full_outlined,
    'cables': Icons.cable_outlined,

    // Clothing & Fashion
    'clothing': Icons.checkroom_outlined,
    'clothes': Icons.checkroom_outlined,
    'apparel': Icons.checkroom_outlined,
    'fashion': Icons.checkroom_outlined,
    'shoes': Icons.directions_walk_outlined,
    'footwear': Icons.directions_walk_outlined,
    'bags': Icons.shopping_bag_outlined,
    'bag': Icons.shopping_bag_outlined,
    'jewelry': Icons.diamond_outlined,
    'jewellery': Icons.diamond_outlined,

    // Home & Household
    'household': Icons.home_outlined,
    'home': Icons.home_outlined,
    'cleaning': Icons.cleaning_services_outlined,
    'detergents': Icons.soap_outlined,
    'kitchen': Icons.kitchen_outlined,
    'furniture': Icons.chair_outlined,
    'bedding': Icons.bed_outlined,
    'tools': Icons.construction_outlined,
    'hardware': Icons.hardware_outlined,
    'stationery': Icons.edit_outlined,
    'office': Icons.business_center_outlined,
    'school': Icons.school_outlined,

    // Beauty & Cosmetics
    'beauty': Icons.face_retouching_natural_outlined,
    'cosmetics': Icons.brush_outlined,
    'skincare': Icons.spa_outlined,
    'haircare': Icons.content_cut_outlined,

    // Toys & Sports
    'toys': Icons.toys_outlined,
    'sports': Icons.sports_outlined,
    'fitness': Icons.fitness_center_outlined,
    'outdoor': Icons.park_outlined,

    // Automotive
    'automotive': Icons.directions_car_outlined,
    'auto': Icons.directions_car_outlined,
    'car': Icons.directions_car_outlined,

    // General / Catch-all named ones
    'general': Icons.inventory_2_outlined,
    'miscellaneous': Icons.category_outlined,
    'misc': Icons.category_outlined,
    'other': Icons.category_outlined,
    'uncategorized': Icons.category_outlined,
  };

  // ── Level 2: keyword → icon (checked in order, first match wins) ──────────
  static const List<(String keyword, IconData icon)> _keywordRules = [
    // Food & Drink
    ('drink', Icons.local_drink_outlined),
    ('beverage', Icons.local_drink_outlined),
    ('juice', Icons.local_drink_outlined),
    ('water', Icons.water_drop_outlined),
    ('coffee', Icons.coffee_outlined),
    ('tea', Icons.emoji_food_beverage_outlined),
    ('beer', Icons.sports_bar_outlined),
    ('wine', Icons.wine_bar_outlined),
    ('alcohol', Icons.liquor_outlined),
    ('snack', Icons.cookie_outlined),
    ('biscuit', Icons.cookie_outlined),
    ('candy', Icons.cookie_outlined),
    ('sweet', Icons.cookie_outlined),
    ('chocolate', Icons.cookie_outlined),
    ('bread', Icons.breakfast_dining_outlined),
    ('cereal', Icons.breakfast_dining_outlined),
    ('bakery', Icons.bakery_dining_outlined),
    ('cake', Icons.cake_outlined),
    ('fruit', Icons.energy_savings_leaf_outlined),
    ('vegetable', Icons.energy_savings_leaf_outlined),
    ('vegetab', Icons.energy_savings_leaf_outlined),
    ('produce', Icons.energy_savings_leaf_outlined),
    ('dairy', Icons.egg_outlined),
    ('milk', Icons.egg_outlined),
    ('meat', Icons.set_meal_outlined),
    ('fish', Icons.set_meal_outlined),
    ('seafood', Icons.set_meal_outlined),
    ('frozen', Icons.ac_unit),
    ('flour', Icons.breakfast_dining_outlined),
    ('grain', Icons.breakfast_dining_outlined),
    ('rice', Icons.breakfast_dining_outlined),
    ('food', Icons.restaurant_outlined),

    // Health & Pharmacy
    ('pharma', Icons.local_pharmacy_outlined),
    ('medic', Icons.medication_outlined),
    ('drug', Icons.medication_outlined),
    ('supplement', Icons.medical_services_outlined),
    ('vitamin', Icons.medical_services_outlined),
    ('health', Icons.health_and_safety_outlined),
    ('wellness', Icons.spa_outlined),
    ('hygiene', Icons.soap_outlined),
    ('soap', Icons.soap_outlined),
    ('sanitizer', Icons.soap_outlined),

    // Electronics
    ('electron', Icons.devices_outlined),
    ('phone', Icons.phone_android_outlined),
    ('mobile', Icons.phone_android_outlined),
    ('gadget', Icons.watch_outlined),
    ('computer', Icons.computer_outlined),
    ('laptop', Icons.laptop_outlined),
    ('charger', Icons.electrical_services_outlined),
    ('battery', Icons.battery_charging_full_outlined),
    ('cable', Icons.cable_outlined),
    ('headphone', Icons.headphones_outlined),
    ('earphone', Icons.headphones_outlined),
    ('speaker', Icons.speaker_outlined),
    ('camera', Icons.camera_alt_outlined),
    ('accessory', Icons.cable_outlined),
    ('accessories', Icons.cable_outlined),

    // Clothing
    ('cloth', Icons.checkroom_outlined),
    ('apparel', Icons.checkroom_outlined),
    ('fashion', Icons.checkroom_outlined),
    ('shirt', Icons.checkroom_outlined),
    ('trouser', Icons.checkroom_outlined),
    ('dress', Icons.checkroom_outlined),
    ('wear', Icons.checkroom_outlined),
    ('shoe', Icons.directions_walk_outlined),
    ('boot', Icons.directions_walk_outlined),
    ('sandal', Icons.directions_walk_outlined),
    ('bag', Icons.shopping_bag_outlined),
    ('wallet', Icons.account_balance_wallet_outlined),
    ('jewel', Icons.diamond_outlined),
    ('watch', Icons.watch_outlined),

    // Home & Household
    ('household', Icons.home_outlined),
    ('home', Icons.home_outlined),
    ('kitchen', Icons.kitchen_outlined),
    ('clean', Icons.cleaning_services_outlined),
    ('detergent', Icons.soap_outlined),
    ('furniture', Icons.chair_outlined),
    ('bedding', Icons.bed_outlined),
    ('tool', Icons.construction_outlined),
    ('hardware', Icons.hardware_outlined),
    ('garden', Icons.park_outlined),

    // Beauty
    ('beauty', Icons.face_retouching_natural_outlined),
    ('cosmetic', Icons.brush_outlined),
    ('skin', Icons.spa_outlined),
    ('hair', Icons.content_cut_outlined),
    ('lotion', Icons.spa_outlined),
    ('cream', Icons.spa_outlined),
    ('perfume', Icons.blur_on),
    ('fragrance', Icons.blur_on),

    // Office & Stationery
    ('statione', Icons.edit_outlined),
    ('office', Icons.business_center_outlined),
    ('school', Icons.school_outlined),
    ('book', Icons.menu_book_outlined),
    ('paper', Icons.description_outlined),

    // Sports & Toys
    ('sport', Icons.sports_outlined),
    ('fitness', Icons.fitness_center_outlined),
    ('gym', Icons.fitness_center_outlined),
    ('toy', Icons.toys_outlined),
    ('game', Icons.sports_esports_outlined),
    ('outdoor', Icons.park_outlined),

    // Automotive
    ('auto', Icons.directions_car_outlined),
    ('car', Icons.directions_car_outlined),
    ('motor', Icons.directions_car_outlined),
    ('tyre', Icons.tire_repair_outlined),
    ('tire', Icons.tire_repair_outlined),
  ];

  // ── Level 3: neutral fallback ─────────────────────────────────────────────
  static const IconData _fallbackIcon = Icons.inventory_2_outlined;

  /// Resolve the best icon for [categoryName] using the 3-level system.
  static IconData iconFor(String? categoryName) {
    if (categoryName == null || categoryName.trim().isEmpty) {
      return _fallbackIcon;
    }

    final lower = categoryName.trim().toLowerCase();

    // Level 1 — exact match
    if (_exactIcons.containsKey(lower)) {
      return _exactIcons[lower]!;
    }

    // Level 2 — keyword scan (first match wins)
    for (final (keyword, icon) in _keywordRules) {
      if (lower.contains(keyword)) {
        return icon;
      }
    }

    // Level 3 — fallback
    return _fallbackIcon;
  }
}
