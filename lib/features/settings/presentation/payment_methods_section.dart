import 'package:flutter/material.dart';
import '../../../core/theme/app_theme_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pos_app/core/services/pos_payment_service.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/core/utils/error_messages.dart';
import '../data/payment_method_provider.dart';
import '../data/payment_method_repository.dart';

class PaymentMethodsSection extends ConsumerStatefulWidget {
  const PaymentMethodsSection({super.key});

  @override
  ConsumerState<PaymentMethodsSection> createState() =>
      _PaymentMethodsSectionState();
}

class _PaymentMethodsSectionState extends ConsumerState<PaymentMethodsSection> {
  final _mpesaDisplayNameController = TextEditingController(text: 'M-Pesa');
  final _mpesaShortcodeController = TextEditingController();
  final _mpesaAccountReferenceController = TextEditingController();
  final _mpesaConsumerKeyController = TextEditingController();
  final _mpesaConsumerSecretController = TextEditingController();
  final _mpesaPasskeyController = TextEditingController();

  bool _mpesaActive = false;
  bool _loadingMpesa = true;
  bool _savingMpesa = false;
  bool _configuringMpesa = false;
  String _mpesaTransactionType = 'CustomerPayBillOnline';
  String _mpesaMessage = '';

  bool _testingConnection = false;
  Map<String, dynamic>? _connectionResult;

  @override
  void initState() {
    super.initState();
    _loadMpesaSettings();
  }

  @override
  void dispose() {
    _mpesaDisplayNameController.dispose();
    _mpesaShortcodeController.dispose();
    _mpesaAccountReferenceController.dispose();
    _mpesaConsumerKeyController.dispose();
    _mpesaConsumerSecretController.dispose();
    _mpesaPasskeyController.dispose();
    super.dispose();
  }

  Future<void> _loadMpesaSettings() async {
    setState(() {
      _loadingMpesa = true;
      _mpesaMessage = '';
    });
    try {
      final settings = await PosPaymentService.fetchBusinessMpesaSettings();
      final publicConfig = settings.publicConfig;
      final secretConfig = settings.secretConfig;
      if (!mounted) return;
      setState(() {
        _mpesaActive = settings.isActive;
        _mpesaDisplayNameController.text = settings.displayName;
        _mpesaShortcodeController.text =
            publicConfig['shortcode']?.toString() ?? '';
        _mpesaTransactionType =
            publicConfig['transactionType']?.toString() ??
            'CustomerPayBillOnline';
        _mpesaAccountReferenceController.text =
            publicConfig['accountReference']?.toString() ?? '';
        _mpesaConsumerKeyController.text =
            secretConfig['consumerKey']?.toString() ?? '';
        _mpesaConsumerSecretController.text =
            secretConfig['consumerSecret']?.toString() ?? '';
        _mpesaPasskeyController.text =
            secretConfig['passkey']?.toString() ?? '';
        _loadingMpesa = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMpesa = false;
        _mpesaMessage = AppErrorMessage.withContext(
          error,
          prefix: 'M-Pesa settings unavailable.',
          fallback: AppErrorMessage.loadFailed,
        );
      });
    }
  }

  Future<void> _saveMpesaSettings() async {
    if (_mpesaActive) {
      final missing = <String>[];
      if (_mpesaShortcodeController.text.trim().isEmpty) {
        missing.add('Till or PayBill number');
      }
      if (_mpesaConsumerKeyController.text.trim().isEmpty) {
        missing.add('consumer key');
      }
      if (_mpesaConsumerSecretController.text.trim().isEmpty) {
        missing.add('consumer secret');
      }
      if (_mpesaPasskeyController.text.trim().isEmpty) {
        missing.add('passkey');
      }
      if (missing.isNotEmpty) {
        setState(() {
          _mpesaMessage =
              'Complete M-Pesa settings before enabling: ${missing.join(', ')}.';
        });
        return;
      }
    }

    setState(() {
      _savingMpesa = true;
      _mpesaMessage = '';
    });
    try {
      final settings = await PosPaymentService.saveBusinessMpesaSettings(
        isActive: _mpesaActive,
        displayName: _mpesaDisplayNameController.text,
        shortcode: _mpesaShortcodeController.text,
        transactionType: _mpesaTransactionType,
        accountReference: _mpesaAccountReferenceController.text,
        consumerKey: _mpesaConsumerKeyController.text,
        consumerSecret: _mpesaConsumerSecretController.text,
        passkey: _mpesaPasskeyController.text,
      );
      if (!mounted) return;
      setState(() {
        _mpesaActive = settings.isActive;
        _mpesaConsumerKeyController.text =
            settings.secretConfig['consumerKey']?.toString() ?? '';
        _mpesaConsumerSecretController.text =
            settings.secretConfig['consumerSecret']?.toString() ?? '';
        _mpesaPasskeyController.text =
            settings.secretConfig['passkey']?.toString() ?? '';
        _mpesaMessage = 'M-Pesa collection saved';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _mpesaMessage = AppErrorMessage.withContext(
          error,
          prefix: 'M-Pesa save failed.',
          fallback: AppErrorMessage.saveFailed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingMpesa = false);
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionResult = null;
    });
    try {
      final result = await PosPaymentService.testMpesaConnection();
      if (!mounted) return;
      setState(() {
        _connectionResult = result;
        _testingConnection = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testingConnection = false;
        _connectionResult = {
          'success': false,
          'message': AppErrorMessage.withContext(
            error,
            prefix: '',
            fallback: 'Connection test failed.',
          ),
        };
      });
    }
  }

  Future<void> _showAddPaymentMethodDialog([
    Map<String, dynamic>? existing,
  ]) async {
    final isEditing = existing != null;
    final nameController = TextEditingController(
      text: isEditing ? existing['name'] : '',
    );
    bool isCashDrawer = isEditing ? (existing['is_cash_drawer'] == 1) : false;
    bool isCredit = isEditing ? (existing['is_credit'] == 1) : false;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(isEditing ? 'Edit Payment Method' : 'Add Payment Method'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. M-Pesa, Card, Bank Transfer',
                  ),
                ),
                SizedBox(height: 16),
                SwitchListTile(
                  title: Text('Affects Cash Drawer'),
                  subtitle: Text(
                    'Check this if this payment method represents physical cash going into the till.',
                  ),
                  value: isCashDrawer,
                  onChanged: (val) => setDialogState(() {
                    isCashDrawer = val;
                    if (val) isCredit = false;
                  }),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: Text('Credit Payment (Kopesha)'),
                  subtitle: Text(
                    'Check this for credit sales that require customer assignment and due dates.',
                  ),
                  value: isCredit,
                  onChanged: (val) => setDialogState(() {
                    isCredit = val;
                    if (val) {
                      isCashDrawer = false;
                    }
                  }),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        if (isEditing) {
                          await PaymentMethodRepository.update(
                            existing['id'],
                            name: nameController.text.trim(),
                            isCashDrawer: isCashDrawer,
                            isCredit: isCredit,
                            isActive: existing['is_active'] == 1,
                            sortOrder: existing['sort_order'],
                          );
                        } else {
                          await PaymentMethodRepository.create(
                            name: nameController.text.trim(),
                            isCashDrawer: isCashDrawer,
                            isCredit: isCredit,
                          );
                        }
                        if (context.mounted) Navigator.pop(ctx, true);
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
                        setDialogState(() => saving = false);
                      }
                    },
              child: saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isEditing ? 'Save' : 'Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ref.invalidate(paymentMethodsProvider);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> method, bool isActive) async {
    try {
      await PaymentMethodRepository.update(
        method['id'],
        name: method['name'],
        isCashDrawer: method['is_cash_drawer'] == 1,
        isCredit: method['is_credit'] == 1,
        isActive: isActive,
        sortOrder: method['sort_order'],
      );
      ref.invalidate(paymentMethodsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteMethod(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Payment Method?'),
        content: Text(
          'Are you sure you want to delete this payment method? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await PaymentMethodRepository.delete(id);
        ref.invalidate(paymentMethodsProvider);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppErrorMessage.from(
                e,
                fallback: 'Could not delete this payment method. Please try again.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Color _cardBackground() =>
      context.isDarkMode ? AppColors.darkSurface : AppColors.surface;

  Color _inputBackground() =>
      context.isDarkMode ? AppColors.darkBackground : AppColors.surfaceHighlight;

  Color _cardBorder() =>
      context.isDarkMode ? AppColors.darkBorder : AppColors.border;

  Color _textPrimary() =>
      context.isDarkMode ? AppColors.darkTextPrimary : AppColors.textPrimary;

  Color _textSecondary() =>
      context.isDarkMode ? AppColors.darkTextSecondary : AppColors.textSecondary;

  Color _textMuted() =>
      context.isDarkMode ? AppColors.darkTextMuted : AppColors.textSecondary;

  Color _accentColor() =>
      context.isDarkMode ? AppColors.darkAccent : AppColors.primary;

  Color _successColor() =>
      context.isDarkMode ? const Color(0xFF10B981) : AppColors.success;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          if (_configuringMpesa)
            _buildMpesaConfigurationView()
          else
            _buildPaymentGatewaySelection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final inConfig = _configuringMpesa;
    return Row(
      children: [
        if (inConfig)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () => setState(() => _configuringMpesa = false),
              icon: Icon(Icons.arrow_back, color: _textSecondary(), size: 20),
              tooltip: 'Back',
              splashRadius: 20,
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inConfig ? 'Configure M-Pesa Payment' : 'Payments',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure how customers pay your business.',
                style: TextStyle(
                  fontSize: 14,
                  color: _textSecondary(),
                ),
              ),
            ],
          ),
        ),
        if (!inConfig)
          OutlinedButton.icon(
            onPressed: () => _showAddPaymentMethodDialog(),
            icon: Icon(Icons.add, size: 18),
            label: Text('Add Method'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _cardBorder()),
              foregroundColor: _textPrimary(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentGatewaySelection() {
    if (_loadingMpesa) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGatewayGrid(),
        const SizedBox(height: 20),
        _buildCustomMethodsList(),
      ],
    );
  }

  Widget _buildGatewayGrid() {
    final gateways = [
      _Gateway(
        id: 'mpesa',
        name: 'M-Pesa',
        subtitle: 'Business Collection',
        icon: Icons.phone_android_outlined,
        active: _mpesaActive,
        configAvailable: true,
      ),
      _Gateway(
        id: 'stripe',
        name: 'Stripe',
        subtitle: 'Online Payments',
        icon: Icons.credit_card_outlined,
        active: false,
      ),
      _Gateway(
        id: 'paypal',
        name: 'PayPal',
        subtitle: 'Digital Payments',
        icon: Icons.account_balance_wallet_outlined,
        active: false,
      ),
      _Gateway(
        id: 'bank',
        name: 'Bank Transfer',
        subtitle: 'Direct Deposit',
        icon: Icons.account_balance_outlined,
        active: false,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 700 ? 2 : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.6,
          children: gateways.map((g) => _buildGatewayCard(g)).toList(),
        );
      },
    );
  }

  Widget _buildGatewayCard(_Gateway gateway) {
    final isMpesa = gateway.id == 'mpesa';

    return Container(
      decoration: BoxDecoration(
        color: _cardBackground(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: gateway.active
              ? _accentColor().withValues(alpha: 0.5)
              : _cardBorder(),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: gateway.active
                  ? _accentColor().withValues(alpha: 0.12)
                  : _cardBorder().withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              gateway.icon,
              size: 20,
              color: gateway.active ? _accentColor() : _textSecondary(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  gateway.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary(),
                  ),
                ),
                Text(
                  gateway.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: _textSecondary(),
                  ),
                ),
              ],
            ),
          ),
          if (isMpesa)
            TextButton(
              onPressed: () => setState(() => _configuringMpesa = true),
              style: TextButton.styleFrom(
                foregroundColor: _accentColor(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                gateway.active ? 'Configure' : 'Enable',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          else
            TextButton(
              onPressed: null,
              style: TextButton.styleFrom(
                foregroundColor: _textMuted(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Enable'),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomMethodsList() {
    final paymentMethodsAsync = ref.watch(paymentMethodsProvider);

    return paymentMethodsAsync.when(
      data: (methods) {
        if (methods.isEmpty) return const SizedBox.shrink();
        return _buildSectionCard(
          title: 'Custom Payment Methods',
          child: Column(
            children: methods.map((method) {
              final isActive = method['is_active'] == 1;
              final isCashDrawer = method['is_cash_drawer'] == 1;
              final isCredit = method['is_credit'] == 1;

              String subtitle = 'Digital/External payment';
              if (isCashDrawer) {
                subtitle = 'Affects cash drawer';
              } else if (isCredit) {
                subtitle = 'Credit payment (Kopesha)';
              }

              final isLast = methods.last == method;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                method['name'],
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isActive
                                      ? _textPrimary()
                                      : _textSecondary(),
                                ),
                              ),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _textSecondary(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isActive,
                          onChanged: (val) => _toggleActive(method, val),
                          activeThumbColor: _accentColor(),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit_outlined,
                              size: 18, color: _textSecondary()),
                          onPressed: () =>
                              _showAddPaymentMethodDialog(method),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.error,
                          ),
                          onPressed: () => _deleteMethod(method['id']),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: _cardBorder().withValues(alpha: 0.4),
                    ),
                ],
              );
            }).toList(),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => _buildErrorCard(err),
    );
  }

  Widget _buildMpesaConfigurationView() {
    if (_loadingMpesa) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMpesaHeaderCard(),
        if (_mpesaMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildMessageBanner(),
        ],
        const SizedBox(height: 12),
        _buildBusinessDetailsSection(),
        const SizedBox(height: 12),
        _buildReceiptSettingsSection(),
        const SizedBox(height: 12),
        _buildDeveloperCredentialsSection(),
        const SizedBox(height: 12),
        _buildStatusCard(),
        const SizedBox(height: 16),
        _buildConfigActionBar(),
      ],
    );
  }

  Widget _buildMpesaHeaderCard() {
    return _buildSectionCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _accentColor().withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.phone_android_outlined,
              color: _accentColor(),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'M-Pesa',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary(),
                  ),
                ),
                Text(
                  'Business Collection',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSecondary(),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                'Enable M-Pesa',
                style: TextStyle(
                  fontSize: 13,
                  color: _textSecondary(),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _mpesaActive,
                onChanged: _savingMpesa
                    ? null
                    : (value) => setState(() => _mpesaActive = value),
                activeThumbColor: _accentColor(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessDetailsSection() {
    return _buildSectionCard(
      title: 'Business Details',
      child: Column(
        children: [
          _buildInputField(
            label: 'Business Name',
            controller: _mpesaDisplayNameController,
            hint: 'M-Pesa',
          ),
          const SizedBox(height: 14),
          _buildInputField(
            label: 'Shortcode / Till Number',
            controller: _mpesaShortcodeController,
            hint: '123456',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 14),
          _buildDropdownField(
            label: 'Type',
            value: _mpesaTransactionType,
            items: const [
              DropdownMenuItem(
                value: 'CustomerPayBillOnline',
                child: Text('PayBill'),
              ),
              DropdownMenuItem(
                value: 'CustomerBuyGoodsOnline',
                child: Text('Buy Goods'),
              ),
            ],
            onChanged: _savingMpesa
                ? null
                : (value) => setState(
                    () => _mpesaTransactionType =
                        value ?? 'CustomerPayBillOnline',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptSettingsSection() {
    return _buildSectionCard(
      title: 'Customer Receipt Settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputField(
            label: 'Reference',
            controller: _mpesaAccountReferenceController,
            hint: 'TASKIUM SHOP',
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Send SMS',
              style: TextStyle(fontSize: 14, color: _textPrimary()),
            ),
            subtitle: Text(
              'Send receipt via SMS after payment',
              style: TextStyle(fontSize: 12, color: _textSecondary()),
            ),
            value: _mpesaActive,
            onChanged: _savingMpesa
                ? null
                : (value) => setState(() => _mpesaActive = value),
            activeTrackColor: _accentColor(),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperCredentialsSection() {
    return _buildSectionCard(
      title: 'API Credentials',
      child: Column(
        children: [
          _buildInputField(
            label: 'Consumer Key',
            controller: _mpesaConsumerKeyController,
            hint: 'Enter consumer key',
            obscure: true,
          ),
          const SizedBox(height: 14),
          _buildInputField(
            label: 'Consumer Secret',
            controller: _mpesaConsumerSecretController,
            hint: 'Enter consumer secret',
            obscure: true,
          ),
          const SizedBox(height: 14),
          _buildInputField(
            label: 'Passkey',
            controller: _mpesaPasskeyController,
            hint: 'Enter passkey',
            obscure: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final connected = _connectionResult != null &&
        _connectionResult!['success'] == true;
    final failed = _connectionResult != null &&
        _connectionResult!['success'] != true;

    return _buildSectionCard(
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _testingConnection
                  ? Colors.amber
                  : connected
                      ? _successColor()
                      : failed
                          ? AppColors.error
                          : _textMuted(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _testingConnection
                  ? 'Testing connection...'
                  : connected
                      ? 'Connection active'
                      : failed
                          ? 'Connection failed'
                          : 'Connection not verified',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _testingConnection
                    ? Colors.amber
                    : connected
                        ? _successColor()
                        : failed
                            ? AppColors.error
                            : _textMuted(),
              ),
            ),
          ),
          if (failed)
            Expanded(
              child: Text(
                _connectionResult!['message']?.toString() ?? '',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.error,
                ),
                textAlign: TextAlign.end,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _mpesaMessage.contains('saved')
            ? _successColor().withValues(alpha: 0.08)
            : AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _mpesaMessage.contains('saved')
              ? _successColor().withValues(alpha: 0.3)
              : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        _mpesaMessage,
        style: TextStyle(
          fontSize: 12,
          color: _mpesaMessage.contains('saved')
              ? _successColor()
              : AppColors.error,
        ),
      ),
    );
  }

  Widget _buildConfigActionBar() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _testingConnection ? null : _testConnection,
          icon: _testingConnection
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _textSecondary(),
                  ),
                )
              : Icon(Icons.wifi_find_outlined, size: 18),
          label: Text(_testingConnection ? 'Testing...' : 'Test Connection'),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: _cardBorder()),
            foregroundColor: _textSecondary(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: _savingMpesa
              ? null
              : () => setState(() => _configuringMpesa = false),
          style: TextButton.styleFrom(foregroundColor: _textSecondary()),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _savingMpesa ? null : _saveMpesaSettings,
          icon: _savingMpesa
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(Icons.check, size: 18),
          label: Text(_savingMpesa ? 'Saving...' : 'Save Configuration'),
          style: FilledButton.styleFrom(
            backgroundColor: _accentColor(),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    String? title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBackground(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder()),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary(),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textSecondary(),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _inputBackground(),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _cardBorder().withValues(alpha: 0.5),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            style: TextStyle(fontSize: 14, color: _textPrimary()),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: _textSecondary().withValues(alpha: 0.5),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              suffixIcon: obscure
                  ? Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: _textSecondary(),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    void Function(String?)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textSecondary(),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _inputBackground(),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _cardBorder().withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonFormField<String>(
            initialValue: value,
            items: items,
            onChanged: onChanged,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            dropdownColor: _cardBackground(),
            style: TextStyle(fontSize: 14, color: _textPrimary()),
            icon: Icon(Icons.keyboard_arrow_down, color: _textSecondary()),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(Object err) {
    return _buildSectionCard(
      child: Text(
        AppErrorMessage.from(err, fallback: AppErrorMessage.loadFailed),
        style: TextStyle(color: AppColors.error),
      ),
    );
  }
}

class _Gateway {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final bool active;
  final bool configAvailable;

  const _Gateway({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    this.active = false,
    this.configAvailable = false,
  });
}
