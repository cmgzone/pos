import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../data/serial_number_repository.dart';

class SerialTrackingScreen extends StatefulWidget {
  const SerialTrackingScreen({super.key});

  @override
  State<SerialTrackingScreen> createState() => _SerialTrackingScreenState();
}

class _SerialTrackingScreenState extends State<SerialTrackingScreen> {
  final _searchController = TextEditingController();
  String _status = '';
  bool _loading = true;
  List<Map<String, dynamic>> _serials = [];
  List<Map<String, dynamic>> _warrantyWatch = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await SerialNumberRepository.getAll(
      search: _searchController.text,
      status: _status.isEmpty ? null : _status,
    );
    final warranty = await SerialNumberRepository.warrantyWatch();
    if (!mounted) {
      return;
    }
    setState(() {
      _serials = results;
      _warrantyWatch = warranty;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serial Tracking'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 680;
                    final search = TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search serial, IMEI, product...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _load(),
                    );
                    final status = DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All')),
                        DropdownMenuItem(
                          value: 'available',
                          child: Text('Available'),
                        ),
                        DropdownMenuItem(value: 'sold', child: Text('Sold')),
                        DropdownMenuItem(
                          value: 'warranty',
                          child: Text('Warranty'),
                        ),
                        DropdownMenuItem(
                          value: 'returned',
                          child: Text('Returned'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _status = value ?? '');
                        _load();
                      },
                    );
                    if (isWide) {
                      return Row(
                        children: [
                          Expanded(child: search),
                          const SizedBox(width: 12),
                          SizedBox(width: 220, child: status),
                        ],
                      );
                    }
                    return Column(
                      children: [search, const SizedBox(height: 12), status],
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (_warrantyWatch.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      '${_warrantyWatch.length} serial(s) have warranties expiring soon.',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (_warrantyWatch.isNotEmpty) const SizedBox(height: 16),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _serials.isEmpty
                      ? Center(
                          child: Text(
                            'No serial numbers found.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _serials.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final serial = _serials[index];
                            return _SerialCard(serial: serial);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SerialCard extends StatelessWidget {
  final Map<String, dynamic> serial;

  const _SerialCard({required this.serial});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = serial['status'] as String? ?? 'available';
    final statusColor = switch (status) {
      'available' => AppColors.success,
      'sold' => colors.primary,
      'warranty' => AppColors.warning,
      'returned' => AppColors.error,
      _ => colors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.qr_code_2_outlined, color: statusColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serial['serial_number'] as String? ?? 'Serial',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                        serial['product_name']?.toString(),
                        serial['variant_name']?.toString(),
                        _shortDate(serial['warranty_expires_at'] as String?),
                      ]
                      .where((item) => item?.trim().isNotEmpty == true)
                      .join(' - '),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _shortDate(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  return 'Warranty ${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
}
