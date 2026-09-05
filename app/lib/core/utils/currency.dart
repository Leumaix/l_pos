import 'package:intl/intl.dart';

final _nairaFormat = NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);

/// Formats a whole-naira integer amount as e.g. "₦5,000". Money throughout
/// Leumadepos is stored and passed around as whole naira integers — see
/// the Firestore data model notes.
String formatNaira(int amountNaira) => _nairaFormat.format(amountNaira);

String formatKg(double kg) => '${kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 2)} kg';

/// Formats a shift's cash-drawer variance the way the whole app talks
/// about it — never a bare signed number. Zero is "Exact", short/over
/// always spelled out (see the shift feature's OpenShift/ClosedShift).
String formatVariance(int varianceNaira) {
  if (varianceNaira == 0) return 'Exact';
  if (varianceNaira < 0) return '${formatNaira(-varianceNaira)} short';
  return '${formatNaira(varianceNaira)} over';
}
