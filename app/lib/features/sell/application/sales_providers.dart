import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/firebase_sales_repository.dart';
import '../data/sales_repository.dart';

/// Real, Firestore-backed by default — the "one-line swap" this app uses
/// everywhere. Widget tests override this explicitly with
/// FakeSalesRepository (see test/widget_test.dart and friends), same
/// pattern as every other repository here.
final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => FirebaseSalesRepository(ref.watch(firebaseAuthRepositoryProvider)),
);

final salesProvider = StreamProvider((ref) => ref.watch(salesRepositoryProvider).watchSales());
