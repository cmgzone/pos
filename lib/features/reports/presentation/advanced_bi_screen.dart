import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../app/app_shell.dart';
import '../data/bi_repository.dart';

class AdvancedBiScreen extends StatefulWidget {
  const AdvancedBiScreen({super.key});

  @override
  State<AdvancedBiScreen> createState() => _AdvancedBiScreenState();
}

class _AdvancedBiScreenState extends State<AdvancedBiScreen> {
  BiDashboardData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await BiRepository.loadDashboard();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      _error = data == null
          ? 'Connect to the cloud as a manager to load advanced analytics.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 800;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 54,
        leading: mobile
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BI Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('Growth, retention and workforce intelligence', style: TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _data == null
                ? _EmptyBiState(message: _error ?? 'No BI data is available yet.', onRetry: _load)
                : _BiDashboard(data: _data!),
      ),
    );
  }
}

class _BiDashboard extends StatelessWidget {
  final BiDashboardData data;

  const _BiDashboard({required this.data});

  static List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
      : const <Map<String, dynamic>>[];

  static double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  String _money(dynamic value) => NumberUtils.formatCompact(_number(value), isCurrency: true);

  @override
  Widget build(BuildContext context) {
    final forecastSummary = Map<String, dynamic>.from(data.forecast['summary'] as Map? ?? const {});
    final clvSummary = Map<String, dynamic>.from(data.clv['summary'] as Map? ?? const {});
    final turnoverSummary = Map<String, dynamic>.from(data.turnover['summary'] as Map? ?? const {});
    final history = _rows(data.forecast['history']);
    final forecast = _rows(data.forecast['forecast']);
    final customers = _rows(data.clv['customers']);
    final cohorts = _rows(data.cohorts['cohorts']);
    final turnover = _rows(data.turnover['turnover']);
    final trend = _number(forecastSummary['trendPerDay']);
    final monthOneRetention = cohorts
        .where((row) => _number(row['period_number']) == 1)
        .map((row) => _number(row['cohort_size']) == 0
            ? 0
            : _number(row['retained_customers']) / _number(row['cohort_size']) * 100)
        .fold<double>(0, (sum, value) => sum + value);
    final retentionCount = cohorts.where((row) => _number(row['period_number']) == 1).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 980;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _MetricCard(
                  width: horizontal ? (constraints.maxWidth - 36) / 4 : constraints.maxWidth,
                  icon: Icons.trending_up_rounded,
                  color: trend >= 0 ? AppColors.success : AppColors.error,
                  label: '30-day forecast',
                  value: _money(forecastSummary['forecastRevenue']),
                  detail: '${trend >= 0 ? '+' : ''}${_money(trend)} per day trend',
                ),
                _MetricCard(
                  width: horizontal ? (constraints.maxWidth - 36) / 4 : constraints.maxWidth,
                  icon: Icons.people_alt_outlined,
                  color: AppColors.fuchsia,
                  label: 'Average customer value',
                  value: _money(clvSummary['averageClv']),
                  detail: '${_number(clvSummary['customerCount']).toInt()} customers measured',
                ),
                _MetricCard(
                  width: horizontal ? (constraints.maxWidth - 36) / 4 : constraints.maxWidth,
                  icon: Icons.repeat_rounded,
                  color: AppColors.metricOrders,
                  label: 'Month-one retention',
                  value: '${retentionCount == 0 ? 0 : monthOneRetention / retentionCount.toDouble()}%',
                  detail: 'Customers returning after first month',
                ),
                _MetricCard(
                  width: horizontal ? (constraints.maxWidth - 36) / 4 : constraints.maxWidth,
                  icon: Icons.badge_outlined,
                  color: AppColors.metricStaff,
                  label: 'Current headcount',
                  value: '${_number(turnoverSummary['currentHeadcount']).toInt()}',
                  detail: '${_number(turnoverSummary['hires']).toInt()} hires · ${_number(turnoverSummary['departures']).toInt()} departures',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            _Panel(
              title: 'Sales forecast',
              subtitle: 'Daily actuals and linear-trend forecast from the last eight weeks.',
              child: SizedBox(
                height: 210,
                child: _ForecastChart(
                  actual: history.map((point) => _number(point['revenue'])).toList(),
                  projected: forecast.map((point) => _number(point['revenue'])).toList(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              children: [
                SizedBox(
                  width: horizontal ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth,
                  child: _Panel(
                    title: 'Highest-value customers',
                    subtitle: 'Lifetime revenue and purchase frequency.',
                    child: _RankedRows(
                      rows: customers.take(5).toList(),
                      title: (row) => row['customer_name']?.toString() ?? 'Customer',
                      value: (row) => '${_money(row['lifetime_value'])} · ${_number(row['transaction_count']).toInt()} orders',
                      color: AppColors.fuchsia,
                    ),
                  ),
                ),
                SizedBox(
                  width: horizontal ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth,
                  child: _Panel(
                    title: 'Cohort retention',
                    subtitle: 'Customers returning in their first month after purchase.',
                    child: _CohortBars(rows: cohorts),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Panel(
              title: 'Employee turnover',
              subtitle: 'Monthly hires, departures and ending team size.',
              child: _TurnoverRows(rows: turnover),
            ),
            const SizedBox(height: AppSpacing.lg),
            _Panel(
              title: 'Decision cues',
              subtitle: 'Signals distilled from the current dashboard.',
              child: Column(
                children: [
                  _InsightRow(
                    icon: trend >= 0 ? Icons.north_east_rounded : Icons.south_east_rounded,
                    color: trend >= 0 ? AppColors.success : AppColors.error,
                    text: trend >= 0
                        ? 'Sales are trending upward by about ${_money(trend)} per day.'
                        : 'Sales are softening by about ${_money(trend.abs())} per day.',
                  ),
                  _InsightRow(
                    icon: Icons.favorite_outline_rounded,
                    color: AppColors.fuchsia,
                    text: retentionCount == 0
                        ? 'More cohort history is needed before retention can be measured.'
                        : 'Average month-one retention is ${(monthOneRetention / retentionCount).toStringAsFixed(1)}%.',
                  ),
                  _InsightRow(
                    icon: Icons.groups_2_outlined,
                    color: AppColors.metricStaff,
                    text: '${_number(turnoverSummary['departures']).toInt()} recorded departures across the last 12 months.',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String detail;

  const _MetricCard({required this.width, required this.icon, required this.color, required this.label, required this.value, required this.detail});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(height: AppSpacing.md),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(detail, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _Panel({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.lg),
        child,
      ]),
    ),
  );
}

class _RankedRows extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String Function(Map<String, dynamic>) title;
  final String Function(Map<String, dynamic>) value;
  final Color color;
  const _RankedRows({required this.rows, required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _NoData();
    return Column(children: [
      for (var index = 0; index < rows.length; index++)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 15, backgroundColor: color.withValues(alpha: 0.14), child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w800))),
          title: Text(title(rows[index]), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(value(rows[index]), style: const TextStyle(fontSize: 11)),
        ),
    ]);
  }
}

class _CohortBars extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _CohortBars({required this.rows});

  @override
  Widget build(BuildContext context) {
    final monthOne = rows.where((row) => _number(row['period_number']) == 1).toList().reversed.take(5).toList().reversed.toList();
    if (monthOne.isEmpty) return const _NoData();
    return Column(children: [
      for (final row in monthOne) ...[
        Row(children: [
          SizedBox(width: 54, child: Text(row['cohort_month']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: (_number(row['retained_customers']) / math.max(1, _number(row['cohort_size']))).clamp(0, 1), minHeight: 10, color: AppColors.metricOrders, backgroundColor: AppColors.metricOrders.withValues(alpha: 0.12)))),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(width: 38, child: Text('${(_number(row['retained_customers']) / math.max(1, _number(row['cohort_size'])) * 100).toStringAsFixed(0)}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: AppSpacing.md),
      ],
    ]);
  }

  static double _number(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
}

class _TurnoverRows extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _TurnoverRows({required this.rows});
  static double _number(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _NoData();
    return Column(children: rows.reversed.take(6).toList().reversed.map((row) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(children: [
        SizedBox(width: 58, child: Text(row['month']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        Expanded(child: Text('${_number(row['hires']).toInt()} hired · ${_number(row['departures']).toInt()} left', style: const TextStyle(fontSize: 12))),
        Text('${_number(row['ending_headcount']).toInt()} staff', style: const TextStyle(fontSize: 12)),
      ]),
    )).toList());
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InsightRow({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
    ]),
  );
}

class _ForecastChart extends StatelessWidget {
  final List<double> actual;
  final List<double> projected;
  const _ForecastChart({required this.actual, required this.projected});
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ForecastPainter(actual: actual, projected: projected, actualColor: AppColors.primary, forecastColor: AppColors.fuchsia, gridColor: Theme.of(context).dividerColor),
    child: const SizedBox.expand(),
  );
}

class _ForecastPainter extends CustomPainter {
  final List<double> actual;
  final List<double> projected;
  final Color actualColor;
  final Color forecastColor;
  final Color gridColor;
  const _ForecastPainter({required this.actual, required this.projected, required this.actualColor, required this.forecastColor, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final values = [...actual, ...projected];
    if (values.isEmpty || size.isEmpty) return;
    final maxValue = math.max(1, values.reduce(math.max));
    final grid = Paint()..color = gridColor.withValues(alpha: 0.55)..strokeWidth = 1;
    for (var index = 1; index <= 3; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final total = math.max(1, values.length - 1);
    Offset point(int index, double value) => Offset(size.width * index / total, size.height - (value / maxValue * (size.height - 12)) - 6);
    final actualPath = Path();
    for (var index = 0; index < actual.length; index++) {
      final p = point(index, actual[index]);
      index == 0 ? actualPath.moveTo(p.dx, p.dy) : actualPath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(actualPath, Paint()..color = actualColor..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    if (projected.isNotEmpty) {
      final forecastPath = Path();
      final start = actual.isEmpty ? 0 : actual.length - 1;
      final anchor = actual.isEmpty ? projected.first : actual.last;
      forecastPath.moveTo(point(start, anchor).dx, point(start, anchor).dy);
      for (var index = 0; index < projected.length; index++) {
        final p = point(start + index + 1, projected[index]);
        forecastPath.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(forecastPath, Paint()..color = forecastColor..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _ForecastPainter old) => old.actual != actual || old.projected != projected || old.gridColor != gridColor;
}

class _NoData extends StatelessWidget {
  const _NoData();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Text('Not enough history yet.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}

class _EmptyBiState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _EmptyBiState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 150),
      Icon(Icons.query_stats_rounded, size: 54, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(height: AppSpacing.lg),
      Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl), child: Text(message, textAlign: TextAlign.center))),
      const SizedBox(height: AppSpacing.lg),
      Center(child: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again'))),
    ],
  );
}
