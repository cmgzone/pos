import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/etims_service.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/unit_utils.dart';
import '../../shifts/data/shift_provider.dart';
import '../../shifts/data/shift_preferences_service.dart';
import '../../shifts/data/shift_repository.dart';
import '../../shifts/presentation/shift_auto_open_dialog.dart';
import '../../settings/data/payment_method_repository.dart';
import '../../products/data/product_repository.dart';
import '../../services/data/service_provider.dart';
import '../../services/data/service_repository.dart';
import '../../training/widgets/training_anchor.dart';
import '../../customers/presentation/customer_message_dialog.dart';
import '../../../widgets/compact_header_actions.dart';
import '../../../widgets/smart_import_preview_dialog.dart';
import '../data/sale_import_service.dart';
import '../data/sale_repository.dart';
import 'receipt_service.dart';

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  List<Map<String, dynamic>> _sales = [];
  bool _isLoading = true;
  String _selectedFilter = 'today';
  String _selectedSaleType = 'all';
  DateTime? _selectedDate;
  bool _isImporting = false;

  bool get _isCashierView =>
      RolePermissions.normalizeRole(SessionService.currentUserRole) ==
      RolePermissions.cashier;

  String? get _cashierFilterId {
    return _isCashierView ? SessionService.currentUserId : null;
  }

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);

    String? startDate;
    String? endDate;
    final now = DateTime.now();

    switch (_selectedFilter) {
      case 'today':
        startDate = DateTime(now.year, now.month, now.day).toIso8601String();
        endDate = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).toIso8601String();
        break;
      case 'yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        startDate = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
        ).toIso8601String();
        endDate = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          23,
          59,
          59,
        ).toIso8601String();
        break;
      case 'date':
        final selected = _selectedDate ?? now;
        startDate = DateTime(
          selected.year,
          selected.month,
          selected.day,
        ).toIso8601String();
        endDate = DateTime(
          selected.year,
          selected.month,
          selected.day,
          23,
          59,
          59,
        ).toIso8601String();
        break;
      case 'week':
        startDate = now.subtract(const Duration(days: 7)).toIso8601String();
        endDate = now.toIso8601String();
        break;
      case 'month':
        startDate = DateTime(now.year, now.month, 1).toIso8601String();
        endDate = now.toIso8601String();
        break;
      case 'all':
        break;
    }

    _sales = await SaleRepository.getAll(
      startDate: startDate,
      endDate: endDate,
      cashierId: _cashierFilterId,
      includeAllBranches:
          RolePermissions.normalizeRole(SessionService.currentUserRole) ==
          RolePermissions.admin,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  bool _canRefund(Map<String, dynamic> sale) {
    final paymentType = (sale['payment_type'] as String? ?? 'cash')
        .toLowerCase();
    final total = (sale['total_amount'] as num? ?? 0).toDouble().abs();
    final refunded = (sale['refunded_amount'] as num? ?? 0).toDouble();
    return RolePermissions.canRefundSales(SessionService.currentUserRole) &&
        !paymentType.startsWith('refund') &&
        refunded + 0.009 < total;
  }

  bool _canDeleteSale(Map<String, dynamic> sale) {
    final paymentType = (sale['payment_type'] as String? ?? 'cash')
        .toLowerCase();
    return RolePermissions.canRefundSales(SessionService.currentUserRole) &&
        !paymentType.startsWith('refund');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          _loadSales();
        }
      },
    );

    final visibleSales = _filteredSales;
    final totalRevenue = visibleSales.fold<double>(
      0.0,
      (sum, s) => sum + (s['total_amount'] as num? ?? 0).toDouble(),
    );
    final totalTax = visibleSales.fold<double>(
      0.0,
      (sum, s) => sum + (s['tax'] as num? ?? 0).toDouble(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 720 || Platform.isWindows;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            toolbarHeight: 50,
            title: Text(
              'Sales',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            actions: [
              CompactHeaderIconButton(
                onPressed: _loadSales,
                icon: Icons.refresh,
                tooltip: 'Refresh',
              ),
              if (!_isCashierView)
                isMobile
                    ? CompactHeaderIconButton(
                        onPressed: _isImporting ? null : _importSalesFromFile,
                        icon: Icons.upload_file_outlined,
                        tooltip: 'Import Excel/CSV sales',
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: CompactHeaderButton(
                          onPressed: _isImporting ? null : _importSalesFromFile,
                          icon: Icons.upload_file_outlined,
                          label: _isImporting ? 'Importing...' : 'Import',
                          filled: false,
                        ),
                      ),
              if (!_isCashierView && !isMobile)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CompactHeaderButton(
                    onPressed: _showRecordBookSaleDialog,
                    icon: Icons.post_add_outlined,
                    label: 'Record Sale',
                  ),
                ),
            ],
          ),
          floatingActionButton: !_isCashierView && isMobile
              ? FloatingActionButton.extended(
                  onPressed: _showRecordBookSaleDialog,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  icon: Icon(Icons.post_add_outlined),
                  label: Text('Record'),
                )
              : null,
          body: Column(
            children: [
              TrainingAnchor(
                id: 'sales.filters',
                child: _SalesHeader(
                  isMobile: isMobile,
                  totalSales: visibleSales.length,
                  totalRevenue: totalRevenue,
                  totalTax: totalTax,
                  selectedFilter: _selectedFilter,
                  selectedDate: _selectedDate,
                  onFilterSelected: _selectFilter,
                  selectedSaleType: _selectedSaleType,
                  onSaleTypeSelected: _selectSaleType,
                  isCashierView: _isCashierView,
                ),
              ),
              Divider(height: 1),
              Expanded(
                child: TrainingAnchor(
                  id: 'sales.list',
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : visibleSales.isEmpty
                      ? _EmptySalesState(isCashierView: _isCashierView)
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            isMobile ? 14 : 24,
                            isMobile ? 14 : 24,
                            isMobile ? 14 : 24,
                            isMobile ? 92 : 24,
                          ),
                          itemCount: visibleSales.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: isMobile ? 10 : 8),
                          itemBuilder: (context, index) {
                            final sale = visibleSales[index];
                            return _SaleRow(
                              sale: sale,
                              onTap: () => _showSaleDetails(sale),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> get _filteredSales {
    if (_selectedSaleType == 'all') {
      return _sales;
    }
    return _sales.where((sale) {
      final serviceCount = (sale['service_line_count'] as num? ?? 0).toInt();
      final productCount = (sale['product_line_count'] as num? ?? 0).toInt();
      return switch (_selectedSaleType) {
        'service' => serviceCount > 0 && productCount == 0,
        'product' => productCount > 0 && serviceCount == 0,
        'single_product' => productCount == 1 && serviceCount == 0,
        'multi_product' => productCount > 1 && serviceCount == 0,
        'mixed' => productCount > 0 && serviceCount > 0,
        _ => true,
      };
    }).toList();
  }

  Future<void> _selectFilter(String filter) async {
    if (filter == 'date') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() {
        _selectedFilter = 'date';
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
      await _loadSales();
      return;
    }
    if (_selectedFilter == filter) {
      return;
    }
    setState(() => _selectedFilter = filter);
    await _loadSales();
  }

  void _selectSaleType(String saleType) {
    if (_selectedSaleType == saleType) {
      return;
    }
    setState(() => _selectedSaleType = saleType);
  }

  Future<void> _importSalesFromFile() async {
    if (_isImporting) {
      return;
    }
    setState(() => _isImporting = true);

    SaleImportResult? result;
    Object? importError;
    try {
      result = await SaleImportService.pickAndImportSales(
        confirmPlan: (plan) => showSmartImportPreviewDialog(
          context,
          plan: plan,
          title: 'Piki AI Sales Import Check',
          actionLabel: 'Import Sales',
          minimumRequirements: const [
            'Summary sales can use just a total column.',
            'Product sales can use product_name, sku, barcode, product_id, or variant_id.',
            'Service sales can use service_name or service_id.',
          ],
          optionalColumns: const [
            'date',
            'quantity',
            'unit_price',
            'payment_type',
            'customer_name',
            'due_date',
            'reference',
          ],
          defaultsNote:
              'Blank optional fields are allowed. Quantity defaults to 1, payment defaults to cash, and item price can come from the product/service.',
        ),
      );
    } catch (error) {
      importError = error;
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }

    if (!mounted) {
      return;
    }

    if (importError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.withContext(
              importError,
              prefix: 'Could not import sales.',
              fallback:
                  'Use an .xlsx or .csv file with total for summary sales, or product/service identifier columns for itemized sales. Date, quantity, payment, customer, and reference fields are optional.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (result == null) {
      return;
    }
    final importResult = result;

    await _loadSales();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Sales Import Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${importResult.imported} sale${importResult.imported == 1 ? '' : 's'} imported'
              '${importResult.fileName == null ? '' : ' from ${importResult.fileName}'}.',
            ),
            if (importResult.productLines > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.productLines} product row${importResult.productLines == 1 ? '' : 's'} matched existing inventory and used POS stock rules.',
                style: TextStyle(color: AppColors.success),
              ),
            ],
            if (importResult.serviceLines > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.serviceLines} service row${importResult.serviceLines == 1 ? '' : 's'} imported as service sales.',
              ),
            ],
            if (importResult.summaryOnly > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.summaryOnly} summary-only row${importResult.summaryOnly == 1 ? '' : 's'} imported without item stock changes.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (importResult.skipped > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.skipped} row${importResult.skipped == 1 ? '' : 's'} skipped.',
                style: TextStyle(color: AppColors.warning),
              ),
            ],
            if (importResult.errors.isNotEmpty) ...[
              SizedBox(height: 12),
              Text(
                'Check these rows:',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              ...importResult.errors.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecordBookSaleDialog() async {
    final methods = (await PaymentMethodRepository.getAll(
      activeOnly: true,
    )).where((method) => method['is_credit'] != 1).toList();
    final services = await ServiceRepository.getServices(activeOnly: true);
    final products = await ProductRepository.getAll();
    if (!mounted) {
      return;
    }
    if (methods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an active non-credit payment method first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final totalController = TextEditingController();
    final taxController = TextEditingController(text: '0');
    final quantityController = TextEditingController(text: '1');
    final priceController = TextEditingController();
    final manualProductNameController = TextEditingController();
    final customerNameController = TextEditingController();
    final assignedStaffController = TextEditingController(
      text: ServiceRepository.defaultAssignedStaffName(),
    );
    final bayController = TextEditingController();
    final noteController = TextEditingController();
    DateTime saleDate = DateTime.now();
    Map<String, dynamic> selectedMethod = methods.first;
    Map<String, dynamic>? selectedService = services.isEmpty
        ? null
        : services.first;
    Map<String, dynamic>? selectedProduct = products.isEmpty
        ? null
        : products.first;
    var recordMode = 'product';
    bool isSaving = false;
    var savedCount = 0;
    var currentFields = selectedService == null
        ? <Map<String, dynamic>>[]
        : await ServiceRepository.getFieldsForService(
            selectedService['id'] as String,
          );
    if (!mounted) {
      return;
    }
    final fieldControllers = <String, TextEditingController>{};

    void resetFieldControllers(List<Map<String, dynamic>> fields) {
      for (final controller in fieldControllers.values) {
        controller.dispose();
      }
      fieldControllers.clear();
      for (final field in fields) {
        fieldControllers[field['id'] as String] = TextEditingController();
      }
    }

    resetFieldControllers(currentFields);

    void syncPriceFromService() {
      final service = selectedService;
      if (service == null) {
        return;
      }
      priceController.text = (service['base_price'] as num? ?? 0)
          .toStringAsFixed(2);
    }

    void syncPriceFromProduct() {
      final product = selectedProduct;
      if (product == null) {
        return;
      }
      priceController.text = (product['price'] as num? ?? 0).toStringAsFixed(2);
    }

    syncPriceFromService();
    if (recordMode == 'product') {
      syncPriceFromProduct();
    }

    Future<void> saveManualRecord({
      required BuildContext dialogContext,
      required StateSetter setDialogState,
      required bool keepOpen,
    }) async {
      final messenger = ScaffoldMessenger.of(dialogContext);
      final quantity = double.tryParse(quantityController.text.trim()) ?? 0;
      final price = double.tryParse(priceController.text.trim()) ?? 0;
      final total = recordMode == 'service' || recordMode == 'product'
          ? quantity * price
          : (double.tryParse(totalController.text.trim()) ?? 0);
      final tax = double.tryParse(taxController.text.trim()) ?? 0;
      if (recordMode == 'product' && selectedProduct == null) {
        if (manualProductNameController.text.trim().isEmpty) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Choose or enter a product to record.'),
              backgroundColor: AppColors.warning,
            ),
          );
          return;
        }
      }
      if (recordMode == 'service' && selectedService == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Choose a service to record.'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }
      if ((recordMode == 'service' || recordMode == 'product') &&
          (quantity <= 0 || price <= 0)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Enter quantity and price greater than 0.'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }
      if (recordMode == 'service') {
        final missingField = _firstMissingManualServiceField(
          currentFields,
          fieldControllers,
        );
        if (missingField != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('${missingField['label']} is required.'),
              backgroundColor: AppColors.warning,
            ),
          );
          return;
        }
      }
      if (total <= 0) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Enter a sale total greater than 0.'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }
      if (tax < 0 || tax > total) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Tax must be between 0 and total.'),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }

      setDialogState(() => isSaving = true);
      try {
        final service = selectedService;
        var product = selectedProduct;
        if (recordMode == 'product' && product == null) {
          final productName = manualProductNameController.text.trim();
          final productId = await ProductRepository.create(
            name: productName,
            price: price,
            cost: 0,
            stock: 0,
            lowStock: 0,
            trackStock: false,
          );
          product = {
            'id': productId,
            'name': productName,
            'price': price,
            'cost': 0,
            'unit': 'pcs',
            'stock_unit': 'pcs',
            'sale_unit': 'pcs',
            'sale_to_stock_factor': 1,
            'track_stock': 0,
          };
        }
        String? serviceOrderId;
        if (recordMode == 'service' && service != null) {
          serviceOrderId = await ServiceRepository.createOrder(
            serviceId: service['id'] as String,
            serviceName: service['name'] as String? ?? 'Service',
            customerName: customerNameController.text,
            entryMode: 'walk_in',
            checkedInAt: saleDate.toIso8601String(),
            status: 'completed',
            assignedStaff: assignedStaffController.text,
            assignedStaffUserId:
                ServiceRepository.currentAssignedStaffUserIdFor(
                  assignedStaffController.text,
                ),
            bayNumber: bayController.text,
            price: total,
            note: noteController.text,
            fieldValues: _buildManualServiceFieldValues(
              currentFields,
              fieldControllers,
            ),
          );
        }
        await SaleRepository.createSale(
          totalAmount: total,
          tax: tax,
          discount: 0,
          paymentType: selectedMethod['name'] as String? ?? 'Payment',
          isCashDrawer: (selectedMethod['is_cash_drawer'] as num? ?? 0) == 1,
          userId: SessionService.currentUserId.isNotEmpty
              ? SessionService.currentUserId
              : 'admin',
          items: recordMode == 'service' && service != null
              ? [
                  {
                    'line_type': 'service',
                    'service_order_id': serviceOrderId,
                    'service_id': service['id'],
                    'product_name': service['name'] as String? ?? 'Service',
                    'quantity': quantity,
                    'unit_price': price,
                  },
                ]
              : recordMode == 'product' && product != null
              ? [
                  {
                    'line_type': 'product',
                    'product_id': product['id'],
                    'product_name': product['name'] as String? ?? 'Product',
                    'quantity': quantity,
                    'unit_price': price,
                    'unit_cost': (product['cost'] as num? ?? 0).toDouble(),
                    'unit': UnitUtils.saleUnitForProduct(product),
                    'sale_to_stock_factor': UnitUtils.saleToStockFactor(
                      product,
                    ),
                  },
                ]
              : const [],
          amountTendered: total,
          changeGiven: 0,
          createdAt: saleDate,
        );
        if (!dialogContext.mounted) {
          return;
        }
        final container = ProviderScope.containerOf(
          dialogContext,
          listen: false,
        );
        container.invalidate(serviceOrdersProvider);
        container.invalidate(serviceTodayOrdersProvider);
        container.invalidate(serviceStatsProvider);
        container.invalidate(serviceSalesByDateProvider);
        savedCount += 1;

        if (!keepOpen) {
          Navigator.pop(dialogContext, true);
          return;
        }

        setDialogState(() {
          isSaving = false;
          totalController.clear();
          taxController.text = '0';
          quantityController.text = '1';
          manualProductNameController.clear();
          customerNameController.clear();
          assignedStaffController.text =
              ServiceRepository.defaultAssignedStaffName();
          bayController.clear();
          noteController.clear();
          for (final controller in fieldControllers.values) {
            controller.clear();
          }
          if (recordMode == 'service') {
            syncPriceFromService();
          } else if (recordMode == 'product') {
            syncPriceFromProduct();
          }
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Sale saved. Add the next record.'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (error) {
        setDialogState(() => isSaving = false);
        if (dialogContext.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                AppErrorMessage.withContext(
                  error,
                  prefix: 'Could not record sale.',
                  fallback: AppErrorMessage.saveFailed,
                ),
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Add Manual Sale'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: [
                      const ButtonSegment(
                        value: 'product',
                        icon: Icon(Icons.inventory_2_outlined),
                        label: Text('Product'),
                      ),
                      if (services.isNotEmpty)
                        const ButtonSegment(
                          value: 'service',
                          icon: Icon(Icons.design_services_outlined),
                          label: Text('Service'),
                        ),
                      const ButtonSegment(
                        value: 'manual',
                        icon: Icon(Icons.edit_note_outlined),
                        label: Text('Total'),
                      ),
                    ],
                    selected: {recordMode},
                    onSelectionChanged: isSaving
                        ? null
                        : (selection) {
                            setDialogState(() {
                              recordMode = selection.first;
                              if (recordMode == 'service') {
                                syncPriceFromService();
                              } else if (recordMode == 'product') {
                                syncPriceFromProduct();
                              }
                            });
                          },
                  ),
                  SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: saleDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked == null) {
                        return;
                      }
                      setDialogState(() {
                        saleDate = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          saleDate.hour,
                          saleDate.minute,
                        );
                      });
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Sale Date',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                      child: Text(
                        '${saleDate.month}/${saleDate.day}/${saleDate.year}',
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  if (recordMode == 'product') ...[
                    if (savedCount > 0) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          '$savedCount record${savedCount == 1 ? '' : 's'} saved',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                    ],
                    if (products.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: selectedProduct?['id'] as String?,
                        decoration: InputDecoration(
                          labelText: 'Product',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        items: products
                            .map(
                              (product) => DropdownMenuItem(
                                value: product['id'] as String,
                                child: Text(
                                  product['name'] as String? ?? 'Product',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isSaving
                            ? null
                            : (value) {
                                if (value == null) {
                                  return;
                                }
                                final product = products.firstWhere(
                                  (product) => product['id'] == value,
                                  orElse: () => products.first,
                                );
                                setDialogState(() {
                                  selectedProduct = product;
                                  syncPriceFromProduct();
                                });
                              },
                      )
                    else
                      TextField(
                        controller: manualProductNameController,
                        enabled: !isSaving,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Product Name',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                      ),
                    SizedBox(height: 12),
                    _ManualSaleResponsiveRow(
                      children: [
                        TextField(
                          controller: quantityController,
                          enabled: !isSaving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Quantity',
                            prefixIcon: Icon(Icons.format_list_numbered),
                          ),
                        ),
                        TextField(
                          controller: priceController,
                          enabled: !isSaving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Price',
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Sale Total',
                        prefixIcon: Icon(Icons.summarize_outlined),
                      ),
                      child: Text(
                        '${ShopSettings.currency}${((double.tryParse(quantityController.text.trim()) ?? 0) * (double.tryParse(priceController.text.trim()) ?? 0)).toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  if (recordMode == 'service' && services.isNotEmpty) ...[
                    if (savedCount > 0) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          '$savedCount record${savedCount == 1 ? '' : 's'} saved',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: selectedService?['id'] as String?,
                      decoration: InputDecoration(
                        labelText: 'Service',
                        prefixIcon: Icon(Icons.design_services_outlined),
                      ),
                      items: services
                          .map(
                            (service) => DropdownMenuItem(
                              value: service['id'] as String,
                              child: Text(
                                service['name'] as String? ?? 'Service',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              final service = services.firstWhere(
                                (service) => service['id'] == value,
                                orElse: () => services.first,
                              );
                              setDialogState(() {
                                selectedService = service;
                                syncPriceFromService();
                              });
                              ServiceRepository.getFieldsForService(value).then(
                                (fields) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  setDialogState(() {
                                    currentFields = fields;
                                    resetFieldControllers(fields);
                                  });
                                },
                                onError: (error) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppErrorMessage.from(
                                          error,
                                          fallback:
                                              'Could not load service fields.',
                                        ),
                                      ),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                },
                              );
                            },
                    ),
                    SizedBox(height: 12),
                    _ManualSaleResponsiveRow(
                      children: [
                        TextField(
                          controller: quantityController,
                          enabled: !isSaving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Quantity',
                            prefixIcon: Icon(Icons.format_list_numbered),
                          ),
                        ),
                        TextField(
                          controller: priceController,
                          enabled: !isSaving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Price',
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Sale Total',
                        prefixIcon: Icon(Icons.summarize_outlined),
                      ),
                      child: Text(
                        '${ShopSettings.currency}${((double.tryParse(quantityController.text.trim()) ?? 0) * (double.tryParse(priceController.text.trim()) ?? 0)).toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      leading: Icon(Icons.assignment_outlined),
                      title: Text('Service Details'),
                      subtitle: Text('Customer, staff, bay, notes'),
                      children: [
                        SizedBox(height: 8),
                        TextField(
                          controller: customerNameController,
                          enabled: !isSaving,
                          decoration: InputDecoration(
                            labelText: 'Customer Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        SizedBox(height: 12),
                        _ManualSaleResponsiveRow(
                          children: [
                            TextField(
                              controller: assignedStaffController,
                              enabled: !isSaving,
                              decoration: InputDecoration(
                                labelText: 'Assigned Staff',
                                prefixIcon: Icon(Icons.people_alt_outlined),
                              ),
                            ),
                            TextField(
                              controller: bayController,
                              enabled: !isSaving,
                              decoration: InputDecoration(
                                labelText: 'Bay / Room',
                                prefixIcon: Icon(
                                  Icons.room_preferences_outlined,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: noteController,
                          enabled: !isSaving,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Note',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                        if (currentFields.isNotEmpty) ...[
                          SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Custom Fields',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          SizedBox(height: 10),
                          ...currentFields.map((field) {
                            final fieldId = field['id'] as String;
                            final controller = fieldControllers[fieldId];
                            if (controller == null) {
                              return const SizedBox.shrink();
                            }
                            return _ManualServiceFieldInput(
                              field: field,
                              controller: controller,
                              enabled: !isSaving,
                              onChanged: (value) {
                                setDialogState(() {
                                  controller.text = value ?? '';
                                  final priceMap =
                                      field['price_map']
                                          as Map<String, double>?;
                                  final mapped = priceMap?[value];
                                  if (mapped != null && mapped > 0) {
                                    priceController.text = mapped
                                        .toStringAsFixed(2);
                                  }
                                });
                              },
                            );
                          }),
                        ],
                      ],
                    ),
                    SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: selectedMethod['id'] as String,
                    decoration: InputDecoration(
                      labelText: 'Payment Method',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    items: methods
                        .map(
                          (method) => DropdownMenuItem(
                            value: method['id'] as String,
                            child: Text(method['name'] as String? ?? 'Payment'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedMethod = methods.firstWhere(
                          (method) => method['id'] == value,
                          orElse: () => methods.first,
                        );
                      });
                    },
                  ),
                  SizedBox(height: 12),
                  if (recordMode == 'manual') ...[
                    TextField(
                      controller: totalController,
                      enabled: !isSaving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Total Amount',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  TextField(
                    controller: taxController,
                    enabled: !isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Tax Included',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx, false),
              child: Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: isSaving
                  ? null
                  : () => saveManualRecord(
                      dialogContext: ctx,
                      setDialogState: setDialogState,
                      keepOpen: true,
                    ),
              icon: Icon(Icons.add, size: 18),
              label: Text('Save & Add Another'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () => saveManualRecord(
                      dialogContext: ctx,
                      setDialogState: setDialogState,
                      keepOpen: false,
                    ),
              child: isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Save Sale'),
            ),
          ],
        ),
      ),
    );

    totalController.dispose();
    taxController.dispose();
    quantityController.dispose();
    priceController.dispose();
    manualProductNameController.dispose();
    customerNameController.dispose();
    assignedStaffController.dispose();
    bayController.dispose();
    noteController.dispose();
    for (final controller in fieldControllers.values) {
      controller.dispose();
    }

    if (saved == true || savedCount > 0) {
      await _loadSales();
    }
  }

  void _showSaleDetails(Map<String, dynamic> sale) async {
    final details = await SaleRepository.getSaleWithItems(sale['id'] as String);
    if (details == null || !mounted) {
      return;
    }

    final items = details['items'] as List<Map<String, dynamic>>? ?? [];
    final paymentType = (sale['payment_type'] as String? ?? 'cash')
        .toLowerCase();
    final isCash = paymentType == 'cash';
    final amountTendered = (sale['amount_tendered'] as num?)?.toDouble() ?? 0;
    final changeGiven = (sale['change_given'] as num?)?.toDouble() ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.receipt, color: AppColors.primaryLight),
            SizedBox(width: 12),
            Text('Sale Details'),
            Spacer(),
            Text(
              '#${(sale['id'] as String).substring(0, 8)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date & payment
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Date: ${_formatDate(sale['created_at'] as String? ?? '')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _paymentTypeColor(sale).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _paymentTypeLabel(sale),
                      style: TextStyle(
                        color: _paymentTypeColor(sale),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if ((sale['customer_name'] as String?)?.isNotEmpty == true) ...[
                SizedBox(height: 10),
                _DetailRow(
                  label: 'Customer',
                  value: sale['customer_name'] as String,
                ),
              ],
              if ((sale['cashier_name'] as String?)?.isNotEmpty == true) ...[
                SizedBox(height: 8),
                _DetailRow(
                  label: 'Cashier',
                  value: sale['cashier_name'] as String,
                ),
              ],
              if ((sale['due_date'] as String?)?.isNotEmpty == true) ...[
                SizedBox(height: 8),
                _DetailRow(
                  label: 'Due Date',
                  value: sale['due_date'] as String,
                  valueColor: (sale['balance_due'] as num? ?? 0) > 0
                      ? AppColors.warning
                      : null,
                ),
              ],
              SizedBox(height: 16),
              Divider(),
              // Items
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        (item['line_type'] as String? ?? 'product') == 'service'
                            ? Icons.design_services_rounded
                            : Icons.inventory_2_outlined,
                        color:
                            (item['line_type'] as String? ?? 'product') ==
                                'service'
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['product_name'] as String? ?? 'Unknown',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        UnitUtils.formatWithUnit(
                          item['quantity'] as num?,
                          item['unit'] as String?,
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(width: 24),
                      Text(
                        '${ShopSettings.currency}${((item['unit_price'] as num) * (item['quantity'] as num)).toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(),
              SizedBox(height: 8),
              _DetailRow(
                label: 'Subtotal',
                value:
                    '${ShopSettings.currency}${((sale['total_amount'] as num) - (sale['tax'] as num) + (sale['discount'] as num)).toStringAsFixed(2)}',
              ),
              _DetailRow(
                label: 'Tax',
                value:
                    '${ShopSettings.currency}${(sale['tax'] as num).toStringAsFixed(2)}',
              ),
              if ((sale['discount'] as num? ?? 0) > 0)
                _DetailRow(
                  label: 'Discount',
                  value:
                      '-${ShopSettings.currency}${(sale['discount'] as num).toStringAsFixed(2)}',
                ),
              if ((sale['refunded_amount'] as num? ?? 0) > 0)
                _DetailRow(
                  label: 'Refunded',
                  value:
                      '${ShopSettings.currency}${(sale['refunded_amount'] as num).toStringAsFixed(2)}',
                  valueColor: AppColors.error,
                ),
              if ((sale['balance_due'] as num? ?? 0) > 0)
                _DetailRow(
                  label: 'Kopesha Balance',
                  value:
                      '${ShopSettings.currency}${(sale['balance_due'] as num).toStringAsFixed(2)}',
                  valueColor: AppColors.warning,
                ),
              if (isCash && amountTendered > 0) ...[
                _DetailRow(
                  label: 'Cash Received',
                  value:
                      '${ShopSettings.currency}${amountTendered.toStringAsFixed(2)}',
                ),
                _DetailRow(
                  label: 'Change Returned',
                  value:
                      '${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}',
                ),
              ],
              SizedBox(height: 8),
              _DetailRow(
                label: 'Profit',
                value:
                    '${ShopSettings.currency}${(sale['profit'] as num? ?? 0).toStringAsFixed(2)}',
                valueColor: (sale['profit'] as num? ?? 0) >= 0
                    ? AppColors.success
                    : AppColors.error,
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '${ShopSettings.currency}${(sale['total_amount'] as num).toStringAsFixed(2)}',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (_canRefund(sale))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showRefundDialog(sale);
              },
              child: Text('Return', style: TextStyle(color: AppColors.error)),
            ),
          if (_canDeleteSale(sale))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteSaleWithConfirmation(sale);
              },
              child: Text('Delete', style: TextStyle(color: AppColors.error)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close')),
          if ((sale['etims_status'] as String?) != 'submitted')
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _submitEtimsForSale(sale);
              },
              icon: Icon(Icons.account_balance_outlined, size: 18),
              label: Text('Submit eTIMS'),
            ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _sendReceiptMessage(sale);
            },
            icon: Icon(Icons.send_outlined, size: 18),
            label: Text('Send Receipt'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final totalAmount = (sale['total_amount'] as num).toDouble();
              final saleTax = (sale['tax'] as num).toDouble();
              final saleDiscount = (sale['discount'] as num).toDouble();
              ReceiptService.showReceiptPreview(
                context,
                saleId: sale['id'] as String,
                total: totalAmount,
                subtotal: totalAmount - saleTax + saleDiscount,
                tax: saleTax,
                discount: saleDiscount,
                paymentType: sale['payment_type'] as String? ?? 'cash',
                items: items,
                customerName: sale['customer_name'] as String?,
                amountTendered:
                    (sale['amount_tendered'] as num?)?.toDouble() ?? 0,
                changeGiven: (sale['change_given'] as num?)?.toDouble() ?? 0,
                balanceDue: (sale['balance_due'] as num?)?.toDouble() ?? 0,
                dueDate: sale['due_date'] as String?,
                cashierName: sale['cashier_name'] as String?,
                documentDate: sale['created_at'] as String?,
                etimsStatus: sale['etims_status'] as String?,
                etimsInvoiceNumber: sale['etims_invoice_number'] as String?,
                etimsControlUnitInvoiceNumber:
                    sale['etims_control_unit_invoice_number'] as String?,
                etimsControlUnitSerial:
                    sale['etims_control_unit_serial'] as String?,
                etimsVerificationUrl: sale['etims_verification_url'] as String?,
                etimsQrCode: sale['etims_qr_code'] as String?,
                showTenderedBreakdown: isCash,
              );
            },
            child: Text('Print'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitEtimsForSale(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as String?)?.trim();
    if (saleId == null || saleId.isEmpty) {
      return;
    }
    try {
      final result = await EtimsService.submitSale(saleId);
      if (!mounted) {
        return;
      }
      await _loadSales();
      if (!mounted) {
        return;
      }
      final submitted = result.status == 'submitted';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            submitted
                ? 'KRA eTIMS submitted'
                : 'KRA eTIMS marked ${result.status.replaceAll('_', ' ')}',
          ),
          backgroundColor: submitted ? AppColors.success : AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              e,
              fallback: 'Could not submit this sale to KRA eTIMS.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _sendReceiptMessage(Map<String, dynamic> sale) async {
    final customerName =
        (sale['customer_name'] as String?)?.trim().isNotEmpty == true
        ? (sale['customer_name'] as String).trim()
        : 'Customer';
    String phone = '';
    String email = '';
    final customerId = (sale['customer_id'] as String?)?.trim();
    if (customerId != null && customerId.isNotEmpty) {
      final rows = await DatabaseService.rawQuery(
        'SELECT phone, email FROM customers WHERE id = ? AND deleted_at IS NULL LIMIT 1',
        [customerId],
      );
      if (rows.isNotEmpty) {
        phone = rows.first['phone'] as String? ?? '';
        email = rows.first['email'] as String? ?? '';
      }
    }
    if (phone.trim().isEmpty && email.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a customer phone number or email before sending receipt.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final saleId = sale['id'] as String? ?? '';
    final total = (sale['total_amount'] as num? ?? 0).toDouble();
    final amount = '${ShopSettings.currency}${total.toStringAsFixed(2)}';
    if (!mounted) {
      return;
    }
    await CustomerMessageDialog.show(
      context,
      customerName: customerName,
      phoneNumber: phone,
      emailAddress: email,
      initialMessage: MessagingService.receiptMessage(
        customerName: customerName,
        saleId: saleId.isEmpty
            ? 'receipt'
            : saleId.substring(0, saleId.length < 8 ? saleId.length : 8),
        amount: amount,
      ),
      metadata: {'source': 'receipt', 'saleId': saleId, 'amount': total},
    );
  }

  Future<void> _deleteSaleWithConfirmation(Map<String, dynamic> sale) async {
    final saleId = sale['id'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Sale?'),
        content: Text(
          'Delete sale #${saleId.substring(0, 8)} from sales history and reports? Use Return instead when you need stock restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await SaleRepository.deleteSale(saleId);
      if (!mounted) {
        return;
      }
      await _loadSales();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale deleted'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.withContext(
              error,
              prefix: 'Could not delete sale.',
              fallback: 'Could not delete this sale. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showRefundDialog(Map<String, dynamic> sale) async {
    final refundableItems = await SaleRepository.getRefundableItems(
      sale['id'] as String,
    );
    if (!mounted) {
      return;
    }
    if (refundableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This sale has no returnable items left'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final noteController = TextEditingController();
    final quantityControllers = <String, TextEditingController>{
      for (final item in refundableItems)
        item['refund_key'] as String: TextEditingController(),
    };
    bool isSaving = false;

    final refundId = await showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Return Items'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose the item quantities to return for sale #${(sale['id'] as String).substring(0, 8)}.',
                ),
                SizedBox(height: 12),
                Text(
                  'Product stock will be restored automatically where applicable.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: refundableItems.length,
                    separatorBuilder: (_, _) => SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = refundableItems[index];
                      final controller =
                          quantityControllers[item['refund_key']]!;
                      final refundableQuantity =
                          (item['refundable_quantity'] as num? ?? 0).toDouble();
                      final unit = item['unit'] as String?;
                      final isCompact = MediaQuery.of(context).size.width < 560;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: isCompact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['product_name'] as String? ?? 'Item',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Returnable: ${UnitUtils.formatWithUnit(refundableQuantity, unit)}',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Price: ${ShopSettings.currency}${(item['unit_price'] as num? ?? 0).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  TextField(
                                    controller: controller,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: 'Return Qty',
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['product_name'] as String? ??
                                              'Item',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Returnable: ${UnitUtils.formatWithUnit(refundableQuantity, unit)}',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          'Price: ${ShopSettings.currency}${(item['unit_price'] as num? ?? 0).toStringAsFixed(2)}',
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
                                  SizedBox(width: 12),
                                  SizedBox(
                                    width: 130,
                                    child: TextField(
                                      controller: controller,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: 'Return Qty',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Reason / note',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final selectedItems = <Map<String, dynamic>>[];
                        for (final item in refundableItems) {
                          final controller =
                              quantityControllers[item['refund_key']]!;
                          final quantity = double.tryParse(
                            controller.text.trim(),
                          );
                          if (quantity == null || quantity <= 0) {
                            continue;
                          }
                          selectedItems.add({
                            'refund_key': item['refund_key'],
                            'quantity': quantity,
                          });
                        }

                        if (selectedItems.isEmpty) {
                          throw Exception('Choose at least one item to return');
                        }

                        final originalPaymentType =
                            (sale['payment_type'] as String? ?? 'cash')
                                .toLowerCase();
                        final requiresOpenShift = originalPaymentType == 'cash';
                        Map<String, dynamic>? shift;
                        var openedShiftForRefund = false;
                        if (requiresOpenShift) {
                          final userId = currentShiftActorId();
                          final access =
                              await ShiftRepository.resolveCurrentShift(
                                userId: userId,
                              );
                          if (access.autoClosedShift != null &&
                              context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Your previous-day shift was auto-closed before this cash refund.',
                                ),
                                backgroundColor: AppColors.warning,
                              ),
                            );
                          }
                          shift = access.currentShift;
                          if (shift == null &&
                              ShiftRepository.roleRequiresManagedShift(
                                SessionService.currentUserRole,
                              )) {
                            if (!context.mounted) {
                              setDialogState(() => isSaving = false);
                              return;
                            }
                            final suggestedOpeningCash =
                                await ShiftPreferencesService.getLastOpeningCash(
                                  userId,
                                );
                            if (!context.mounted) {
                              setDialogState(() => isSaving = false);
                              return;
                            }
                            final opening = await showShiftAutoOpenDialog(
                              context,
                              transactionLabel: 'cash refund',
                              suggestedOpeningCash: suggestedOpeningCash,
                            );
                            if (!context.mounted || opening == null) {
                              setDialogState(() => isSaving = false);
                              return;
                            }
                            shift = await ShiftRepository.openShift(
                              userId: userId,
                              cashierName: ShiftRepository.normalizeActorName(
                                SessionService.currentUserName,
                              ),
                              openingCash: opening.openingCash,
                              note:
                                  opening.note ??
                                  'Auto-opened on first cash transaction.',
                            );
                            await ShiftPreferencesService.saveLastOpeningCash(
                              userId,
                              opening.openingCash,
                            );
                            openedShiftForRefund = true;
                          }
                          if (openedShiftForRefund && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'A new shift was auto-opened for this cash refund.',
                                ),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        }

                        final refundId = await SaleRepository.refundSale(
                          saleId: sale['id'] as String,
                          userId: SessionService.currentUserId.isNotEmpty
                              ? SessionService.currentUserId
                              : 'admin',
                          shiftId: shift?['id'] as String?,
                          note: noteController.text,
                          items: selectedItems,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx, refundId);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppErrorMessage.from(
                                  e,
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => isSaving = false);
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Refund'),
            ),
          ],
        ),
      ),
    );

    noteController.dispose();
    for (final controller in quantityControllers.values) {
      controller.dispose();
    }

    if (refundId != null && mounted) {
      await _loadSales();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale refunded and stock restored'),
          backgroundColor: AppColors.success,
        ),
      );
      await _showRefundReceipt(refundId, sale);
    }
  }

  Future<void> _showRefundReceipt(
    String refundId,
    Map<String, dynamic> originalSale,
  ) async {
    final refundDetails = await SaleRepository.getSaleWithItems(refundId);
    if (refundDetails == null || !mounted) {
      return;
    }

    final refundTotal = (refundDetails['total_amount'] as num? ?? 0)
        .toDouble()
        .abs();
    final refundTax = (refundDetails['tax'] as num? ?? 0).toDouble().abs();
    final refundDiscount = (refundDetails['discount'] as num? ?? 0)
        .toDouble()
        .abs();

    await ReceiptService.showReceiptPreview(
      context,
      saleId: refundId,
      total: refundTotal,
      subtotal: refundTotal - refundTax + refundDiscount,
      tax: refundTax,
      discount: refundDiscount,
      paymentType: refundDetails['payment_type'] as String? ?? 'refund_cash',
      items:
          refundDetails['items'] as List<Map<String, dynamic>>? ??
          <Map<String, dynamic>>[],
      customerName: refundDetails['customer_name'] as String?,
      previewTitle: 'Refund Receipt Preview',
      documentTitle: 'Refund Receipt',
      fileNamePrefix: 'refund_receipt',
      recordLabel: 'Refund',
      referenceSaleId: originalSale['id'] as String,
      note: refundDetails['refund_note'] as String?,
      useAbsoluteAmounts: true,
      cashierName: refundDetails['cashier_name'] as String?,
      documentDate: refundDetails['created_at'] as String?,
      etimsStatus: refundDetails['etims_status'] as String?,
      etimsInvoiceNumber: refundDetails['etims_invoice_number'] as String?,
      etimsControlUnitInvoiceNumber:
          refundDetails['etims_control_unit_invoice_number'] as String?,
      etimsControlUnitSerial:
          refundDetails['etims_control_unit_serial'] as String?,
      etimsVerificationUrl: refundDetails['etims_verification_url'] as String?,
      etimsQrCode: refundDetails['etims_qr_code'] as String?,
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) {
      return iso;
    }
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _paymentTypeLabel(Map<String, dynamic> sale) {
    final type = (sale['payment_type'] as String? ?? 'cash').toLowerCase();
    if (type == 'kopesha') {
      return 'KOPESHA [CREDIT]';
    }
    if (type == 'refund_cash') {
      return 'REFUND [CASH]';
    }
    if (type == 'refund_kopesha') {
      return 'REFUND [KOPESHA]';
    }
    return type.toUpperCase();
  }

  Color _paymentTypeColor(Map<String, dynamic> sale) {
    final type = (sale['payment_type'] as String? ?? 'cash').toLowerCase();
    if (type == 'kopesha') {
      return AppColors.warning;
    }
    if (type.startsWith('refund')) {
      return AppColors.error;
    }
    return AppColors.primaryLight;
  }
}

Map<String, dynamic>? _firstMissingManualServiceField(
  List<Map<String, dynamic>> fields,
  Map<String, TextEditingController> controllers,
) {
  for (final field in fields) {
    final isRequired = (field['is_required'] as num? ?? 0) == 1;
    final controller = controllers[field['id'] as String];
    if (isRequired && (controller?.text.trim().isEmpty ?? true)) {
      return field;
    }
  }
  return null;
}

List<Map<String, dynamic>> _buildManualServiceFieldValues(
  List<Map<String, dynamic>> fields,
  Map<String, TextEditingController> controllers,
) {
  return fields
      .map(
        (field) => {
          'field_id': field['id'],
          'field_label': field['label'],
          'field_type': field['field_type'],
          'value_text': controllers[field['id'] as String]?.text ?? '',
        },
      )
      .toList();
}

class _ManualSaleResponsiveRow extends StatelessWidget {
  final List<Widget> children;

  const _ManualSaleResponsiveRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _ManualServiceFieldInput extends StatelessWidget {
  final Map<String, dynamic> field;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _ManualServiceFieldInput({
    required this.field,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final type = field['field_type'] as String? ?? 'text';
    final label = field['label'] as String? ?? 'Detail';
    final isRequired = (field['is_required'] as num? ?? 0) == 1;
    final decoratedLabel = isRequired ? '$label *' : label;

    if (type == 'select') {
      final options = (field['options'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: controller.text.isEmpty ? null : controller.text,
          decoration: InputDecoration(labelText: decoratedLabel),
          items: options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: decoratedLabel,
          hintText: type == 'date' ? 'YYYY-MM-DD HH:MM' : null,
        ),
      ),
    );
  }
}

class _SalesHeader extends StatelessWidget {
  final bool isMobile;
  final int totalSales;
  final double totalRevenue;
  final double totalTax;
  final String selectedFilter;
  final DateTime? selectedDate;
  final ValueChanged<String> onFilterSelected;
  final String selectedSaleType;
  final ValueChanged<String> onSaleTypeSelected;
  final bool isCashierView;

  const _SalesHeader({
    required this.isMobile,
    required this.totalSales,
    required this.totalRevenue,
    required this.totalTax,
    required this.selectedFilter,
    required this.selectedDate,
    required this.onFilterSelected,
    required this.selectedSaleType,
    required this.onSaleTypeSelected,
    required this.isCashierView,
  });

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      isMobile ? 12 : 20,
      isMobile ? 8 : 0,
      isMobile ? 12 : 20,
      isMobile ? 10 : 12,
    );

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Text(
              selectedFilter == 'today'
                  ? 'Today'
                  : selectedFilter == 'yesterday'
                  ? 'Yesterday'
                  : selectedFilter == 'date' && selectedDate != null
                  ? '${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}'
                  : selectedFilter == 'week'
                  ? 'Last 7 days'
                  : selectedFilter == 'month'
                  ? 'This month'
                  : 'All sales',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '${ShopSettings.currency}${totalRevenue.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 8),
          ],
          if (isMobile)
            Row(
              children: [
                Expanded(
                  child: _MiniSalesMetric(
                    label: 'Sales',
                    value: '$totalSales',
                    icon: Icons.receipt_long,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _MiniSalesMetric(
                    label: 'Tax',
                    value:
                        '${ShopSettings.currency}${totalTax.toStringAsFixed(2)}',
                    icon: Icons.account_balance_outlined,
                    color: AppColors.warning,
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatCard(
                  icon: Icons.receipt_long,
                  label: 'Total Sales',
                  value: '$totalSales',
                  color: AppColors.primary,
                ),
                _StatCard(
                  icon: Icons.attach_money,
                  label: 'Revenue',
                  value:
                      '${ShopSettings.currency}${totalRevenue.toStringAsFixed(2)}',
                  color: AppColors.success,
                ),
                _StatCard(
                  icon: Icons.account_balance,
                  label: 'Tax Collected',
                  value:
                      '${ShopSettings.currency}${totalTax.toStringAsFixed(2)}',
                  color: AppColors.warning,
                ),
              ],
            ),
          SizedBox(height: 10),
          _SalesFilterBar(
            selectedFilter: selectedFilter,
            onSelected: onFilterSelected,
            isMobile: isMobile,
          ),
          SizedBox(height: 8),
          _SaleTypeFilterBar(
            selectedType: selectedSaleType,
            onSelected: onSaleTypeSelected,
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }
}

class _SalesFilterBar extends StatelessWidget {
  final String selectedFilter;
  final ValueChanged<String> onSelected;
  final bool isMobile;

  const _SalesFilterBar({
    required this.selectedFilter,
    required this.onSelected,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final filters = const [
      ('today', 'Today'),
      ('yesterday', 'Yesterday'),
      ('date', 'Pick Date'),
      ('week', 'Week'),
      ('month', 'Month'),
      ('all', 'All'),
    ];

    if (isMobile) {
      return SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: filters.length,
          separatorBuilder: (_, _) => SizedBox(width: 8),
          itemBuilder: (context, index) {
            final filter = filters[index];
            return SizedBox(
              width: filter.$1 == 'yesterday' || filter.$1 == 'date' ? 92 : 64,
              child: _CompactFilterButton(
                label: filter.$2,
                isSelected: selectedFilter == filter.$1,
                onTap: () => onSelected(filter.$1),
              ),
            );
          },
        ),
      );
    }

    return Wrap(
      children: [
        for (final filter in filters)
          _FilterChip(
            label: filter.$2,
            isSelected: selectedFilter == filter.$1,
            onTap: () => onSelected(filter.$1),
          ),
      ],
    );
  }
}

class _CompactFilterButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CompactFilterButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _SaleTypeFilterBar extends StatelessWidget {
  final String selectedType;
  final ValueChanged<String> onSelected;
  final bool isMobile;

  const _SaleTypeFilterBar({
    required this.selectedType,
    required this.onSelected,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final filters = const [
      ('all', 'All Types', Icons.list_alt_outlined),
      ('product', 'Products', Icons.inventory_2_outlined),
      ('single_product', 'One Product', Icons.looks_one_outlined),
      ('multi_product', 'Multi Product', Icons.view_list_outlined),
      ('service', 'Services', Icons.design_services_outlined),
      ('mixed', 'Mixed', Icons.merge_type_outlined),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => SizedBox(width: 6),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = selectedType == filter.$1;
          return _SaleTypeChip(
            label: filter.$2,
            icon: filter.$3,
            isSelected: selected,
            onTap: () => onSelected(filter.$1),
          );
        },
      ),
    );
  }
}

class _SaleTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SaleTypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? Theme.of(context).colorScheme.secondary
          : context.appSurfaceHighlight,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? context.appBackground
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? context.appBackground
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniSalesMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniSalesMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySalesState extends StatelessWidget {
  final bool isCashierView;

  const _EmptySalesState({required this.isCashierView});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            SizedBox(height: 16),
            Text(
              'No sales found',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            Text(
              isCashierView
                  ? 'Completed branch sales will appear here.'
                  : 'Complete a sale from POS or record an old sale.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  final Map<String, dynamic> sale;
  final VoidCallback onTap;
  const _SaleRow({required this.sale, required this.onTap});

  Color _badgeColor(String paymentType) {
    if (paymentType == 'kopesha') {
      return AppColors.warning;
    }
    if (paymentType.startsWith('refund')) {
      return AppColors.error;
    }
    return AppColors.primaryLight;
  }

  String _badgeLabel(String paymentType) {
    if (paymentType == 'kopesha') {
      return 'KOPESHA';
    }
    if (paymentType == 'refund_cash') {
      return 'REFUND';
    }
    if (paymentType == 'refund_kopesha') {
      return 'REFUND';
    }
    return paymentType.toUpperCase();
  }

  String _refundStateLabel(Map<String, dynamic> sale) {
    final total = (sale['total_amount'] as num? ?? 0).toDouble().abs();
    final refunded = (sale['refunded_amount'] as num? ?? 0).toDouble();
    if (refunded <= 0.009) {
      return '';
    }
    if (refunded + 0.009 >= total) {
      return 'Refunded';
    }
    return 'Partial Refund';
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = sale['created_at'] as String? ?? '';
    final dt = DateTime.tryParse(createdAt);
    final paymentType = (sale['payment_type'] as String? ?? 'cash')
        .toLowerCase();
    final isRefund = paymentType.startsWith('refund');
    final serviceLineCount = (sale['service_line_count'] as num? ?? 0).toInt();
    final productLineCount = (sale['product_line_count'] as num? ?? 0).toInt();
    final isServiceSale = serviceLineCount > 0 && productLineCount == 0;
    final isMixedSale = serviceLineCount > 0 && productLineCount > 0;
    final serviceNames = (sale['service_names'] as String?)?.trim() ?? '';
    final productNames = (sale['product_names'] as String?)?.trim() ?? '';
    final saleTypeLabel = isServiceSale
        ? 'Service sale'
        : isMixedSale
        ? 'Products + services'
        : productLineCount == 1
        ? 'One product sale'
        : productLineCount > 1
        ? 'Multi-product sale'
        : 'Product sale';
    final saleDisplayNames = isServiceSale
        ? serviceNames
        : isMixedSale
        ? [
            if (productNames.isNotEmpty) productNames,
            if (serviceNames.isNotEmpty) serviceNames,
          ].join(' + ')
        : productNames;
    final hasRefund = (sale['refund_sale_id'] as String?)?.isNotEmpty == true;
    final refundState = _refundStateLabel(sale);
    final dateStr = dt != null
        ? '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560 || Platform.isWindows) {
          return _MobileSaleRowCard(
            sale: sale,
            onTap: onTap,
            paymentType: paymentType,
            isRefund: isRefund,
            isServiceSale: isServiceSale,
            saleTypeLabel: saleTypeLabel,
            serviceNames: saleDisplayNames,
            dateStr: dateStr,
            refundState: hasRefund
                ? (refundState.isEmpty ? 'Refunded' : refundState)
                : '',
            badgeColor: _badgeColor(paymentType),
            badgeLabel: _badgeLabel(paymentType),
          );
        }

        return Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          (isRefund
                                  ? AppColors.error
                                  : isServiceSale
                                  ? Theme.of(context).colorScheme.secondary
                                  : AppColors.success)
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isRefund
                          ? Icons.assignment_return
                          : isServiceSale
                          ? Icons.design_services_rounded
                          : Icons.receipt_long,
                      color: isRefund
                          ? AppColors.error
                          : isServiceSale
                          ? Theme.of(context).colorScheme.secondary
                          : AppColors.success,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sale #${(sale['id'] as String).substring(0, 8)}',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          saleDisplayNames.isNotEmpty
                              ? '$saleTypeLabel - $saleDisplayNames'
                              : saleTypeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isServiceSale
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if ((sale['customer_name'] as String?)?.isNotEmpty ==
                            true) ...[
                          SizedBox(height: 4),
                          Text(
                            sale['customer_name'] as String,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (hasRefund) ...[
                          SizedBox(height: 4),
                          Text(
                            refundState.isEmpty ? 'Refunded' : refundState,
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _badgeColor(paymentType).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _badgeLabel(paymentType),
                      style: TextStyle(
                        color: _badgeColor(paymentType),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${ShopSettings.currency}${(sale['total_amount'] as num? ?? 0).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isRefund ? AppColors.error : AppColors.success,
                        ),
                      ),
                      Text(
                        'Profit: ${ShopSettings.currency}${(sale['profit'] as num? ?? 0).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: (sale['profit'] as num? ?? 0) >= 0
                              ? AppColors.success.withValues(alpha: 0.8)
                              : AppColors.error,
                        ),
                      ),
                      if ((sale['balance_due'] as num? ?? 0) > 0)
                        Text(
                          'Due: ${ShopSettings.currency}${(sale['balance_due'] as num).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileSaleRowCard extends StatelessWidget {
  final Map<String, dynamic> sale;
  final VoidCallback onTap;
  final String paymentType;
  final bool isRefund;
  final bool isServiceSale;
  final String saleTypeLabel;
  final String serviceNames;
  final String dateStr;
  final String refundState;
  final Color badgeColor;
  final String badgeLabel;

  const _MobileSaleRowCard({
    required this.sale,
    required this.onTap,
    required this.paymentType,
    required this.isRefund,
    required this.isServiceSale,
    required this.saleTypeLabel,
    required this.serviceNames,
    required this.dateStr,
    required this.refundState,
    required this.badgeColor,
    required this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final total = (sale['total_amount'] as num? ?? 0).toDouble();
    final profit = (sale['profit'] as num? ?? 0).toDouble();
    final balanceDue = (sale['balance_due'] as num? ?? 0).toDouble();
    final customerName = (sale['customer_name'] as String?)?.trim() ?? '';
    final typeColor = isRefund
        ? AppColors.error
        : isServiceSale
        ? Theme.of(context).colorScheme.secondary
        : AppColors.success;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isRefund
                          ? Icons.assignment_return
                          : isServiceSale
                          ? Icons.design_services_rounded
                          : Icons.receipt_long,
                      color: typeColor,
                      size: 21,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serviceNames.isNotEmpty
                              ? serviceNames
                              : 'Sale #${(sale['id'] as String).substring(0, 8)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          saleTypeLabel,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: isRefund ? AppColors.error : AppColors.success,
                        ),
                      ),
                      SizedBox(height: 5),
                      _SaleBadge(label: badgeLabel, color: badgeColor),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SaleInfoChip(
                    icon: Icons.schedule_outlined,
                    label: dateStr.isEmpty ? 'No date' : dateStr,
                  ),
                  _SaleInfoChip(
                    icon: Icons.trending_up,
                    label:
                        'Profit ${ShopSettings.currency}${profit.toStringAsFixed(2)}',
                    color: profit >= 0 ? AppColors.success : AppColors.error,
                  ),
                  if (balanceDue > 0)
                    _SaleInfoChip(
                      icon: Icons.warning_amber_outlined,
                      label:
                          'Due ${ShopSettings.currency}${balanceDue.toStringAsFixed(2)}',
                      color: AppColors.warning,
                    ),
                  if (customerName.isNotEmpty)
                    _SaleInfoChip(
                      icon: Icons.person_outline,
                      label: customerName,
                    ),
                  if (refundState.isNotEmpty)
                    _SaleInfoChip(
                      icon: Icons.assignment_return_outlined,
                      label: refundState,
                      color: AppColors.error,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SaleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SaleInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _SaleInfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: isSelected ? AppColors.primary : context.appSurfaceHighlight,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w500, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
