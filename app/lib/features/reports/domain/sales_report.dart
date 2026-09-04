import '../../sell/domain/cart_line.dart';
import '../../sell/domain/sale.dart';

enum ReportRange { today, week, month }

/// One day's total, for the 7-bar trend chart. [day] is normalized to
/// midnight.
class DailyTotal {
  final DateTime day;
  final int total;

  const DailyTotal({required this.day, required this.total});
}

class ProductTypeTotals {
  final int gas;

  /// Everything that isn't gas, summed together — the catalog's
  /// categories are owner-defined and unbounded now, so there's no
  /// fixed "cylinders vs accessories" split to report separately
  /// anymore; see the owner-managed-catalog feature.
  final int products;

  const ProductTypeTotals({this.gas = 0, this.products = 0});

  int get grandTotal => gas + products;
}

class SalesReport {
  final int totalForRange;
  final ProductTypeTotals breakdown;

  /// Always exactly 7 entries, oldest to newest, ending on [now]'s day —
  /// independent of [ReportRange]: the trend chart is always a 7-day
  /// window regardless of which range is selected for the headline total.
  final List<DailyTotal> last7Days;

  const SalesReport({
    required this.totalForRange,
    required this.breakdown,
    required this.last7Days,
  });
}

bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

bool _inRange(DateTime saleTime, ReportRange range, DateTime now) {
  switch (range) {
    case ReportRange.today:
      return _isSameDay(saleTime, now);
    case ReportRange.week:
      final start = _startOfDay(now).subtract(const Duration(days: 6));
      return !saleTime.isBefore(start);
    case ReportRange.month:
      final start = _startOfDay(now).subtract(const Duration(days: 29));
      return !saleTime.isBefore(start);
  }
}

/// Pure aggregation over an already-fetched sales list — the same list
/// Reports and Home both read from (SalesRepository), never recomputed
/// from anything else.
SalesReport buildSalesReport(List<Sale> sales, {required ReportRange range, required DateTime now}) {
  final inRange = sales.where((sale) => _inRange(sale.createdAt, range, now)).toList();
  final totalForRange = inRange.fold(0, (sum, sale) => sum + sale.total);

  var gas = 0;
  var products = 0;
  for (final sale in inRange) {
    for (final line in sale.items) {
      switch (line) {
        case GasCartLine():
          gas += line.lineTotal;
        case ProductCartLine():
          products += line.lineTotal;
      }
    }
  }

  final last7Days = <DailyTotal>[
    for (var i = 6; i >= 0; i--)
      DailyTotal(
        day: _startOfDay(now).subtract(Duration(days: i)),
        total: sales
            .where((sale) => _isSameDay(sale.createdAt, _startOfDay(now).subtract(Duration(days: i))))
            .fold(0, (sum, sale) => sum + sale.total),
      ),
  ];

  return SalesReport(
    totalForRange: totalForRange,
    breakdown: ProductTypeTotals(gas: gas, products: products),
    last7Days: last7Days,
  );
}
