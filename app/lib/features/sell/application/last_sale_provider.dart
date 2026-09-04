import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sale.dart';

/// Holds the most recently completed sale so the Receipt screen can read
/// it after Payment navigates there — a simple hand-off since there's no
/// backend to fetch a just-created sale by id from yet.
final lastSaleProvider = StateProvider<Sale?>((ref) => null);
