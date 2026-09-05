import 'dart:async';

import '../../../core/business_config.dart';
import '../../../core/utils/replay_stream.dart';

/// Business-wide settings an owner can edit in-app — just the gas tank
/// capacity. The gas RATE is also owner-editable, but lives on
/// InventoryRepository instead (see InventoryRepository.changeGasRate):
/// stock is tracked internally in "units" pegged to the rate, so a rate
/// change has to atomically recompute existing stock alongside it, unlike
/// this plain field swap.
abstract class BusinessRepository {
  Stream<double> watchGasTankCapacityKg();

  /// Updates only `settings.gasTankCapacityKg` on the business doc — never
  /// the whole document. This purely feeds the Stock screen's "% full"
  /// gauge; it doesn't touch stock-tracking math at all, which is why it's
  /// safe to make owner-editable on its own.
  Future<void> updateGasTankCapacityKg(double capacityKg);
}

class FakeBusinessRepository implements BusinessRepository {
  double _capacityKg;
  final _controller = StreamController<double>.broadcast();

  FakeBusinessRepository({double initialCapacityKg = kDefaultGasTankCapacityKg})
    : _capacityKg = initialCapacityKg;

  /// Synchronous access for tests — avoids awaiting the stream directly
  /// (a bare `.first` await outside a widget pump can hang under
  /// AutomatedTestWidgetsFlutterBinding's fake clock; see the pattern
  /// used by InventoryRepository.currentGasStock/currentProducts).
  double get currentCapacityKg => _capacityKg;

  @override
  Stream<double> watchGasTankCapacityKg() => replayLatest(() => _capacityKg, _controller.stream);

  @override
  Future<void> updateGasTankCapacityKg(double capacityKg) async {
    _capacityKg = capacityKg;
    _controller.add(_capacityKg);
  }
}
