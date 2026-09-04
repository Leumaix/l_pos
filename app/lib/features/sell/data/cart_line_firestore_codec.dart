import '../domain/cart_line.dart';
import '../domain/product.dart';

/// Firestore snapshot encoding for a completed sale's cart lines.
///
/// A sale's items are a frozen record of what was sold, never a live
/// catalog reference (see Sale.items' doc comment) — so on the way back
/// out, a ProductCartLine's [Product] is reconstructed with placeholder
/// categoryId/stockCount/unit. Nothing that reads a decoded Sale
/// (receipt_screen.dart, reports/domain/sales_report.dart) touches those
/// fields, only name/lineTotal/quantity, so this is safe.
Map<String, dynamic> cartLineToMap(CartLine line) {
  return switch (line) {
    GasCartLine() => {
      'id': line.id,
      'type': 'gas',
      'name': line.name,
      'lineTotal': line.lineTotal,
      'mode': line.mode == GasSaleMode.kg ? 'kg' : 'amount',
      'kg': line.kg,
      'unitsDeducted': line.unitsDeducted,
      'oversells': line.oversells,
    },
    ProductCartLine() => {
      'id': line.id,
      'type': 'product',
      'name': line.name,
      'lineTotal': line.lineTotal,
      'productId': line.product.id,
      'quantity': line.quantity,
      'unitPrice': line.product.price,
    },
  };
}

CartLine cartLineFromMap(Map<String, dynamic> map) {
  final type = map['type'] as String;
  if (type == 'gas') {
    return GasCartLine(
      id: map['id'] as String,
      mode: map['mode'] == 'kg' ? GasSaleMode.kg : GasSaleMode.amount,
      kg: map['kg'] as num?,
      unitsDeducted: (map['unitsDeducted'] as num).toInt(),
      oversells: map['oversells'] as bool,
    );
  }
  if (type == 'product') {
    final unitPrice = (map['unitPrice'] as num).toInt();
    return ProductCartLine(
      id: map['id'] as String,
      quantity: (map['quantity'] as num).toInt(),
      // Placeholder — not a live catalog reference, see this file's doc
      // comment. categoryId/stockCount/unit are never read back from a
      // decoded Sale.
      product: Product(
        id: map['productId'] as String,
        categoryId: '',
        name: map['name'] as String,
        price: unitPrice,
        stockCount: 0,
      ),
    );
  }
  throw ArgumentError.value(type, 'type', 'unknown cart line type');
}
