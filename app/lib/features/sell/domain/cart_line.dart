import 'product.dart';

enum GasSaleMode { kg, amount }

/// A line in the cart: either gas (priced by weight or by amount) or a
/// discrete product (cylinder/accessory, priced by quantity).
sealed class CartLine {
  String get id;
  String get name;
  int get lineTotal;

  const CartLine();
}

/// One gas line item. [unitsDeducted] is always exactly what the customer
/// is charged in naira — that's the whole point of the units system (see
/// package:gas_stock): 1 unit = ₦1, so naira paid and units deducted are
/// the same number, whether the line came from a kg entry (rounded) or an
/// amount entry (exact).
class GasCartLine extends CartLine {
  @override
  final String id;
  final GasSaleMode mode;
  final num? kg; // set only for GasSaleMode.kg; the display value, verbatim
  final int unitsDeducted;
  final bool oversells; // this line alone would take gas stock negative

  const GasCartLine({
    required this.id,
    required this.mode,
    required this.unitsDeducted,
    required this.oversells,
    this.kg,
  });

  @override
  String get name {
    if (mode != GasSaleMode.kg) return 'Gas (by amount)';
    final k = kg!;
    final isWhole = k == k.truncateToDouble();
    return '${k.toStringAsFixed(isWhole ? 0 : 2)} kg gas';
  }

  @override
  int get lineTotal => unitsDeducted;
}

/// One cylinder/accessory line item — a product and how many of it.
class ProductCartLine extends CartLine {
  @override
  final String id;
  final Product product;
  final int quantity;

  const ProductCartLine({required this.id, required this.product, required this.quantity});

  @override
  String get name => product.name;

  @override
  int get lineTotal => product.price * quantity;

  ProductCartLine copyWith({int? quantity}) =>
      ProductCartLine(id: id, product: product, quantity: quantity ?? this.quantity);
}
