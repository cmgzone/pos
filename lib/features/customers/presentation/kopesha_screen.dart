import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/features/app/app_shell.dart';

import '../../../core/services/messaging_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../data/customer_repository.dart';
import 'customer_account_screen.dart';
import 'customer_kopesha_detail_screen.dart';
import 'customer_message_dialog.dart';

// ── Shared Kopesha helpers (pure, reusable) ─────────────────────────────────

double kopeshaMoney(dynamic v) => (v as num?)?.toDouble() ?? 0;
int kopeshaCount(dynamic v) => (v as num?)?.toInt() ?? 0;

DateTime? _kopeshaDate(String? raw) =>
    raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);

bool _kopeshaIsPastDue(String? raw) {
  final d = _kopeshaDate(raw);
  if (d == null) return false;
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  return d.isBefore(today);
}

String kopeshaRisk(Map<String, dynamic> c) {
  final overdueCount = kopeshaCount(c['overdue_count']);
  final overdueAmount = kopeshaMoney(c['overdue_amount']);
  final outstanding = kopeshaMoney(c['outstanding_balance']);
  final oldest = _kopeshaDate(c['oldest_overdue_date'] as String?);
  final overdueDays = oldest == null ? 0 : DateTime.now().difference(oldest).inDays;
  if (overdueCount >= 2 ||
      overdueAmount >= 250 ||
      overdueDays >= 7 ||
      outstanding >= 750) {
    return 'High Risk';
  }
  if (overdueCount >= 1 ||
      kopeshaCount(c['due_today_count']) > 0 ||
      outstanding >= 250) {
    return 'Watch';
  }
  return 'Healthy';
}

/// Per-customer status used for the compact list tile badge.
String kopeshaStatus(Map<String, dynamic> c) {
  final overdue = kopeshaCount(c['overdue_count']);
  final dueToday = kopeshaCount(c['due_today_count']);
  if (overdue > 0) return 'Overdue';
  if (dueToday > 0) return 'Due Today';
  if (kopeshaRisk(c) == 'High Risk') return 'Risky';
  return 'Open';
}

Color kopeshaStatusColor(String status) {
  switch (status) {
    case 'Risky':
      return AppColors.error;
    case 'Due Today':
      return AppColors.primary;
    case 'Overdue':
      return AppColors.apricot;
    case 'Open':
    default:
      return AppColors.warning;
  }
}

String _initials(String? name) {
  final cleaned = (name ?? '').trim();
  if (cleaned.isEmpty) return '?';
  final parts = cleaned.split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

// ── Screen ──────────────────────────────────────────────────────────────────

class KopeshaScreen extends ConsumerStatefulWidget {
  const KopeshaScreen({super.key});

  @override
  ConsumerState<KopeshaScreen> createState() => _KopeshaScreenState();
}

class _KopeshaScreenState extends ConsumerState<KopeshaScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _filter = 'all';

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
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final rows = await CustomerRepository.getKopeshaCustomers(
        query: _searchController.text,
        filter: _filter,
      );
      if (!mounted) return;
      setState(() {
        _customers = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _onFilterChanged(String value) {
    if (value == _filter) return;
    _filter = value;
    _load();
  }

  void _onBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      AppShell.selectIndex(0);
    }
  }

  Future<void> _openCreateAccountScreen() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const CustomerAccountScreen()),
    );

    if (created == null || !mounted) return;

    _searchController.clear();
    _filter = 'all';
    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${created['name']} account created'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _openStatement(Map<String, dynamic> customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerKopeshaDetailScreen(customerId: customer['id'] as String),
      ),
    );

    if (!mounted) return;
    await _load();
  }

  Future<void> _messageCustomer(Map<String, dynamic> customer) async {
    final name = customer['name'] as String? ?? 'Customer';
    final phone = customer['phone'] as String? ?? '';
    final balance =
        '${ShopSettings.currency}${kopeshaMoney(customer['outstanding_balance']).toStringAsFixed(2)}';
    final message = MessagingService.balanceReminder(
      customerName: name,
      balance: balance,
      dueDate: customer['next_due_date'] as String?,
    );
    await CustomerMessageDialog.show(
      context,
      customerName: name,
      phoneNumber: phone,
      initialMessage: message,
      metadata: {'source': 'kopesha_list', 'customerId': customer['id']},
    );
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

    final outstanding = _customers.fold<double>(
      0.0,
      (sum, c) => sum + kopeshaMoney(c['outstanding_balance']),
    );
    final dueToday = _customers
        .where((c) => kopeshaCount(c['due_today_count']) > 0)
        .length;
    final overdue = _customers
        .where((c) => kopeshaCount(c['overdue_count']) > 0)
        .length;
    final risky =
        _customers.where((c) => kopeshaRisk(c) == 'High Risk').length;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      floatingActionButton: FloatingActionButton.small(
        onPressed: _openCreateAccountScreen,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'New Account',
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: SafeArea(
        child: Column(
          children: [
            KopeshaHeader(
              onBack: _onBack,
              onRefresh: _load,
              onNotifications: () => AppShell.showNotificationsSheet(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: KopeshaSearchBar(
                controller: _searchController,
                onChanged: (_) => _load(),
                onFilterTap: () {
                  // Equivalent to "All Open" — clears any active filter.
                  if (_filter != 'all') _onFilterChanged('all');
                },
                activeFilter: _filter,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: KopeshaFilterChips(
                selected: _filter,
                onChanged: _onFilterChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: CompactOutstandingCard(
                outstanding: outstanding,
                dueToday: dueToday,
                overdue: overdue,
                risky: risky,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Text(
                    'Customers (${_customers.length})',
                    style: TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Sorted by: Recent',
                    style: TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLight),
      );
    }
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: AppColors.darkTextMuted,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load Kopesha customers.',
                style: TextStyle(color: AppColors.darkTextSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_customers.isEmpty) {
      return KopeshaEmptyState(onCreate: _openCreateAccountScreen);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 88),
      itemCount: _customers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final c = _customers[index];
        final status = kopeshaStatus(c);
        final statusColor = kopeshaStatusColor(status);
        final phone = (c['phone'] as String? ?? '').trim();
        return KopeshaCustomerTile(
          customer: c,
          status: status,
          statusColor: statusColor,
          hasWhatsApp: phone.isNotEmpty,
          onTap: () => _openStatement(c),
          onWhatsApp: phone.isNotEmpty ? () => _messageCustomer(c) : null,
        );
      },
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

class KopeshaHeader extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onNotifications;

  const KopeshaHeader({
    super.key,
    required this.onBack,
    required this.onRefresh,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: const Border(
          bottom: BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.darkTextPrimary),
            onPressed: onBack,
            tooltip: 'Back',
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.handshake_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Kopesha',
            style: TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(
              Icons.notifications_none_outlined,
              color: AppColors.darkTextSecondary,
            ),
            onPressed: onNotifications,
            tooltip: 'Notifications',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.darkTextSecondary),
            onPressed: onRefresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

class KopeshaSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final String activeFilter;

  const KopeshaSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
    this.activeFilter = 'all',
  });

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.isNotEmpty;
    final filterActive = activeFilter != 'all';
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.darkTextPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search customers...',
        hintStyle: TextStyle(color: AppColors.darkTextMuted),
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primaryLight),
        ),
        prefixIcon: Icon(
          Icons.search,
          color: AppColors.darkTextMuted,
          size: 20,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasQuery)
              IconButton(
                icon: Icon(Icons.clear, color: AppColors.darkTextMuted, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
            Container(
              height: 22,
              width: 1,
              color: AppColors.darkBorder,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            IconButton(
              icon: Icon(
                Icons.tune,
                color: filterActive
                    ? AppColors.primaryLight
                    : AppColors.darkTextMuted,
                size: 20,
              ),
              onPressed: onFilterTap,
              tooltip: 'Filters',
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class KopeshaFilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const KopeshaFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const List<_FilterChipData> _filters = [
    _FilterChipData('All Open', 'all'),
    _FilterChipData('Due Today', 'due_today'),
    _FilterChipData('Overdue', 'overdue'),
    _FilterChipData('Risky', 'risky'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = _filters[index];
          final isSelected = selected == f.value;
          return InkWell(
            onTap: () => onChanged(f.value),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.darkBorder,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  f.label,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : AppColors.darkTextSecondary,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterChipData {
  final String label;
  final String value;
  const _FilterChipData(this.label, this.value);
}

class CompactOutstandingCard extends StatelessWidget {
  final double outstanding;
  final int dueToday;
  final int overdue;
  final int risky;

  const CompactOutstandingCard({
    super.key,
    required this.outstanding,
    required this.dueToday,
    required this.overdue,
    required this.risky,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder, width: 1),
      ),
      child: Row(
        children: [
          _Section(
            value: '${ShopSettings.currency}${outstanding.toStringAsFixed(0)}',
            label: 'Outstanding',
            color: AppColors.primaryLight,
            prominent: true,
            flex: 5,
          ),
          _Divider(),
          _Section(
            value: '$dueToday',
            label: 'Due Today',
            color: AppColors.primary,
            flex: 3,
          ),
          _Divider(),
          _Section(
            value: '$overdue',
            label: 'Overdue',
            color: AppColors.apricot,
            flex: 3,
          ),
          _Divider(),
          _Section(
            value: '$risky',
            label: 'Risky',
            color: AppColors.error,
            flex: 3,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool prominent;
  final int flex;

  const _Section({
    required this.value,
    required this.label,
    required this.color,
    this.prominent = false,
    this.flex = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: prominent ? 26 : 20,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      color: AppColors.darkBorder,
    );
  }
}

class KopeshaCustomerTile extends StatelessWidget {
  final Map<String, dynamic> customer;
  final String status;
  final Color statusColor;
  final bool hasWhatsApp;
  final VoidCallback onTap;
  final VoidCallback? onWhatsApp;

  const KopeshaCustomerTile({
    super.key,
    required this.customer,
    required this.status,
    required this.statusColor,
    required this.hasWhatsApp,
    required this.onTap,
    this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final name = customer['name'] as String? ?? 'Customer';
    final phone = (customer['phone'] as String? ?? '').trim();
    final outstanding = kopeshaMoney(customer['outstanding_balance']);
    final pastDue = _kopeshaIsPastDue(customer['next_due_date'] as String?);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: pastDue ? statusColor.withValues(alpha: 0.5) : AppColors.darkBorder,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _initials(name),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.darkTextPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (hasWhatsApp && onWhatsApp != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: InkWell(
                              onTap: onWhatsApp,
                              borderRadius: BorderRadius.circular(20),
                              child: Icon(
                                Icons.chat,
                                color: AppColors.success,
                                size: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      phone.isNotEmpty ? phone : 'No phone',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${ShopSettings.currency}${outstanding.toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.darkTextMuted,
                    size: 20,
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

class KopeshaEmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const KopeshaEmptyState({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              color: AppColors.darkTextMuted,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'No customers match this Kopesha filter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.darkTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try changing the filters or create a new account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
