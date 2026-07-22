import 'package:flutter/material.dart';
import '../data/purchase_repository.dart';

class PurchaseApprovalScreen extends StatefulWidget {
  const PurchaseApprovalScreen({super.key});
  @override
  State<PurchaseApprovalScreen> createState() => _PurchaseApprovalScreenState();
}

class _PurchaseApprovalScreenState extends State<PurchaseApprovalScreen> {
  late Future<List<Map<String, dynamic>>> _orders;
  @override
  void initState() {
    super.initState();
    _orders = PurchaseRepository.getPendingApprovals();
  }

  void _reload() =>
      setState(() => _orders = PurchaseRepository.getPendingApprovals());
  Future<void> _decide(String id, bool approved) async {
    try {
      await PurchaseRepository.decidePurchaseOrder(id, approved: approved);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update order: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchase Approvals')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return const Center(
            child: Text('No purchase orders awaiting approval.'),
          );
        }
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Card(
              child: ListTile(
                title: Text(
                  row['order_number']?.toString() ?? 'Purchase order',
                ),
                subtitle: Text(
                  '${row['supplier_name'] ?? 'Supplier'} · ${row['total_amount']}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      onPressed: () => _decide(row['id'] as String, false),
                      icon: const Icon(Icons.close, color: Colors.red),
                    ),
                    IconButton(
                      onPressed: () => _decide(row['id'] as String, true),
                      icon: const Icon(Icons.check, color: Colors.green),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
