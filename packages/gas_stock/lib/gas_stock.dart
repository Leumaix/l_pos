/// Pure gas pricing/stock logic for Leumadepos: no Firebase, no UI.
/// Stock is tracked in integer "units" (1 unit = ₦1 of gas at the current
/// rate) so amount-based sales never round. See [GasStock] and the
/// functions in gas_operations.dart for the details.
library;

export 'src/gas_rate.dart';
export 'src/gas_stock.dart';
export 'src/gas_operations.dart';
