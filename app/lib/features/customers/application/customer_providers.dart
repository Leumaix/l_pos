import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/customer_repository.dart';
import '../data/firebase_customer_repository.dart';

/// Real, Firestore-backed by default — the "one-line swap" this app uses
/// everywhere. Widget tests override this explicitly with
/// FakeCustomerRepository, same pattern as every other repository here.
final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => FirebaseCustomerRepository(ref.watch(firebaseAuthRepositoryProvider)),
);

final customersProvider = StreamProvider(
  (ref) => ref.watch(customerRepositoryProvider).watchCustomers(),
);

final customerTransactionsProvider = StreamProvider.family(
  (ref, String customerId) => ref.watch(customerRepositoryProvider).watchTransactions(customerId),
);
