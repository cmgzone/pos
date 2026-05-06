import 'package:flutter/material.dart';

import '../../../core/services/branch_service.dart';
import '../../../core/theme/app_colors.dart';
import '../data/product_repository.dart';
import '../data/stock_transfer_repository.dart';

class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key});

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  List<Map<String, dynamic>> _transfers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _transfers = await StockTransferRepository.getForCurrentBranch();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestTransfer() async {
    final branches = (await BranchService.getBranches(activeOnly: true))
        .where((branch) => branch['id'] != BranchService.currentBranchId)
        .toList();
    final products = await ProductRepository.getAll();
    if (!mounted) return;
    if (branches.isEmpty || products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add another branch and products before transferring.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    Map<String, dynamic> selectedBranch = branches.first;
    Map<String, dynamic> selectedProduct = products.first;
    final quantityController = TextEditingController(text: '1');
    final noteController = TextEditingController();
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Request Stock Transfer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: selectedBranch,
                    decoration: const InputDecoration(
                      labelText: 'To branch',
                      prefixIcon: Icon(Icons.store_mall_directory_outlined),
                    ),
                    items: branches
                        .map(
                          (branch) => DropdownMenuItem(
                            value: branch,
                            child: Text(branch['name'] as String? ?? 'Branch'),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(
                            () => selectedBranch = value ?? selectedBranch,
                          ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: selectedProduct,
                    decoration: const InputDecoration(
                      labelText: 'Product',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    items: products
                        .map(
                          (product) => DropdownMenuItem(
                            value: product,
                            child: Text(
                              product['name'] as String? ?? 'Product',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setDialogState(
                            () => selectedProduct = value ?? selectedProduct,
                          ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final quantity =
                            double.tryParse(quantityController.text.trim()) ??
                            0;
                        setDialogState(() => saving = true);
                        try {
                          await StockTransferRepository.requestTransfer(
                            toBranchId: selectedBranch['id'] as String,
                            productId: selectedProduct['id'] as String,
                            quantity: quantity,
                            note: noteController.text,
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (error) {
                          setDialogState(() => saving = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(error.toString()),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('Request'),
              ),
            ],
          );
        },
      ),
    );

    quantityController.dispose();
    noteController.dispose();
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _changeStatus(
    Map<String, dynamic> transfer,
    String status,
  ) async {
    try {
      await StockTransferRepository.updateStatus(
        transfer['id'] as String,
        status: status,
        note: transfer['note'] as String?,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: AppColors.error),
      );
    }
  }

  List<PopupMenuEntry<String>> _statusActions(Map<String, dynamic> transfer) {
    final status = transfer['status'] as String? ?? 'requested';
    final isOutgoing =
        transfer['from_branch_id'] == BranchService.currentBranchId;
    final isIncoming =
        transfer['to_branch_id'] == BranchService.currentBranchId;
    final entries = <PopupMenuEntry<String>>[];
    if (status == 'requested' && isOutgoing) {
      entries.add(
        const PopupMenuItem(
          value: 'approved',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.verified_outlined),
            title: Text('Approve'),
          ),
        ),
      );
    }
    if (status == 'approved' && isIncoming) {
      entries.add(
        const PopupMenuItem(
          value: 'received',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.inventory_outlined),
            title: Text('Mark received'),
          ),
        ),
      );
    }
    if (status == 'requested' || status == 'approved') {
      entries.add(
        const PopupMenuItem(
          value: 'cancelled',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.cancel_outlined),
            title: Text('Cancel'),
          ),
        ),
      );
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Stock Transfers'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _requestTransfer,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Request'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _transfers.isEmpty
          ? const Center(
              child: Text(
                'No stock transfers yet',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _transfers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final transfer = _transfers[index];
                final outgoing =
                    transfer['from_branch_id'] == BranchService.currentBranchId;
                final quantity = (transfer['quantity'] as num? ?? 0).toDouble();
                final status = transfer['status'] as String? ?? 'requested';
                final actions = _statusActions(transfer);
                return Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              (outgoing ? AppColors.warning : AppColors.success)
                                  .withValues(alpha: 0.14),
                          child: Icon(
                            outgoing
                                ? Icons.call_made_rounded
                                : Icons.call_received_rounded,
                            color: outgoing
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                transfer['product_name'] as String? ??
                                    'Product',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${outgoing ? 'To' : 'From'} ${outgoing ? transfer['to_branch_name'] : transfer['from_branch_name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${quantity.toStringAsFixed(2)} ${transfer['unit'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              status.toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            tooltip: 'Transfer actions',
                            itemBuilder: (_) => actions,
                            onSelected: (value) =>
                                _changeStatus(transfer, value),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
