/// Gas stock, tracked internally in "units".
///
/// 1 unit = ₦1 worth of gas at the current [GasRate]. This is the only
/// representation ever persisted. Kilograms are always derived (see
/// [kgRemaining]), never stored — that's what keeps "sell ₦5,000 worth"
/// exact instead of landing on a repeating decimal.
///
/// [units] can go negative. That is intentional: an oversold gas sale is
/// allowed to complete (see [sellByAmount], [sellByKg]) and a negative
/// balance is a visible signal that stock needs reconciling, not an error
/// state to hide.
class GasStock {
  final int units;

  const GasStock(this.units);

  static const zero = GasStock(0);

  @override
  String toString() => 'GasStock(units: $units)';

  @override
  bool operator ==(Object other) => other is GasStock && other.units == units;

  @override
  int get hashCode => units.hashCode;
}
