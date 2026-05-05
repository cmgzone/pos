import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'database_service.dart';

const _uuid = Uuid();

/// Seeds the database with demo product data on first launch.
///
/// Note: User accounts are no longer seeded locally. All accounts must be
/// created through the cloud registration endpoint (SaaS model).
class SeedService {
  static Future<void> seedIfEmpty() async {
    final products = await DatabaseService.queryAll('products');
    if (products.isNotEmpty) return; // Already seeded

    // Only seed product data if there are users (i.e. after registration).
    // If no users exist yet, skip seeding — the sign-up flow will handle it.
    final users = await DatabaseService.queryAll('users');
    if (users.isEmpty) return;

    debugPrint('[Seed] Seeding demo product data...');
    final now = DateTime.now().toIso8601String();

    // ── Payment Methods ──
    await _seedPaymentMethods(now);

    // ── Categories ──
    final catElectronics = _uuid.v4();
    final catAccessories = _uuid.v4();
    final catBeverages = _uuid.v4();
    final catSnacks = _uuid.v4();

    final categories = [
      {
        'id': catElectronics,
        'name': 'Electronics',
        'color': '#6B4EE6',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
      {
        'id': catAccessories,
        'name': 'Accessories',
        'color': '#00E5FF',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
      {
        'id': catBeverages,
        'name': 'Beverages',
        'color': '#32D74B',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
      {
        'id': catSnacks,
        'name': 'Snacks',
        'color': '#FF9F0A',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
    ];

    for (final cat in categories) {
      await DatabaseService.insert('categories', cat);
    }

    // ── Products ──
    final productData = [
      {
        'name': 'Wireless Mouse',
        'price': 29.99,
        'cost': 15.0,
        'stock': 45,
        'sku': 'ELC-001',
        'barcode': '1000000001',
        'category_id': catElectronics,
      },
      {
        'name': 'USB-C Hub',
        'price': 49.99,
        'cost': 25.0,
        'stock': 30,
        'sku': 'ELC-002',
        'barcode': '1000000002',
        'category_id': catElectronics,
      },
      {
        'name': 'Bluetooth Speaker',
        'price': 79.99,
        'cost': 40.0,
        'stock': 20,
        'sku': 'ELC-003',
        'barcode': '1000000003',
        'category_id': catElectronics,
      },
      {
        'name': 'Webcam HD',
        'price': 59.99,
        'cost': 30.0,
        'stock': 15,
        'sku': 'ELC-004',
        'barcode': '1000000004',
        'category_id': catElectronics,
      },
      {
        'name': 'Mechanical Keyboard',
        'price': 89.99,
        'cost': 45.0,
        'stock': 25,
        'sku': 'ELC-005',
        'barcode': '1000000005',
        'category_id': catElectronics,
      },
      {
        'name': 'Phone Case',
        'price': 14.99,
        'cost': 5.0,
        'stock': 100,
        'sku': 'ACC-001',
        'barcode': '2000000001',
        'category_id': catAccessories,
      },
      {
        'name': 'Screen Protector',
        'price': 9.99,
        'cost': 2.0,
        'stock': 200,
        'sku': 'ACC-002',
        'barcode': '2000000002',
        'category_id': catAccessories,
      },
      {
        'name': 'Laptop Sleeve',
        'price': 24.99,
        'cost': 10.0,
        'stock': 50,
        'sku': 'ACC-003',
        'barcode': '2000000003',
        'category_id': catAccessories,
      },
      {
        'name': 'Charging Cable',
        'price': 12.99,
        'cost': 4.0,
        'stock': 150,
        'sku': 'ACC-004',
        'barcode': '2000000004',
        'category_id': catAccessories,
      },
      {
        'name': 'Espresso Coffee',
        'price': 4.99,
        'cost': 1.5,
        'stock': 80,
        'sku': 'BEV-001',
        'barcode': '3000000001',
        'category_id': catBeverages,
      },
      {
        'name': 'Green Tea',
        'price': 3.49,
        'cost': 1.0,
        'stock': 120,
        'sku': 'BEV-002',
        'barcode': '3000000002',
        'category_id': catBeverages,
      },
      {
        'name': 'Orange Juice',
        'price': 2.99,
        'cost': 1.2,
        'stock': 60,
        'sku': 'BEV-003',
        'barcode': '3000000003',
        'category_id': catBeverages,
      },
      {
        'name': 'Energy Drink',
        'price': 3.99,
        'cost': 1.8,
        'stock': 90,
        'sku': 'BEV-004',
        'barcode': '3000000004',
        'category_id': catBeverages,
      },
      {
        'name': 'Protein Bar',
        'price': 2.49,
        'cost': 1.0,
        'stock': 75,
        'sku': 'SNK-001',
        'barcode': '4000000001',
        'category_id': catSnacks,
      },
      {
        'name': 'Trail Mix',
        'price': 5.99,
        'cost': 2.5,
        'stock': 40,
        'sku': 'SNK-002',
        'barcode': '4000000002',
        'category_id': catSnacks,
      },
      {
        'name': 'Chips Variety',
        'price': 3.49,
        'cost': 1.2,
        'stock': 110,
        'sku': 'SNK-003',
        'barcode': '4000000003',
        'category_id': catSnacks,
      },
    ];

    for (final p in productData) {
      await DatabaseService.insert('products', {
        'id': _uuid.v4(),
        ...p,
        'low_stock': 10,
        'image_url': null,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      });
    }

    debugPrint(
      '[Seed] Demo data seeded: ${categories.length} categories, ${productData.length} products',
    );
  }

  static Future<void> _seedPaymentMethods(String now) async {
    // Check if payment methods already exist
    final existing = await DatabaseService.queryAll('payment_methods');
    if (existing.isNotEmpty) return;

    debugPrint('[Seed] Seeding default payment methods...');

    final paymentMethods = [
      {
        'id': _uuid.v4(),
        'name': 'Cash',
        'is_cash_drawer': 1,
        'is_credit': 0,
        'is_active': 1,
        'sort_order': 0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
      {
        'id': _uuid.v4(),
        'name': 'Kopesha',
        'is_cash_drawer': 0,
        'is_credit': 1,
        'is_active': 1,
        'sort_order': 1,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
      {
        'id': _uuid.v4(),
        'name': 'M-Pesa',
        'is_cash_drawer': 0,
        'is_credit': 0,
        'is_active': 1,
        'sort_order': 2,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
      {
        'id': _uuid.v4(),
        'name': 'Card',
        'is_cash_drawer': 0,
        'is_credit': 0,
        'is_active': 1,
        'sort_order': 3,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
      {
        'id': _uuid.v4(),
        'name': 'Bank Transfer',
        'is_cash_drawer': 0,
        'is_credit': 0,
        'is_active': 1,
        'sort_order': 4,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      },
    ];

    for (final method in paymentMethods) {
      await DatabaseService.insert('payment_methods', method);
    }

    debugPrint('[Seed] Seeded ${paymentMethods.length} payment methods');
  }
}
