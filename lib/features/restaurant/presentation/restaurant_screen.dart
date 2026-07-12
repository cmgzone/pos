import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../app/app_shell.dart';
import '../../products/data/product_repository.dart';
import '../../sales/presentation/pos_screen.dart';
import '../data/restaurant_repository.dart';

class RestaurantScreen extends StatefulWidget {
  const RestaurantScreen({super.key});
  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends State<RestaurantScreen> {
  late Future<List<Map<String, dynamic>>> _tables;
  @override
  void initState() {
    super.initState();
    _tables = RestaurantRepository.getTables();
  }

  void _refresh() => setState(() => _tables = RestaurantRepository.getTables());

  Future<void> _addTable() async {
    final name = TextEditingController();
    final area = TextEditingController();
    final seats = TextEditingController(text: '2');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add table'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Table name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: area,
              decoration: const InputDecoration(labelText: 'Area (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: seats,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Seats'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await RestaurantRepository.addTable(
        name: name.text,
        area: area.text,
        seats: int.tryParse(seats.text) ?? 2,
      );
      _refresh();
    } catch (error) {
      _message(error, error: true);
    }
  }

  Future<void> _openTable(Map<String, dynamic> table) async {
    var orderId = table['order_id'] as String? ?? '';
    try {
      if (orderId.isEmpty) {
        orderId = await RestaurantRepository.openOrder(
          tableId: table['id'] as String,
        );
        _refresh();
      }
      final products = await ProductRepository.getAll(
        typeFilter: ProductTypeFilter.simpleOnly,
        restaurantMenuOnly: true,
      );
      if (!mounted) return;
      if (products.isEmpty) {
        _message(
          'No restaurant menu items yet. Enable "Show in restaurant menu" '
          'on products you want to sell here.',
          error: true,
        );
        return;
      }
      final product = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (context) => ListView(
          children: products
              .map(
                (item) => ListTile(
                  title: Text(item['name'] as String? ?? 'Product'),
                  subtitle: Text(item['price'].toString()),
                  onTap: () => Navigator.pop(context, item),
                ),
              )
              .toList(),
        ),
      );
      if (product != null) {
        await RestaurantRepository.addProduct(
          orderId: orderId,
          product: product,
        );
        _refresh();
      }
    } catch (error) {
      _message(error, error: true);
    }
  }

  Future<void> _checkoutTable(Map<String, dynamic> table) async {
    final parts = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Split bill'),
        children: [1, 2, 3, 4]
            .map(
              (count) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, count),
                child: Text(count == 1 ? 'One bill' : '$count equal bills'),
              ),
            )
            .toList(),
      ),
    );
    if (parts == null) return;
    try {
      final holds = await RestaurantRepository.sendToPos(
        table: table,
        splitCount: parts,
      );
      _refresh();
      _message(
        '${holds.length} bill${holds.length == 1 ? '' : 's'} saved to POS holds.',
      );
    } catch (error) {
      _message(error, error: true);
    }
  }

  Future<void> _advanceKitchen(
    Map<String, dynamic> table,
    Map<String, dynamic> item,
  ) async {
    const next = {
      'pending': 'preparing',
      'preparing': 'ready',
      'ready': 'served',
      'served': 'served',
    };
    await RestaurantRepository.updateKitchenStatus(
      orderId: table['order_id'] as String,
      itemId: item['id'] as String,
      status: next[item['status']] ?? 'preparing',
    );
    _refresh();
  }

  void _message(Object value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value.toString().replaceFirst('Exception: ', '')),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Restaurant'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(onPressed: _addTable, icon: const Icon(Icons.add_rounded)),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.table_restaurant_outlined), text: 'Floor'),
            Tab(icon: Icon(Icons.soup_kitchen_outlined), text: 'Kitchen'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Bills'),
          ],
        ),
      ),
      body: TabBarView(children: [_floor(), _kitchen(), _bills()]),
    ),
  );

  Widget _bills() => FutureBuilder<List<Map<String, dynamic>>>(
    future: RestaurantRepository.getBills(),
    builder: (context, snapshot) {
      final bills = snapshot.data ?? [];
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (bills.isEmpty) {
        return const Center(child: Text('No bills sent to POS yet.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: bills.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final bill = bills[index];
          return ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(bill['name'] as String? ?? 'Bill'),
            subtitle: Text(
              '${bill['cashier_name'] ?? ''} · ${bill['total']}',
            ),
            trailing: FilledButton.tonal(
              onPressed: () => _takeBillToPos(bill['id'] as String),
              child: const Text('Take to POS'),
            ),
          );
        },
      );
    },
  );

  Future<void> _takeBillToPos(String holdId) async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(builder: (_) => PosScreen(initialHoldId: holdId)),
    );
    _refresh();
  }

  Widget _floor() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _tables,
    builder: (context, snapshot) {
      final tables = snapshot.data ?? [];
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (tables.isEmpty) {
        return Center(
          child: FilledButton.icon(
            onPressed: _addTable,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add first table'),
          ),
        );
      }
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) {
          final table = tables[index];
          final occupied = table['status'] == 'occupied';
          return Card(
            color: occupied ? AppColors.warning.withValues(alpha: .1) : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openTable(table),
              onLongPress: occupied ? () => _checkoutTable(table) : null,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.table_restaurant_rounded,
                      color: occupied ? AppColors.warning : AppColors.success,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      table['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      occupied
                          ? '${table['order_no']} · ${table['total']}'
                          : 'Available',
                    ),
                    if (occupied)
                      const Text(
                        'Hold to checkout',
                        style: TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _kitchen() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _tables,
    builder: (context, snapshot) {
      final tables = snapshot.data ?? [];
      final tickets = <Widget>[];
      for (final table in tables) {
        for (final item in table['items'] as List<dynamic>? ?? const []) {
          if (item['status'] != 'served') {
            tickets.add(
              Card(
                child: ListTile(
                  onTap: () => _advanceKitchen(
                    table,
                    Map<String, dynamic>.from(item as Map),
                  ),
                  leading: const Icon(Icons.soup_kitchen_outlined),
                  title: Text(item['product_name']?.toString() ?? 'Item'),
                  subtitle: Text('${table['name']} · ${item['quantity']}'),
                  trailing: Text(item['status']?.toString() ?? 'pending'),
                ),
              ),
            );
          }
        }
      }
      return tickets.isEmpty
          ? const Center(child: Text('No active kitchen tickets.'))
          : ListView(padding: const EdgeInsets.all(12), children: tickets);
    },
  );
}
