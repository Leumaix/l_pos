import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../auth/application/auth_providers.dart';
import '../../customers/application/customer_providers.dart';
import '../../customers/domain/customer_totals.dart';
import '../../reports/domain/sales_report.dart';
import '../../sell/application/inventory_providers.dart';
import '../../sell/application/sales_providers.dart';
import '../../sell/domain/sale.dart';

/// Home's dashboard figures, composed directly from the same repositories
/// Sell, Stock, Customers, and Reports all read from — never a separate
/// hardcoded snapshot that could quietly drift out of sync with what
/// those screens actually show (e.g. after a real restock or sale).
class DashboardSummary {
  final int todaysSalesTotalNaira;
  final double gasRemainingKg;
  final int amountOwedByCustomersNaira;

  const DashboardSummary({
    required this.todaysSalesTotalNaira,
    required this.gasRemainingKg,
    required this.amountOwedByCustomersNaira,
  });
}

final dashboardSummaryProvider = Provider<AsyncValue<DashboardSummary>>((ref) {
  // /sales reads are owner-only at the rules level (see firestore.rules)
  // — an attendant subscribing to salesProvider at all would just spin
  // forever on a permission-denied error. Their Home never shows
  // today's-sales anyway (see home_screen.dart's owner/attendant
  // split), so skip the subscription entirely rather than let it fail.
  final isOwner = ref.watch(authStateProvider).valueOrNull?.role == 'owner';
  final gasStockAsync = ref.watch(gasStockProvider);
  final salesAsync = isOwner ? ref.watch(salesProvider) : const AsyncData<List<Sale>>([]);
  final customersAsync = ref.watch(customersProvider);
  final rate = ref.watch(gasRateProvider);

  for (final async in [gasStockAsync, salesAsync, customersAsync]) {
    if (async.hasError) return AsyncError(async.error!, async.stackTrace!);
  }

  final gasStock = gasStockAsync.valueOrNull;
  final sales = salesAsync.valueOrNull;
  final customers = customersAsync.valueOrNull;
  if (gasStock == null || sales == null || customers == null) {
    return const AsyncLoading();
  }

  // Same pure aggregation Reports uses for its "Today" total.
  final todaysTotal = buildSalesReport(
    sales,
    range: ReportRange.today,
    now: DateTime.now(),
  ).totalForRange;

  return AsyncData(
    DashboardSummary(
      todaysSalesTotalNaira: todaysTotal,
      gasRemainingKg: kgRemaining(gasStock, rate), // same call Stock's gauge makes
      amountOwedByCustomersNaira: totalOwedByCustomers(customers), // same helper Customers/Reports use
    ),
  );
});
