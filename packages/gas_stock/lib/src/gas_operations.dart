import 'gas_rate.dart';
import 'gas_stock.dart';

/// The result of a gas sale: the resulting stock, how many units it took,
/// and whether it pushed stock below zero (an oversell — allowed, but the
/// caller should surface [wentNegative] as a warning).
class GasSaleResult {
  final GasStock stock;
  final int unitsDeducted;
  final bool wentNegative;

  const GasSaleResult({
    required this.stock,
    required this.unitsDeducted,
    required this.wentNegative,
  });
}

/// The result of a restock: the resulting stock and how many units the
/// delivery added.
class GasRestockResult {
  final GasStock stock;
  final int unitsAdded;

  const GasRestockResult({required this.stock, required this.unitsAdded});
}

/// The number of units a [kg] quantity is worth at [rate], rounded to the
/// nearest whole unit. Shared by [sellByKg], [restock], and any UI that
/// needs to preview a conversion before committing.
int unitsForKg(num kg, GasRate rate) => (kg * rate.nairaPerKg).round();

/// Sell gas "by amount": deducts exactly [amountNaira] units. No rounding
/// is ever applied here — the naira amount the customer paid and the units
/// deducted are the same number, by construction.
///
/// Allowed to take [GasStock.units] negative (see [GasStock] docs); throws
/// [ArgumentError] only for a non-positive [amountNaira], which is an
/// invalid input, not a business-policy question.
GasSaleResult sellByAmount(GasStock stock, int amountNaira) {
  if (amountNaira <= 0) {
    throw ArgumentError.value(amountNaira, 'amountNaira', 'must be positive');
  }
  final newUnits = stock.units - amountNaira;
  return GasSaleResult(
    stock: GasStock(newUnits),
    unitsDeducted: amountNaira,
    wentNegative: newUnits < 0,
  );
}

/// Sell gas "by kg": deducts `round(kg * rate)` units. The kg value itself
/// is what gets displayed as the line item ("X kg") — it is never
/// recomputed from stock.
///
/// Allowed to take [GasStock.units] negative; throws [ArgumentError] only
/// for a non-positive [kg].
GasSaleResult sellByKg(GasStock stock, num kg, GasRate rate) {
  if (kg <= 0) {
    throw ArgumentError.value(kg, 'kg', 'must be positive');
  }
  final unitsToDeduct = unitsForKg(kg, rate);
  final newUnits = stock.units - unitsToDeduct;
  return GasSaleResult(
    stock: GasStock(newUnits),
    unitsDeducted: unitsToDeduct,
    wentNegative: newUnits < 0,
  );
}

/// The result of a rate change: the resulting stock (re-expressed at the
/// new rate) and the physical kg that was preserved across the change.
class GasRateChangeResult {
  final GasStock stock;
  final double preservedKg;

  const GasRateChangeResult({required this.stock, required this.preservedKg});
}

/// Changes the rate WITHOUT changing the physical kg [stock] represents:
/// first derives the current kg at [oldRate] (exactly what [kgRemaining]
/// would show), then re-expresses that same kg as units at [newRate]. The
/// kg value itself never changes — only how many units it takes to record
/// it. Rounds the same way [sellByKg]/[restock] do (nearest whole unit via
/// [unitsForKg]), so this can shift the recorded units by at most 1 unit
/// (a fraction of a naira) versus the mathematically exact kg.
///
/// Works the same whether [stock] is currently non-negative or already
/// oversold (negative) — kg preservation doesn't care about sign, it just
/// carries whatever the current reconciliation state is over to the new
/// rate unchanged.
GasRateChangeResult changeRate(GasStock stock, GasRate oldRate, GasRate newRate) {
  final kg = kgRemaining(stock, oldRate);
  final newUnits = unitsForKg(kg, newRate);
  return GasRateChangeResult(stock: GasStock(newUnits), preservedKg: kg);
}

/// Restock: adds `round(kgDelivered * rate)` units ON TOP OF whatever
/// [stock] already holds. Never overwrites or replaces existing stock —
/// leftover gas from before a delivery is preserved.
///
/// Throws [ArgumentError] for a non-positive [kgDelivered].
GasRestockResult restock(GasStock stock, num kgDelivered, GasRate rate) {
  if (kgDelivered <= 0) {
    throw ArgumentError.value(kgDelivered, 'kgDelivered', 'must be positive');
  }
  final unitsAdded = unitsForKg(kgDelivered, rate);
  return GasRestockResult(
    stock: GasStock(stock.units + unitsAdded),
    unitsAdded: unitsAdded,
  );
}

/// Display-only: how many kg [stock] represents at [rate]. This is a
/// derived readout, computed fresh every time — never store this value.
/// Can be negative if stock has been oversold; that is meaningful (it
/// flags gas needing reconciliation), not an error.
double kgRemaining(GasStock stock, GasRate rate) => stock.units / rate.nairaPerKg;

/// Display-only: the approximate kg an amount-based sale line item
/// represents, e.g. for a receipt showing "₦5,000 (~3.57 kg)". Purely
/// cosmetic — never used for stock math, which stays exact in units.
double displayKgForAmount(int amountNaira, GasRate rate) => amountNaira / rate.nairaPerKg;

/// Pure check a caller (typically the Sell screen) can consult before
/// confirming a sale, to decide whether to show an oversell warning.
bool wouldGoNegative(GasStock stock, int unitsToDeduct) => stock.units - unitsToDeduct < 0;
