import 'package:flutter_test/flutter_test.dart';
import 'package:gas_stock/gas_stock.dart';
import 'package:leumadepos/features/sell/domain/cart.dart';
import 'package:leumadepos/features/sell/domain/cart_line.dart';
import 'package:leumadepos/features/sell/domain/product.dart';

void main() {
  const rate = GasRate(1400);
  const cylinder6kg = Product(
    id: 'cyl-6kg',
    categoryId: 'cat-cylinders',
    name: '6kg Cylinder',
    price: 15000,
    stockCount: 3,
  );

  group('gas lines — warn-but-allow oversell policy', () {
    test('adding within stock succeeds with no warning', () {
      final result = addGasByAmount(
        const Cart(),
        amountNaira: 5000,
        currentGasStock: const GasStock(28000),
        lineId: 'l1',
      );

      expect(result.blocked, isFalse);
      expect(result.oversellsGas, isFalse);
      expect(result.cart.lines, hasLength(1));
      expect(result.cart.total, 5000);
    });

    test(
      'a by-amount sale that exceeds stock is still added, with a warning',
      () {
        final result = addGasByAmount(
          const Cart(),
          amountNaira: 5000,
          currentGasStock: const GasStock(1000),
          lineId: 'l1',
        );

        expect(result.blocked, isFalse); // never blocked for gas
        expect(result.oversellsGas, isTrue);
        expect(result.message, isNotNull);
        expect(result.cart.lines, hasLength(1)); // line was still added
        expect(result.cart.total, 5000); // customer is still charged in full
      },
    );

    test('a by-kg sale that exceeds stock is still added, with a warning', () {
      final result = addGasByKg(
        const Cart(),
        kg: 5,
        currentGasStock: const GasStock(1000), // needs 7000 units
        rate: rate,
        lineId: 'l1',
      );

      expect(result.blocked, isFalse);
      expect(result.oversellsGas, isTrue);
      expect(result.cart.lines.single, isA<GasCartLine>());
      expect((result.cart.lines.single as GasCartLine).unitsDeducted, 7000);
    });

    test('a second gas line is checked against stock minus what the first '
        'line already committed, not the original stock figure', () {
      final afterFirst = addGasByAmount(
        const Cart(),
        amountNaira: 6000,
        currentGasStock: const GasStock(10000),
        lineId: 'l1',
      );
      expect(
        afterFirst.oversellsGas,
        isFalse,
      ); // 10000 - 6000 = 4000 left, fine

      final afterSecond = addGasByAmount(
        afterFirst.cart,
        amountNaira: 6000,
        currentGasStock: const GasStock(10000), // same on-hand stock figure
        lineId: 'l2',
      );

      // 4000 remaining after the first line, second line needs 6000 -> negative.
      expect(afterSecond.oversellsGas, isTrue);
      expect(afterSecond.cart.lines, hasLength(2));
      expect(afterSecond.cart.total, 12000);
    });

    test('exact stock match is not flagged as an oversell', () {
      final result = addGasByAmount(
        const Cart(),
        amountNaira: 5000,
        currentGasStock: const GasStock(5000),
        lineId: 'l1',
      );
      expect(result.oversellsGas, isFalse);
    });
  });

  group(
    'product lines (cylinders/accessories) — hard-block oversell policy',
    () {
      test('adding within stock succeeds', () {
        final result = addProduct(const Cart(), cylinder6kg, lineId: 'l1');

        expect(result.blocked, isFalse);
        expect(result.cart.lines, hasLength(1));
        expect((result.cart.lines.single as ProductCartLine).quantity, 1);
        expect(result.cart.total, 15000);
      });

      test('adding the same product again merges into one line', () {
        final first = addProduct(const Cart(), cylinder6kg, lineId: 'l1');
        final second = addProduct(first.cart, cylinder6kg, lineId: 'l2');

        expect(second.blocked, isFalse);
        expect(second.cart.lines, hasLength(1)); // merged, not a second line
        expect((second.cart.lines.single as ProductCartLine).quantity, 2);
        expect(second.cart.total, 30000);
      });

      test('adding up to exactly the stock count succeeds every time', () {
        var cart = const Cart();
        for (var i = 0; i < cylinder6kg.stockCount; i++) {
          final result = addProduct(cart, cylinder6kg, lineId: 'l$i');
          expect(
            result.blocked,
            isFalse,
            reason: 'add #$i should still fit in stock',
          );
          cart = result.cart;
        }
        expect(
          (cart.lines.single as ProductCartLine).quantity,
          cylinder6kg.stockCount,
        );
      });

      test(
        'adding beyond stock count is blocked and the cart is unchanged',
        () {
          var cart = const Cart();
          for (var i = 0; i < cylinder6kg.stockCount; i++) {
            cart = addProduct(cart, cylinder6kg, lineId: 'l$i').cart;
          }

          final blockedResult = addProduct(cart, cylinder6kg, lineId: 'l-over');

          expect(blockedResult.blocked, isTrue);
          expect(
            blockedResult.oversellsGas,
            isFalse,
          ); // this is the product policy, not gas's
          expect(blockedResult.message, isNotNull);
          expect(
            blockedResult.cart.lines,
            same(cart.lines),
          ); // cart is untouched
          expect(
            (blockedResult.cart.lines.single as ProductCartLine).quantity,
            cylinder6kg.stockCount,
          );
        },
      );

      test('a zero-stock product is blocked on the very first add', () {
        const outOfStock = Product(
          id: 'lighter',
          categoryId: 'cat-accessories',
          name: 'Lighter',
          price: 300,
          stockCount: 0,
        );

        final result = addProduct(const Cart(), outOfStock, lineId: 'l1');

        expect(result.blocked, isTrue);
        expect(result.cart.lines, isEmpty);
      });

      test('decrementing reduces quantity, then removes the line at zero', () {
        var cart = addProduct(const Cart(), cylinder6kg, lineId: 'l1').cart;
        cart = addProduct(cart, cylinder6kg, lineId: 'l2').cart; // quantity 2

        cart = decrementProduct(cart, 'l1').cart;
        expect((cart.lines.single as ProductCartLine).quantity, 1);

        cart = decrementProduct(cart, 'l1').cart;
        expect(cart.lines, isEmpty);
      });

      test(
        'decrementing frees up capacity for a subsequent hard-blocked add',
        () {
          var cart = const Cart();
          for (var i = 0; i < cylinder6kg.stockCount; i++) {
            cart = addProduct(cart, cylinder6kg, lineId: 'l$i').cart;
          }
          expect(addProduct(cart, cylinder6kg, lineId: 'over').blocked, isTrue);

          cart = decrementProduct(cart, 'l0').cart;
          final result = addProduct(cart, cylinder6kg, lineId: 'l-again');

          expect(result.blocked, isFalse);
          expect(
            (result.cart.lines.single as ProductCartLine).quantity,
            cylinder6kg.stockCount,
          );
        },
      );
    },
  );

  group('removeLine — works uniformly across gas and product lines', () {
    test('removes a gas line by id', () {
      final withGas = addGasByAmount(
        const Cart(),
        amountNaira: 3000,
        currentGasStock: const GasStock(10000),
        lineId: 'gas-1',
      ).cart;

      final result = removeLine(withGas, 'gas-1');
      expect(result.cart.lines, isEmpty);
    });

    test('removes a product line by id regardless of quantity', () {
      var cart = addProduct(const Cart(), cylinder6kg, lineId: 'l1').cart;
      cart = addProduct(cart, cylinder6kg, lineId: 'l2').cart; // quantity 2

      final result = removeLine(cart, 'l1');
      expect(result.cart.lines, isEmpty);
    });
  });

  group('mixed cart totals', () {
    test('subtotal and total sum gas and product lines together', () {
      var cart = addGasByAmount(
        const Cart(),
        amountNaira: 5000,
        currentGasStock: const GasStock(28000),
        lineId: 'gas-1',
      ).cart;
      cart = addProduct(cart, cylinder6kg, lineId: 'p1').cart;

      expect(cart.subtotal, 5000 + 15000);
      expect(cart.total, 20000);
    });
  });
}
