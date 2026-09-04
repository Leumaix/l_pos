/// The current selling rate for gas, in naira per kilogram.
///
/// This is a business setting (e.g. ₦1,400/kg) — never hardcode a rate
/// value anywhere else. It only affects kg <-> unit conversions; it does
/// not change what is stored as stock (see [GasStock]).
class GasRate {
  final num nairaPerKg;

  const GasRate(this.nairaPerKg) : assert(nairaPerKg > 0, 'rate must be positive');

  @override
  String toString() => 'GasRate(₦$nairaPerKg/kg)';

  @override
  bool operator ==(Object other) => other is GasRate && other.nairaPerKg == nairaPerKg;

  @override
  int get hashCode => nairaPerKg.hashCode;
}
