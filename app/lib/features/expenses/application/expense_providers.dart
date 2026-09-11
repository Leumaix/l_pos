import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/expense_repository.dart';

/// Same "one-line swap" pattern as checkout/shift/auth: real by default,
/// overridden with FakeExpenseRepository in tests.
final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => FirebaseExpenseRepository(ref.watch(authRepositoryProvider)),
);
