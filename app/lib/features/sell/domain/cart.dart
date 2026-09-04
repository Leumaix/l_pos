import 'package:gas_stock/gas_stock.dart';

import 'cart_line.dart';
import 'product.dart';

class Cart {
  final List<CartLine> lines;

  const Cart({this.lines = const []});

  int get subtotal => lines.fold(0, (sum, line) => sum + line.lineTotal);

  int get total => subtotal; // no tax/discount modeled for MVP

  bool get isEmpty => lines.isEmpty;

  Cart _withLines(List<CartLine> newLines) => Cart(lines: newLines);
}

/// The result of attempting to add or adjust a cart line.
///
/// Two independent stock policies apply here, per the business rule:
/// - Gas: never blocked. [oversellsGas] is a warning flag the UI should
///   surface (e.g. "this will take gas stock negative"); the sale still
///   proceeds — see gas_stock's oversell policy.
/// - Cylinders/accessories: hard-blocked. [blocked] is true and [cart] is
///   unchanged when the requested quantity would exceed [Product.stockCount].
class CartUpdateResult {
  final Cart cart;
  final bool blocked;
  final bool oversellsGas;
  final String? message;

  const CartUpdateResult({
    required this.cart,
    this.blocked = false,
    this.oversellsGas = false,
    this.message,
  });
}

/// Units already committed to gas lines already in the cart — subtracted
/// from on-hand stock before evaluating a new gas line, so a second or
/// third gas entry in the same cart is checked against what's actually
/// still left, not the pre-sale stock figure.
int _unitsCommittedInCart(Cart cart) {
  return cart.lines
      .whereType<GasCartLine>()
      .fold(0, (sum, line) => sum + line.unitsDeducted);
}

/// Adds a "by amount" gas line. Never blocked — see [CartUpdateResult] docs.
CartUpdateResult addGasByAmount(
  Cart cart, {
  required int amountNaira,
  required GasStock currentGasStock,
  required String lineId,
}) {
  final effectiveStock = GasStock(currentGasStock.units - _unitsCommittedInCart(cart));
  final sale = sellByAmount(effectiveStock, amountNaira);

  final line = GasCartLine(
    id: lineId,
    mode: GasSaleMode.amount,
    unitsDeducted: sale.unitsDeducted,
    oversells: sale.wentNegative,
  );

  return CartUpdateResult(
    cart: cart._withLines([...cart.lines, line]),
    oversellsGas: sale.wentNegative,
    message: sale.wentNegative ? 'This will take gas stock negative' : null,
  );
}

/// Adds a "by kg" gas line. Never blocked — see [CartUpdateResult] docs.
CartUpdateResult addGasByKg(
  Cart cart, {
  required num kg,
  required GasStock currentGasStock,
  required GasRate rate,
  required String lineId,
}) {
  final effectiveStock = GasStock(currentGasStock.units - _unitsCommittedInCart(cart));
  final sale = sellByKg(effectiveStock, kg, rate);

  final line = GasCartLine(
    id: lineId,
    mode: GasSaleMode.kg,
    kg: kg,
    unitsDeducted: sale.unitsDeducted,
    oversells: sale.wentNegative,
  );

  return CartUpdateResult(
    cart: cart._withLines([...cart.lines, line]),
    oversellsGas: sale.wentNegative,
    message: sale.wentNegative ? 'This will take gas stock negative' : null,
  );
}

int _quantityInCart(Cart cart, String productId) {
  return cart.lines
      .whereType<ProductCartLine>()
      .where((line) => line.product.id == productId)
      .fold(0, (sum, line) => sum + line.quantity);
}

/// Adds one unit of [product] to the cart, merging into an existing line
/// for that product if present. Hard-blocked (cart unchanged) if that
/// would exceed [Product.stockCount] — see [CartUpdateResult] docs.
CartUpdateResult addProduct(Cart cart, Product product, {required String lineId}) {
  final alreadyInCart = _quantityInCart(cart, product.id);
  if (alreadyInCart + 1 > product.stockCount) {
    return CartUpdateResult(
      cart: cart,
      blocked: true,
      message: 'Not enough ${product.name} in stock',
    );
  }

  final existingIndex = cart.lines.indexWhere(
    (line) => line is ProductCartLine && line.product.id == product.id,
  );

  if (existingIndex == -1) {
    final line = ProductCartLine(id: lineId, product: product, quantity: 1);
    return CartUpdateResult(cart: cart._withLines([...cart.lines, line]));
  }

  final updatedLines = [...cart.lines];
  final existing = updatedLines[existingIndex] as ProductCartLine;
  updatedLines[existingIndex] = existing.copyWith(quantity: existing.quantity + 1);
  return CartUpdateResult(cart: cart._withLines(updatedLines));
}

/// Removes one unit of a product line, dropping the line entirely once it
/// reaches zero. No stock check needed — removal can never oversell.
CartUpdateResult decrementProduct(Cart cart, String lineId) {
  final index = cart.lines.indexWhere((line) => line.id == lineId);
  if (index == -1) return CartUpdateResult(cart: cart);

  final line = cart.lines[index] as ProductCartLine;
  final updatedLines = [...cart.lines];
  if (line.quantity <= 1) {
    updatedLines.removeAt(index);
  } else {
    updatedLines[index] = line.copyWith(quantity: line.quantity - 1);
  }
  return CartUpdateResult(cart: cart._withLines(updatedLines));
}

/// Removes a line entirely, regardless of type.
CartUpdateResult removeLine(Cart cart, String lineId) {
  return CartUpdateResult(
    cart: cart._withLines(cart.lines.where((line) => line.id != lineId).toList()),
  );
}
