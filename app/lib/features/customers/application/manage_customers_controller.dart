import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/customer.dart';
import 'customer_providers.dart';

/// Thin pass-through to CustomerRepository — same shape as
/// ManageCatalogController and RestockController. Unlike the catalog,
/// this is NOT owner-only: any active staff member can add a walk-in
/// customer on the spot (see firestore.rules' /customers write rule).
class ManageCustomersController {
  final Ref ref;

  ManageCustomersController(this.ref);

  Future<Customer> createCustomer({
    required String name,
    required String phone,
    int openingBalanceNaira = 0,
  }) => ref
      .read(customerRepositoryProvider)
      .createCustomer(name: name, phone: phone, openingBalanceNaira: openingBalanceNaira);
}

final manageCustomersControllerProvider = Provider((ref) => ManageCustomersController(ref));
