import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/branch_service.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/overlay_notice.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/product_repository.dart';
import '../data/stock_transfer_repository.dart';

enum _TransferAction { send, request }

class StockTransferScreen extends ConsumerStatefulWidget {
  const StockTransferScreen({super.key});

  @override
  ConsumerState<StockTransferScreen> createState() =>
      _StockTransferScreenState();
}

class _StockTransferScreenState extends ConsumerState<StockTransferScreen> {
  List<Map<String, dynamic>> _transfers = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      _transfers = await StockTransferRepository.getForCurrentBranch();
    } catch (error) {
      _loadError = AppErrorMessage.from(
        error,
        fallback: AppErrorMessage.loadFailed,
      );
    }
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
            title: Text('Send Stock to Another Branch'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: selectedBranch,
                    decoration: InputDecoration(
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
                  SizedBox(height: 12),
                  DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: selectedProduct,
                    decoration: InputDecoration(
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
                  SizedBox(height: 12),
                  TextField(
                    controller: quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
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
                child: Text('Cancel'),
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
                            AppOverlayNotice.showSnackBar(
                              context,
                              SnackBar(
                                content: Text(
                                  AppErrorMessage.from(
                                    error,
                                    fallback: AppErrorMessage.saveFailed,
                                  ),
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                icon: saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.send_outlined),
                label: Text('Send'),
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

  Future<void> _requestStockIn() async {
    final branches = (await BranchService.getBranches(activeOnly: true))
        .where((branch) => branch['id'] != BranchService.currentBranchId)
        .toList();
    if (!mounted) return;
    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add another branch before requesting stock.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    Map<String, dynamic> selectedBranch = branches.first;
    List<Map<String, dynamic>> sourceProducts;
    try {
      sourceProducts = await ProductRepository.getAllForBranch(
        selectedBranch['id'] as String,
      );
    } catch (_) {
      sourceProducts = const [];
    }
    if (!mounted) return;
    Map<String, dynamic>? selectedProduct = sourceProducts.isEmpty
        ? null
        : sourceProducts.first;
    var loadingProducts = false;
    var saving = false;
    final quantityController = TextEditingController(text: '1');
    final noteController = TextEditingController();

    Future<void> loadProductsForBranch(
      void Function(void Function()) setDialogState,
      String branchId,
    ) async {
      setDialogState(() {
        loadingProducts = true;
        sourceProducts = const [];
        selectedProduct = null;
      });
      try {
        final products = await ProductRepository.getAllForBranch(branchId);
        setDialogState(() {
          sourceProducts = products;
          selectedProduct = products.isEmpty ? null : products.first;
          loadingProducts = false;
        });
      } catch (_) {
        setDialogState(() {
          sourceProducts = const [];
          selectedProduct = null;
          loadingProducts = false;
        });
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Request Stock from Another Branch'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Map<String, dynamic>>(
                    initialValue: selectedBranch,
                    decoration: InputDecoration(
                      labelText: 'From branch',
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
                        : (value) {
                            if (value == null) return;
                            setDialogState(() => selectedBranch = value);
                            loadProductsForBranch(
                              setDialogState,
                              value['id'] as String,
                            );
                          },
                  ),
                  SizedBox(height: 12),
                  if (loadingProducts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Loading products from this branch...'),
                        ],
                      ),
                    )
                  else if (sourceProducts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'This branch has no products to request.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selectedProduct,
                      decoration: InputDecoration(
                        labelText: 'Product',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      items: sourceProducts
                          .map(
                            (product) => DropdownMenuItem(
                              value: product,
                              child: Text(
                                '${product['name'] as String? ?? 'Product'} '
                                '(${(product['stock'] as num? ?? 0).toDouble().toStringAsFixed(2)} '
                                '${product['stock_unit'] ?? product['unit'] ?? ''})',
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
                  SizedBox(height: 12),
                  TextField(
                    controller: quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
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
                child: Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: saving || selectedProduct == null
                    ? null
                    : () async {
                        final quantity =
                            double.tryParse(quantityController.text.trim()) ??
                            0;
                        setDialogState(() => saving = true);
                        try {
                          await StockTransferRepository.requestStockIn(
                            fromBranchId: selectedBranch['id'] as String,
                            productId: selectedProduct!['id'] as String,
                            quantity: quantity,
                            note: noteController.text,
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (error) {
                          setDialogState(() => saving = false);
                          if (context.mounted) {
                            AppOverlayNotice.showSnackBar(
                              context,
                              SnackBar(
                                content: Text(
                                  AppErrorMessage.from(
                                    error,
                                    fallback: AppErrorMessage.saveFailed,
                                  ),
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                icon: saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.call_received_rounded),
                label: Text('Request'),
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
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              error,
              fallback: 'Could not update the transfer. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
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
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          _load();
        }
      },
    );

    final isMobile =
        MediaQuery.sizeOf(context).width < AppConstants.mobileBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: Text('Stock Transfers'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          if (isMobile)
            PopupMenuButton<_TransferAction>(
              tooltip: 'New transfer',
              onSelected: (action) {
                switch (action) {
                  case _TransferAction.send:
                    _requestTransfer();
                  case _TransferAction.request:
                    _requestStockIn();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _TransferAction.request,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.call_received_rounded),
                    title: Text('Request stock'),
                    subtitle: Text('Ask another branch for items'),
                  ),
                ),
                PopupMenuItem(
                  value: _TransferAction.send,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.call_made_rounded),
                    title: Text('Send stock'),
                    subtitle: Text('Move items to another branch'),
                  ),
                ),
              ],
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: OutlinedButton.icon(
                onPressed: _requestTransfer,
                icon: Icon(Icons.call_made_rounded, size: 18),
                label: Text('Send stock'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FilledButton.icon(
                onPressed: _requestStockIn,
                icon: Icon(Icons.call_received_rounded, size: 18),
                label: Text('Request stock'),
              ),
            ),
          ],
          if (isMobile) SizedBox(width: 8),
        ],
      ),
      body: TrainingAnchor(
        id: 'transfers.workspace',
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sync_problem_rounded,
                        color: AppColors.warning,
                        size: 42,
                      ),
                      SizedBox(height: 12),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: Icon(Icons.refresh_rounded),
                        label: Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _transfers.isEmpty
            ? Center(
                child: Text(
                  'No stock transfers yet',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _transfers.length,
                separatorBuilder: (_, _) => SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final transfer = _transfers[index];
                  final outgoing =
                      transfer['from_branch_id'] ==
                      BranchService.currentBranchId;
                  final quantity = (transfer['quantity'] as num? ?? 0)
                      .toDouble();
                  final status = transfer['status'] as String? ?? 'requested';
                  final actions = _statusActions(transfer);
                  return Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                (outgoing
                                        ? AppColors.warning
                                        : AppColors.success)
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
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  transfer['product_name'] as String? ??
                                      'Product',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '${outgoing ? 'To' : 'From'} ${outgoing ? transfer['to_branch_name'] : transfer['from_branch_name']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              SizedBox(height: 4),
                              Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          if (actions.isNotEmpty) ...[
                            SizedBox(width: 4),
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
      ),
    );
  }
}
