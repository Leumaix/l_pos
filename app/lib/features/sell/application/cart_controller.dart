import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../domain/cart.dart';
import '../domain/product.dart';

/// Owns the in-progress sale's cart. All the actual stock-policy logic
/// lives in the pure functions in domain/cart.dart (and is unit-tested
/// there) — this controller just generates line ids, calls them, and
/// republishes the resulting [Cart] plus the outcome of the last action so
/// the Sell screen can react (e.g. show a snackbar for a block/warning).
class CartController extends StateNotifier<Cart> {
  CartController() : super(const Cart());

  int _nextId = 0;
  String _newLineId() => 'line-${_nextId++}';

  CartUpdateResult addGasAmount({required int amountNaira, required GasStock currentGasStock}) {
    final result = addGasByAmount(
      state,
      amountNaira: amountNaira,
      currentGasStock: currentGasStock,
      lineId: _newLineId(),
    );
    state = result.cart;
    return result;
  }

  CartUpdateResult addGasKg({
    required num kg,
    required GasStock currentGasStock,
    required GasRate rate,
  }) {
    final result = addGasByKg(
      state,
      kg: kg,
      currentGasStock: currentGasStock,
      rate: rate,
      lineId: _newLineId(),
    );
    state = result.cart;
    return result;
  }

  CartUpdateResult addCartProduct(Product product) {
    final result = addProduct(state, product, lineId: _newLineId());
    state = result.cart;
    return result;
  }

  void decrementCartProduct(String lineId) {
    state = decrementProduct(state, lineId).cart;
  }

  void removeCartLine(String lineId) {
    state = removeLine(state, lineId).cart;
  }

  void clear() {
    state = const Cart();
  }
}

final cartControllerProvider = StateNotifierProvider<CartController, Cart>(
  (ref) => CartController(),
);
