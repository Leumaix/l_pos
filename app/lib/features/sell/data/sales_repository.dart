import 'dart:async';

import '../../../core/utils/replay_stream.dart';
import '../domain/sale.dart';

/// The record of completed sales — what Reports will read from later.
/// [recordSale] is called only once a checkout has already been validated
/// and committed elsewhere (see CheckoutController); this repository just
/// persists the result.
abstract class SalesRepository {
  Stream<List<Sale>> watchSales();
  Future<void> recordSale(Sale sale);
}

class FakeSalesRepository implements SalesRepository {
  final List<Sale> _sales = [];
  final _controller = StreamController<List<Sale>>.broadcast();

  @override
  Stream<List<Sale>> watchSales() =>
      replayLatest(() => List.unmodifiable(_sales), _controller.stream);

  @override
  Future<void> recordSale(Sale sale) async {
    _sales.add(sale);
    _controller.add(List.unmodifiable(_sales));
  }
}
