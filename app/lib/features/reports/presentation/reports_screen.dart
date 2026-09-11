import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/stock_thresholds.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/stat_card.dart';
import '../../business/application/business_providers.dart';
import '../../customers/application/customer_providers.dart';
import '../../customers/domain/customer_totals.dart';
import '../../expenses/application/expense_providers.dart';
import '../../expenses/domain/expenses_report.dart';
import '../../gifts/application/gift_providers.dart';
import '../../gifts/domain/gifts_report.dart';
import '../../sell/application/inventory_providers.dart';
import '../../sell/application/sales_providers.dart';
import '../../shift/application/shift_providers.dart';
import '../../shift/domain/shift.dart';
import '../domain/sales_report.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportRange _range = ReportRange.today;

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesProvider);
    final customersAsync = ref.watch(customersProvider);
    final gasStockAsync = ref.watch(gasStockProvider);
    final rate = ref.watch(gasRateProvider);
    final capacityKg = ref.watch(gasTankCapacityKgProvider);
    final productsAsync = ref.watch(productsProvider);
    final shiftHistoryAsync = ref.watch(shiftHistoryProvider);
    final isDesktop = Breakpoints.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Reports', style: AppTextStyles.headingSm),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ResponsiveCenter(
            maxWidth: 640,
            desktopMaxWidth: 960,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final r in ReportRange.values) ...[
                      _RangeChip(
                        label: switch (r) {
                          ReportRange.today => 'Today',
                          ReportRange.week => 'Week',
                          ReportRange.month => 'Month',
                        },
                        selected: _range == r,
                        onTap: () => setState(() => _range = r),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                // Desktop: a real multi-panel dashboard (stat tiles up top,
                // grid panels below) instead of the narrow/tablet single
                // column below — that column is otherwise untouched, so
                // this is purely additive, not a reorganization of it.
                if (isDesktop)
                  _buildDesktopDashboard()
                else ...[
                  salesAsync.when(
                    data: (sales) {
                      final report = buildSalesReport(
                        sales,
                        range: _range,
                        now: DateTime.now(),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  switch (_range) {
                                    ReportRange.today => "Today's sales",
                                    ReportRange.week => 'This week\'s sales',
                                    ReportRange.month => 'This month\'s sales',
                                  },
                                  style: AppTextStyles.secondary(
                                    AppTextStyles.bodySm,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  formatNaira(report.totalForRange),
                                  style: AppTextStyles.numericXl,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text('Last 7 days', style: AppTextStyles.headingSm),
                          const SizedBox(height: AppSpacing.md),
                          AppCard(child: _DailyChart(days: report.last7Days)),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'By product type',
                            style: AppTextStyles.headingSm,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppCard(
                            child: Column(
                              children: [
                                _BreakdownRow(
                                  label: 'Gas',
                                  value: report.breakdown.gas,
                                ),
                                _BreakdownRow(
                                  label: 'Products',
                                  value: report.breakdown.products,
                                  isLast: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    error: (err, _) => Text(
                      'Could not load sales',
                      style: AppTextStyles.danger(AppTextStyles.bodyMd),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ExpensesAndNetSection(range: _range),
                  const SizedBox(height: AppSpacing.lg),
                  _GiftsSection(range: _range),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Stock snapshot', style: AppTextStyles.headingSm),
                  const SizedBox(height: AppSpacing.md),
                  gasStockAsync.when(
                    data: (gasStock) {
                      // Same source Stock's own gauge reads — kgRemaining is
                      // never recomputed independently here.
                      final kg = kgRemaining(gasStock, rate);
                      final fraction = (kg / capacityKg).clamp(0.0, 1.0);
                      return AppCard(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Gas remaining',
                              style: AppTextStyles.secondary(
                                AppTextStyles.bodyMd,
                              ),
                            ),
                            Text(
                              '${formatKg(kg)} (${(fraction * 100).round()}%)',
                              style: AppTextStyles.numericSm,
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (err, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  productsAsync.when(
                    data: (products) {
                      final lowStockCount = products
                          .where((p) => p.stockCount <= kLowStockThreshold)
                          .length;
                      return AppCard(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Low-stock items',
                              style: AppTextStyles.secondary(
                                AppTextStyles.bodyMd,
                              ),
                            ),
                            Text(
                              '$lowStockCount',
                              style: lowStockCount > 0
                                  ? AppTextStyles.danger(
                                      AppTextStyles.numericSm,
                                    )
                                  : AppTextStyles.numericSm,
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (err, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  customersAsync.when(
                    data: (customers) => Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.cardRadius,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Debtors outstanding',
                            style: AppTextStyles.secondary(
                              AppTextStyles.bodySm,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            // Same shared helper Home and the Customers list
                            // banner both call — never summed separately here.
                            formatNaira(totalOwedByCustomers(customers)),
                            style: AppTextStyles.numericXl.copyWith(
                              color: AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (err, _) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Shift history', style: AppTextStyles.headingSm),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Every closed business day — the cash float declared, per-method '
                    'totals, and how the counted drawer compared to what was expected.',
                    style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  shiftHistoryAsync.when(
                    data: (shifts) => shifts.isEmpty
                        ? Text(
                            'No shifts closed yet.',
                            style: AppTextStyles.secondary(
                              AppTextStyles.bodyMd,
                            ),
                          )
                        : Column(
                            children: [
                              for (final shift in shifts) ...[
                                _ShiftHistoryCard(shift: shift),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                            ],
                          ),
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                    error: (err, _) => Text(
                      'Could not load shift history',
                      style: AppTextStyles.danger(AppTextStyles.bodyMd),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop only: a real multi-panel dashboard — small stat tiles across
  /// the top, then the bigger panels (chart, breakdown, shift history) as
  /// grid panels below rather than stacked one on top of the other, like
  /// a real analytics dashboard rather than a wider version of the same
  /// single column. Re-watches the same providers the narrow column above
  /// already does (Riverpod returns the cached value; this is not a
  /// second, divergent read of anything) rather than threading five
  /// AsyncValue parameters through a separate widget class — same data,
  /// arranged differently.
  Widget _buildDesktopDashboard() {
    final salesAsync = ref.watch(salesProvider);
    final expensesAsync = ref.watch(expensesProvider);
    final giftsAsync = ref.watch(giftsProvider);
    final gasStockAsync = ref.watch(gasStockProvider);
    final rate = ref.watch(gasRateProvider);
    final productsAsync = ref.watch(productsProvider);
    final customersAsync = ref.watch(customersProvider);
    final shiftHistoryAsync = ref.watch(shiftHistoryProvider);

    final salesLabel = switch (_range) {
      ReportRange.today => "Today's sales",
      ReportRange.week => "This week's sales",
      ReportRange.month => "This month's sales",
    };
    // Computed once here, then reused by the stat tile, the chart, and
    // the breakdown panel below — same single source of truth as the
    // narrow column's own salesAsync.when() call, not three separate
    // re-derivations of the same range's totals.
    final sales = salesAsync.valueOrNull;
    final report = sales == null
        ? null
        : buildSalesReport(sales, range: _range, now: DateTime.now());
    final expenses = expensesAsync.valueOrNull;
    final expensesReport = expenses == null
        ? null
        : buildExpensesReport(expenses, range: _range, now: DateTime.now());
    final netForRange = (report == null || expensesReport == null)
        ? null
        : report.totalForRange - expensesReport.totalForRange;
    final gifts = giftsAsync.valueOrNull;
    final giftsReport = gifts == null
        ? null
        : buildGiftsReport(gifts, range: _range, now: DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatCard(
                  label: salesLabel,
                  value: report == null
                      ? '—'
                      : formatNaira(report.totalForRange),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  label: 'Expenses',
                  value: expensesReport == null
                      ? '—'
                      : formatNaira(expensesReport.totalForRange),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatCard(
                  label: 'Net',
                  value: netForRange == null ? '—' : formatNaira(netForRange),
                  valueColor: netForRange != null && netForRange < 0
                      ? AppColors.danger
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Never folded into Net above — a gift is never revenue,
              // shown separately by design (see gifts_report.dart's own
              // doc comment).
              Expanded(
                child: StatCard(
                  label: 'Given away',
                  value: giftsReport == null
                      ? '—'
                      : formatNaira(giftsReport.totalForRange),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: gasStockAsync.when(
                  data: (gasStock) => StatCard(
                    label: 'Gas remaining',
                    value: formatKg(kgRemaining(gasStock, rate)),
                    icon: Icons.local_fire_department_outlined,
                  ),
                  loading: () => const StatCard(
                    label: 'Gas remaining',
                    value: '—',
                    icon: Icons.local_fire_department_outlined,
                  ),
                  error: (err, _) => const StatCard(
                    label: 'Gas remaining',
                    value: '—',
                    icon: Icons.local_fire_department_outlined,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: productsAsync.when(
                  data: (products) {
                    final lowStockCount = products
                        .where((p) => p.stockCount <= kLowStockThreshold)
                        .length;
                    return StatCard(
                      label: 'Low-stock items',
                      value: '$lowStockCount',
                      valueColor: lowStockCount > 0 ? AppColors.danger : null,
                    );
                  },
                  loading: () =>
                      const StatCard(label: 'Low-stock items', value: '—'),
                  error: (err, _) =>
                      const StatCard(label: 'Low-stock items', value: '—'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: customersAsync.when(
                  data: (customers) => StatCard(
                    label: 'Debtors outstanding',
                    value: formatNaira(totalOwedByCustomers(customers)),
                    valueColor: AppColors.danger,
                  ),
                  loading: () =>
                      const StatCard(label: 'Debtors outstanding', value: '—'),
                  error: (err, _) =>
                      const StatCard(label: 'Debtors outstanding', value: '—'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Last 7 days', style: AppTextStyles.headingSm),
                  const SizedBox(height: AppSpacing.md),
                  if (report != null)
                    AppCard(child: _DailyChart(days: report.last7Days))
                  else if (salesAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  else
                    Text(
                      'Could not load sales',
                      style: AppTextStyles.danger(AppTextStyles.bodyMd),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('By product type', style: AppTextStyles.headingSm),
                  const SizedBox(height: AppSpacing.md),
                  if (report != null)
                    AppCard(
                      child: Column(
                        children: [
                          _BreakdownRow(
                            label: 'Gas',
                            value: report.breakdown.gas,
                          ),
                          _BreakdownRow(
                            label: 'Products',
                            value: report.breakdown.products,
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shift history', style: AppTextStyles.headingSm),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Every closed business day — the cash float declared, per-method '
                    'totals, and how the counted drawer compared to what was expected.',
                    style: AppTextStyles.secondary(AppTextStyles.bodyMd),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  shiftHistoryAsync.when(
                    data: (shifts) => shifts.isEmpty
                        ? Text(
                            'No shifts closed yet.',
                            style: AppTextStyles.secondary(
                              AppTextStyles.bodyMd,
                            ),
                          )
                        : Column(
                            children: [
                              for (final shift in shifts) ...[
                                _ShiftHistoryCard(shift: shift),
                                const SizedBox(height: AppSpacing.sm),
                              ],
                            ],
                          ),
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                    error: (err, _) => Text(
                      'Could not load shift history',
                      style: AppTextStyles.danger(AppTextStyles.bodyMd),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Additive alongside the existing sales card above — expenses total for
/// the same [range], plus a net (revenue − expenses) figure. Composes
/// two independent AsyncValues via .valueOrNull, same pattern the
/// desktop dashboard already uses for its own stat-tile row, rather than
/// nesting one .when() inside another.
class _ExpensesAndNetSection extends ConsumerWidget {
  final ReportRange range;

  const _ExpensesAndNetSection({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesProvider);
    final expensesAsync = ref.watch(expensesProvider);
    final sales = salesAsync.valueOrNull;
    final expenses = expensesAsync.valueOrNull;

    final salesReport = sales == null
        ? null
        : buildSalesReport(sales, range: range, now: DateTime.now());
    final expensesReport = expenses == null
        ? null
        : buildExpensesReport(expenses, range: range, now: DateTime.now());
    final netForRange = (salesReport == null || expensesReport == null)
        ? null
        : salesReport.totalForRange - expensesReport.totalForRange;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Expenses',
            value: expensesReport == null
                ? '—'
                : formatNaira(expensesReport.totalForRange),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatCard(
            label: 'Net',
            value: netForRange == null ? '—' : formatNaira(netForRange),
            valueColor: netForRange != null && netForRange < 0
                ? AppColors.danger
                : null,
          ),
        ),
      ],
    );
  }
}

/// Additive alongside the sales/expenses cards above — never folded into
/// Net (see gifts_report.dart's own doc comment: a gift is never
/// revenue). Same .valueOrNull composition pattern as
/// _ExpensesAndNetSection.
class _GiftsSection extends ConsumerWidget {
  final ReportRange range;

  const _GiftsSection({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final giftsAsync = ref.watch(giftsProvider);
    final gifts = giftsAsync.valueOrNull;
    final giftsReport = gifts == null
        ? null
        : buildGiftsReport(gifts, range: range, now: DateTime.now());

    return StatCard(
      label: 'Given away',
      value: giftsReport == null ? '—' : formatNaira(giftsReport.totalForRange),
    );
  }
}

class _ShiftHistoryCard extends StatelessWidget {
  final ClosedShift shift;

  const _ShiftHistoryCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final overOrShort = shift.varianceNaira != 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  DateFormat('MMM d, y · h:mm a').format(shift.closedAt),
                  style: AppTextStyles.bodyMd,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                formatVariance(shift.varianceNaira),
                style: overOrShort
                    ? AppTextStyles.danger(AppTextStyles.numericSm)
                    : AppTextStyles.success(AppTextStyles.numericSm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Opened by ${shift.openedByStaffName} · Closed by ${shift.closedByStaffName}',
            style: AppTextStyles.secondary(AppTextStyles.bodySm),
          ),
          const SizedBox(height: AppSpacing.sm),
          _BreakdownRow(label: 'Opening float', value: shift.openingFloatNaira),
          _BreakdownRow(label: 'Cash sales', value: shift.cashTotalNaira),
          _BreakdownRow(label: 'Cash expenses', value: shift.expenseTotalNaira),
          _BreakdownRow(label: 'Card sales', value: shift.cardTotalNaira),
          _BreakdownRow(
            label: 'Transfer sales',
            value: shift.transferTotalNaira,
          ),
          _BreakdownRow(
            label: 'Customer account sales',
            value: shift.creditTotalNaira,
          ),
          _BreakdownRow(
            label: 'Counted cash',
            value: shift.countedCashNaira,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentTintBg : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        child: Container(
          height: AppSpacing.minTouchTarget - 8,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelSm.copyWith(
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  final List<DailyTotal> days;

  const _DailyChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final maxValue = days.fold(0, (m, d) => d.total > m ? d.total : m);
    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;

    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: maxValue == 0
                          ? 4
                          : 8 + (day.total / maxValue) * 72,
                      decoration: BoxDecoration(
                        color: isToday(day.day)
                            ? AppColors.accent
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      DateFormat('E').format(day.day).substring(0, 1),
                      style: isToday(day.day)
                          ? AppTextStyles.accent(AppTextStyles.bodySm)
                          : AppTextStyles.muted(AppTextStyles.bodySm),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int value;
  final bool isLast;

  const _BreakdownRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyLg),
          Text(formatNaira(value), style: AppTextStyles.numericSm),
        ],
      ),
    );
  }
}
