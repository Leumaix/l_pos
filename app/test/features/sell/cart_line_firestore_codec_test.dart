import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/sell/data/cart_line_firestore_codec.dart';
import 'package:leumadepos/features/sell/domain/cart_line.dart';
import 'package:leumadepos/features/sell/domain/product.dart';

void main() {
  group('cartLineToMap / cartLineFromMap round-trip', () {
    test('a gas line (by kg) survives the round trip', () {
      const line = GasCartLine(id: 'line-1', mode: GasSaleMode.kg, kg: 5.5, unitsDeducted: 7700, oversells: false);

      final decoded = cartLineFromMap(cartLineToMap(line));

      expect(decoded, isA<GasCartLine>());
      final gas = decoded as GasCartLine;
      expect(gas.id, 'line-1');
      expect(gas.mode, GasSaleMode.kg);
      expect(gas.kg, 5.5);
      expect(gas.unitsDeducted, 7700);
      expect(gas.oversells, isFalse);
      expect(gas.name, line.name);
      expect(gas.lineTotal, line.lineTotal);
    });

    test('a gas line (by amount) survives the round trip, including an oversell flag', () {
      const line = GasCartLine(id: 'line-2', mode: GasSaleMode.amount, unitsDeducted: 5000, oversells: true);

      final decoded = cartLineFromMap(cartLineToMap(line)) as GasCartLine;

      expect(decoded.mode, GasSaleMode.amount);
      expect(decoded.kg, isNull);
      expect(decoded.unitsDeducted, 5000);
      expect(decoded.oversells, isTrue);
    });

    test('a product line survives the round trip', () {
      const product = Product(
        id: 'prod-1',
        categoryId: 'cat-cylinders',
        name: '3kg Cylinder',
        price: 8500,
        stockCount: 12,
        unit: ProductUnit.piece,
      );
      const line = ProductCartLine(id: 'line-3', product: product, quantity: 2);

      final decoded = cartLineFromMap(cartLineToMap(line)) as ProductCartLine;

      expect(decoded.id, 'line-3');
      expect(decoded.quantity, 2);
      expect(decoded.product.id, 'prod-1');
      expect(decoded.product.name, '3kg Cylinder');
      expect(decoded.product.price, 8500);
      expect(decoded.name, line.name);
      expect(decoded.lineTotal, line.lineTotal);
    });

    test('an unknown type throws rather than silently returning garbage', () {
      expect(() => cartLineFromMap({'type': 'mystery'}), throwsArgumentError);
    });
  });
}
