import 'package:flutter/material.dart';
import '../data/delivery_repository.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});
  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  late Future<List<Map<String, dynamic>>> _zones;
  late Future<List<Map<String, dynamic>>> _deliveries;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _zones = DeliveryRepository.zones();
    _deliveries = DeliveryRepository.deliveries();
  }

  Future<void> _zone() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delivery zone'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: 'Zone name'),
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
    if (ok == true) {
      await DeliveryRepository.addZone(name: c.text);
      setState(_reload);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Delivery'),
      actions: [IconButton(onPressed: _zone, icon: const Icon(Icons.add))],
    ),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Delivery Zones',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _zones,
          builder: (context, s) => Column(
            children: (s.data ?? [])
                .map(
                  (z) => ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: Text(z['name'].toString()),
                    subtitle: Text('Fee ${z['fee']}'),
                  ),
                )
                .toList(),
          ),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Active Deliveries',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _deliveries,
          builder: (context, s) => Column(
            children: (s.data ?? [])
                .map(
                  (d) => ListTile(
                    title: Text(d['tracking_code'].toString()),
                    subtitle: Text(d['status'].toString()),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        await DeliveryRepository.updateStatus(
                          d['id'].toString(),
                          v,
                        );
                        setState(_reload);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'assigned',
                          child: Text('Assigned'),
                        ),
                        PopupMenuItem(
                          value: 'out_for_delivery',
                          child: Text('Out for delivery'),
                        ),
                        PopupMenuItem(
                          value: 'delivered',
                          child: Text('Delivered'),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );
}
