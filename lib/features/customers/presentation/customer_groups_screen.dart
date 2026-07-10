import 'package:flutter/material.dart';
import '../data/customer_group_repository.dart';
import '../data/customer_repository.dart';

class CustomerGroupsScreen extends StatefulWidget {
  const CustomerGroupsScreen({super.key});
  @override
  State<CustomerGroupsScreen> createState() => _CustomerGroupsScreenState();
}

class _CustomerGroupsScreenState extends State<CustomerGroupsScreen> {
  late Future<List<Map<String, dynamic>>> _groups;
  @override
  void initState() {
    super.initState();
    _groups = CustomerGroupRepository.getAll();
  }

  void _reload() => setState(() => _groups = CustomerGroupRepository.getAll());
  Future<void> _add() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New customer group'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CustomerGroupRepository.create(name: c.text);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _addMember(Map<String, dynamic> group) async {
    final customers = await CustomerRepository.search('');
    if (!mounted) return;
    final customer = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) => ListView(
        children: customers
            .map(
              (row) => ListTile(
                title: Text(row['name']?.toString() ?? 'Customer'),
                subtitle: Text(row['phone']?.toString() ?? ''),
                onTap: () => Navigator.pop(context, row),
              ),
            )
            .toList(),
      ),
    );
    if (customer == null) return;
    await CustomerGroupRepository.addMember(
      groupId: group['id'] as String,
      customerId: customer['id'] as String,
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Customer Groups'),
      actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add))],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _groups,
      builder: (context, s) {
        final rows = s.data ?? [];
        if (rows.isEmpty) {
          return Center(
            child: FilledButton(
              onPressed: _add,
              child: const Text('Create first group'),
            ),
          );
        }
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            return ListTile(
              onTap: () => _addMember(row),
              leading: const Icon(Icons.groups_outlined),
              title: Text(row['name'] as String),
              subtitle: Text('${row['member_count']} members'),
              trailing: const Icon(Icons.person_add_alt_1_outlined),
            );
          },
        );
      },
    ),
  );
}
