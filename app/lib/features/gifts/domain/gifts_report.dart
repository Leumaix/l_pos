import '../../reports/domain/sales_report.dart' show ReportRange;
import 'gift.dart';

class GiftsReport {
  final int totalForRange;

  const GiftsReport({required this.totalForRange});
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

bool _inRange(DateTime createdAt, ReportRange range, DateTime now) {
  switch (range) {
    case ReportRange.today:
      return _isSameDay(createdAt, now);
    case ReportRange.week:
      final start = _startOfDay(now).subtract(const Duration(days: 6));
      return !createdAt.isBefore(start);
    case ReportRange.month:
      final start = _startOfDay(now).subtract(const Duration(days: 29));
      return !createdAt.isBefore(start);
  }
}

/// Pure aggregation over an already-fetched gifts list — mirrors
/// buildExpensesReport's exact shape (expenses/domain/expenses_report.dart).
/// Deliberately shown SEPARATELY from revenue/net in Reports — a gift is
/// never revenue, so it's never subtracted into the net figure the way an
/// expense is (see that plan's own note on this).
GiftsReport buildGiftsReport(
  List<Gift> gifts, {
  required ReportRange range,
  required DateTime now,
}) {
  final inRange = gifts
      .where((gift) => _inRange(gift.createdAt, range, now))
      .toList();
  final totalForRange = inRange.fold(
    0,
    (sum, gift) => sum + gift.estimatedValueNaira,
  );
  return GiftsReport(totalForRange: totalForRange);
}
