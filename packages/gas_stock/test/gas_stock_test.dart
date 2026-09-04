import 'package:gas_stock/gas_stock.dart';
import 'package:test/test.dart';

void main() {
  const rate = GasRate(1400);

  group('sellByAmount — exact, no rounding', () {
    test('deducts exactly the amount paid', () {
      final result = sellByAmount(const GasStock(28000), 5000);
      expect(result.unitsDeducted, 5000);
      expect(result.stock.units, 23000);
      expect(result.wentNegative, isFalse);
    });

    test('repeated amount sales never drift', () {
      // ₦5,000 / ₦1,400/kg = 3.571428... kg — the classic rounding trap.
      // The units model must never approximate this: three ₦5,000 sales
      // must remove exactly 15,000 units, not 15,000 ± rounding error.
      var stock = const GasStock(20000);
      for (var i = 0; i < 3; i++) {
        stock = sellByAmount(stock, 5000).stock;
      }
      expect(stock.units, 20000 - 15000);
    });

    test('rejects non-positive amounts', () {
      expect(() => sellByAmount(const GasStock(1000), 0), throwsArgumentError);
      expect(() => sellByAmount(const GasStock(1000), -500), throwsArgumentError);
    });
  });

  group('sellByKg — rounds to nearest unit', () {
    test('exact kg amounts convert cleanly', () {
      final result = sellByKg(const GasStock(10000), 2.5, rate);
      expect(result.unitsDeducted, 3500);
      expect(result.stock.units, 6500);
    });

    test('fractional kg rounds to the nearest whole unit', () {
      // 1.2345 kg * 1400 = 1728.3 -> rounds to 1728
      final result = sellByKg(const GasStock(5000), 1.2345, rate);
      expect(result.unitsDeducted, 1728);
    });

    test('half-unit boundary rounds consistently with num.round()', () {
      const halfUnitRate = GasRate(2); // 0.25kg * 2 = 0.5 exactly
      final result = sellByKg(const GasStock(1000), 0.25, halfUnitRate);
      expect(result.unitsDeducted, 0.5.round()); // documents actual platform rounding behavior
    });

    test('rejects non-positive kg', () {
      expect(() => sellByKg(const GasStock(1000), 0, rate), throwsArgumentError);
      expect(() => sellByKg(const GasStock(1000), -2, rate), throwsArgumentError);
    });
  });

  group('restock — additive, never overwrites', () {
    test('adds on top of existing non-zero stock', () {
      final result = restock(const GasStock(4000), 10, rate); // +14000
      expect(result.unitsAdded, 14000);
      expect(result.stock.units, 18000);
    });

    test('adds on top of zero stock', () {
      final result = restock(GasStock.zero, 5, rate);
      expect(result.stock.units, 7000);
    });

    test('multiple restocks accumulate rather than replace', () {
      var stock = const GasStock(2000);
      stock = restock(stock, 3, rate).stock; // +4200 -> 6200
      stock = restock(stock, 7, rate).stock; // +9800 -> 16000
      expect(stock.units, 16000);
    });

    test('restock never loses leftover stock, even after a sale', () {
      var stock = const GasStock(28000);
      stock = sellByKg(stock, 5, rate).stock; // -7000 -> 21000 leftover
      stock = restock(stock, 20, rate).stock; // +28000 -> 49000
      expect(stock.units, 49000);
    });

    test('rejects non-positive deliveries', () {
      expect(() => restock(const GasStock(1000), 0, rate), throwsArgumentError);
      expect(() => restock(const GasStock(1000), -1, rate), throwsArgumentError);
    });
  });

  group('oversell policy — gas allows negative stock with a warning flag', () {
    test('sellByAmount can push stock negative without throwing', () {
      final result = sellByAmount(const GasStock(1000), 5000);
      expect(result.stock.units, -4000);
      expect(result.wentNegative, isTrue);
    });

    test('sellByKg can push stock negative without throwing', () {
      final result = sellByKg(const GasStock(1000), 5, rate); // needs 7000
      expect(result.stock.units, -6000);
      expect(result.wentNegative, isTrue);
    });

    test('wentNegative is false when a sale lands exactly on zero', () {
      final result = sellByAmount(const GasStock(5000), 5000);
      expect(result.stock.units, 0);
      expect(result.wentNegative, isFalse);
    });

    test('wouldGoNegative previews the outcome before committing', () {
      const stock = GasStock(1000);
      expect(wouldGoNegative(stock, 1000), isFalse); // lands exactly on 0
      expect(wouldGoNegative(stock, 1001), isTrue);
      expect(wouldGoNegative(stock, 999), isFalse);
    });
  });

  group('display conversions — derived, never stored', () {
    test('kgRemaining divides units by rate', () {
      expect(kgRemaining(const GasStock(28000), rate), 20.0);
    });

    test('kgRemaining reflects the repeating-decimal case precisely as a double', () {
      expect(kgRemaining(const GasStock(5000), rate), closeTo(3.571428571, 1e-9));
    });

    test('kgRemaining is negative when stock has been oversold — a reconciliation flag, not an error', () {
      expect(kgRemaining(const GasStock(-2800), rate), -2.0);
    });

    test('displayKgForAmount approximates an amount sale for receipt display only', () {
      expect(displayKgForAmount(5000, rate), closeTo(3.571428571, 1e-9));
    });

    test('display helpers never mutate or depend on stock state', () {
      const stock = GasStock(28000);
      final before = stock.units;
      kgRemaining(stock, rate);
      displayKgForAmount(5000, rate);
      expect(stock.units, before);
    });
  });

  group('end-to-end scenario', () {
    test('a realistic sequence of restocks and sales stays exact throughout', () {
      var stock = GasStock.zero;

      stock = restock(stock, 20, rate).stock; // delivery: 20kg -> +28000
      expect(stock.units, 28000);

      stock = sellByAmount(stock, 5000).stock; // ₦5,000 worth -> -5000
      expect(stock.units, 23000);

      stock = sellByKg(stock, 2, rate).stock; // 2kg -> -2800
      expect(stock.units, 20200);

      stock = restock(stock, 10, rate).stock; // top-up delivery: +14000
      expect(stock.units, 34200);

      expect(kgRemaining(stock, rate), closeTo(24.428571429, 1e-9));
    });
  });
}
