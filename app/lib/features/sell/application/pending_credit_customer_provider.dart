import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../customers/domain/customer.dart';

/// Set by Customer detail's "Record sale" action, right before navigating
/// to Sell, to hand off which customer the sale is for. Payment reads and
/// clears this exactly once (in initState), pre-selecting Customer
/// Account + that customer so staff don't have to search for them again
/// — the sale itself still goes through the normal cart, still decrements
/// stock/gas like any other sale. "Record sale" from Customer detail is
/// not a separate stock-free path; it's a shortcut into the same one.
final pendingCreditCustomerProvider = StateProvider<Customer?>((ref) => null);
