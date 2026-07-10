import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../../app/app_shell.dart';
import '../data/stocktake_repository.dart';

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _sessionsFuture;
  Future<List<Map<String, dynamic>>>? _itemsFuture;
  String? _selectedSessionId;
  Map<String, dynamic>? _selectedSession;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = StocktakeRepository.getSessions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshSessions() {
    setState(() {
      _sessionsFuture = StocktakeRepository.getSessions();
    });
  }

  void _loadItems() {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    setState(() {
      _itemsFuture = StocktakeRepository.getItems(
        sessionId,
        search: _searchController.text,
      );
    });
  }

  Future<void> _startStocktake() async {
    final controller = TextEditingController(
      text: 'Stocktake ${DateTime.now().toString().substring(0, 10)}',
    );
    final noteController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Start Stocktake'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Note'),
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
              child: const Text('Start'),
            ),
          ],
        );
      },
    );
    if (result != true) return;
    setState(() => _busy = true);
    try {
      final id = await StocktakeRepository.createSession(
        name: controller.text,
        note: noteController.text,
      );
      final session = await StocktakeRepository.getSession(id);
      setState(() {
        _selectedSessionId = id;
        _selectedSession = session;
        _itemsFuture = StocktakeRepository.getItems(id);
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSession(Map<String, dynamic> session) async {
    final id = session['id'] as String;
    _searchController.clear();
    setState(() {
      _selectedSessionId = id;
      _selectedSession = session;
      _itemsFuture = StocktakeRepository.getItems(id);
    });
  }

  Future<void> _showCountDialog(Map<String, dynamic> item) async {
    final countController = TextEditingController(
      text: (item['counted_qty'] as num?)?.toString() ?? '',
    );
    final noteController = TextEditingController(
      text: item['note'] as String? ?? '',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final unit = UnitUtils.label(item['unit'] as String?);
        return AlertDialog(
          title: Text(item['product_name'] as String? ?? 'Product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: countController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: 'Counted $unit'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Note'),
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
              child: const Text('Save Count'),
            ),
          ],
        );
      },
    );
    if (result != true) return;
    final counted = double.tryParse(countController.text.trim());
    if (counted == null || counted < 0) {
      _showError('Enter a valid counted quantity.');
      return;
    }
    try {
      await StocktakeRepository.updateCount(
        itemId: item['id'] as String,
        countedQty: counted,
        note: noteController.text,
      );
      _loadItems();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _completeSession() async {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Stocktake?'),
        content: const Text(
          'Counted items will reconcile product stock immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await StocktakeRepository.completeSession(sessionId);
      _selectedSession = await StocktakeRepository.getSession(sessionId);
      _loadItems();
      _refreshSessions();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelSession() async {
    final sessionId = _selectedSessionId;
    if (sessionId == null) return;
    setState(() => _busy = true);
    try {
      await StocktakeRepository.cancelSession(sessionId);
      setState(() {
        _selectedSessionId = null;
        _selectedSession = null;
        _itemsFuture = null;
      });
      _refreshSessions();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedSessionId != null) {
      return _buildDetail();
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Stocktake'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshSessions,
            icon: const Icon(Icons.refresh_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _busy ? null : _startStocktake,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('New Count'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? const <Map<String, dynamic>>[];
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (sessions.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: _startStocktake,
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('Start First Stocktake'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final session = sessions[index];
              final itemCount = (session['item_count'] as num? ?? 0).toInt();
              final counted = (session['counted_count'] as num? ?? 0).toInt();
              final progress = itemCount == 0 ? 0.0 : counted / itemCount;
              return Card(
                child: ListTile(
                  onTap: () => _openSession(session),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(Icons.fact_check_rounded),
                  ),
                  title: Text(session['name'] as String? ?? 'Stocktake'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(value: progress),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${(progress * 100).round()}%'),
                      Text(
                        session['status'] as String? ?? 'draft',
                        style: Theme.of(context).textTheme.labelSmall,
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

  Widget _buildDetail() {
    final session = _selectedSession;
    final isCompleted = session?['status'] == 'completed';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _selectedSessionId = null;
              _selectedSession = null;
              _itemsFuture = null;
            });
            _refreshSessions();
          },
        ),
        title: Text(session?['name'] as String? ?? 'Stocktake'),
        actions: [
          if (!isCompleted)
            TextButton.icon(
              onPressed: _busy ? null : _cancelSession,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel'),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _busy || isCompleted ? null : _completeSession,
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('Complete'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _loadItems(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search product, SKU, or barcode',
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _itemsFuture,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <Map<String, dynamic>>[];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No items in this stocktake.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _StocktakeItemTile(
                      item: item,
                      enabled: !isCompleted,
                      onTap: () => _showCountDialog(item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StocktakeItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool enabled;
  final VoidCallback onTap;

  const _StocktakeItemTile({
    required this.item,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final expected = (item['expected_qty'] as num? ?? 0).toDouble();
    final counted = (item['counted_qty'] as num?)?.toDouble();
    final variance = (item['variance_qty'] as num? ?? 0).toDouble();
    final unit = item['unit'] as String? ?? UnitUtils.defaultUnit;
    final countedText = counted == null
        ? 'Not counted'
        : UnitUtils.formatWithUnit(counted, unit);
    final varianceColor = variance.abs() <= 0.001
        ? AppColors.success
        : variance > 0
        ? AppColors.warning
        : AppColors.error;
    return Card(
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: CircleAvatar(
          backgroundColor: varianceColor.withValues(alpha: 0.12),
          child: Icon(Icons.inventory_rounded, color: varianceColor),
        ),
        title: Text(item['product_name'] as String? ?? 'Product'),
        subtitle: Text(
          'Expected ${UnitUtils.formatWithUnit(expected, unit)}  |  Counted $countedText',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              variance >= 0
                  ? '+${UnitUtils.formatQuantity(variance)}'
                  : UnitUtils.formatQuantity(variance),
              style: TextStyle(
                color: varianceColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}
